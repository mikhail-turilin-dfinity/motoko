// This module is only enabled when compiling the RTS for IC or WASI.

use super::Memory;
use crate::constants::WASM_PAGE_SIZE;
use crate::gc::incremental::free_list::Heap;
use crate::gc::incremental::free_list::SegregatedFreeList;
use crate::gc::incremental::IncrementalGC;
use crate::gc::incremental::FREE_LIST;
use crate::rts_trap_with;
use crate::types::*;

use core::arch::wasm32;

/// Maximum live data retained in a GC.
pub(crate) static mut MAX_LIVE: Bytes<u32> = Bytes(0);

/// Amount of garbage collected so far.
pub(crate) static mut RECLAIMED: Bytes<u64> = Bytes(0);

/// Counter for total allocations
pub(crate) static mut ALLOCATED: Bytes<u64> = Bytes(0);

/// Heap pointer
pub(crate) static mut HP: u32 = 0;

/// Heap pointer after last GC
pub(crate) static mut LAST_HP: u32 = 0;

// Provided by generated code
extern "C" {
    pub(crate) fn get_heap_base() -> u32;
    pub(crate) fn get_static_roots() -> Value;
}

pub(crate) unsafe fn get_aligned_heap_base() -> u32 {
    // align to 32 bytes
    ((get_heap_base() + 31) / 32) * 32
}

#[no_mangle]
unsafe extern "C" fn init(align: bool, use_free_list: bool) {
    HP = if align {
        get_aligned_heap_base()
    } else {
        get_heap_base()
    };
    LAST_HP = HP;
    if use_free_list {
        FREE_LIST = Some(SegregatedFreeList::new());
    }
}

#[no_mangle]
unsafe extern "C" fn get_max_live_size() -> Bytes<u32> {
    MAX_LIVE
}

#[no_mangle]
unsafe extern "C" fn get_reclaimed() -> Bytes<u64> {
    RECLAIMED
}

#[no_mangle]
unsafe extern "C" fn get_total_allocations() -> Bytes<u64> {
    ALLOCATED
}

#[no_mangle]
unsafe extern "C" fn get_heap_size() -> Bytes<u32> {
    Bytes(HP - get_aligned_heap_base())
}

/// Provides a `Memory` implementation, to be used in functions compiled for IC or WASI. The
/// `Memory` implementation allocates in Wasm heap with Wasm `memory.grow` instruction.
pub struct IcMemory;

impl Memory for IcMemory {
    #[inline]
    unsafe fn mutator_alloc(&mut self, amount: Words<u32>) -> Value {
        if FREE_LIST.is_some() {
            IncrementalGC::allocation_increment(self);
        }
        allocate(amount)
    }

    #[inline]
    unsafe fn collector_alloc(&mut self, amount: Words<u32>) -> Value {
        allocate(amount)
    }
}

#[inline]
unsafe fn allocate(amount: Words<u32>) -> Value {
    ALLOCATED += Bytes(u64::from(amount.to_bytes().as_u32()));
    match &mut FREE_LIST {
        Some(free_list) => free_list.allocate(&mut IC_HEAP, amount.to_bytes()),
        None => allocate_at_heap_end(amount),
    }
}

static mut IC_HEAP: IcHeap = IcHeap {};

struct IcHeap;

impl Heap for IcHeap {
    #[inline]
    unsafe fn grow_heap(&mut self, n: Words<u32>) -> Value {
        allocate_at_heap_end(n)
    }
}

#[inline]
unsafe fn allocate_at_heap_end(n: Words<u32>) -> Value {
    let bytes = n.to_bytes();
    let delta = u64::from(bytes.as_u32());

    // Update heap pointer
    let old_hp = u64::from(HP);
    let new_hp = old_hp + delta;

    // Grow memory if needed
    grow_memory(new_hp);

    debug_assert!(new_hp <= u64::from(core::u32::MAX));
    HP = new_hp as u32;

    Value::from_ptr(old_hp as usize)
}

/// Page allocation. Ensures that the memory up to, but excluding, the given pointer is allocated.
#[inline(never)]
unsafe fn grow_memory(ptr: u64) {
    debug_assert!(ptr <= 2 * u64::from(core::u32::MAX));
    let page_size = u64::from(WASM_PAGE_SIZE.as_u32());
    let total_pages_needed = ((ptr + page_size - 1) / page_size) as usize;
    let current_pages = wasm32::memory_size(0);
    if total_pages_needed > current_pages {
        #[allow(clippy::collapsible_if)] // faster by 1% if not colapsed with &&
        if wasm32::memory_grow(0, total_pages_needed - current_pages) == core::usize::MAX {
            rts_trap_with("Cannot grow memory");
        }
    }
}
