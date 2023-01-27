/*
Internal definitions.

This file defines types and values that should always be in scope (because they
are used by the desugarer, by ir-to-ir-passes or by `mo:⛔`), but not user
visible. All names here are prefixed with `@`, so they are invisible from user
code, and cannot be shadowed.
*/

type @Iter<T_> = {next : () -> ?T_};

var @cycles : Nat = 0;

// Function called by backend to add funds to call.
// DO NOT RENAME without modifying compilation.
func @add_cycles() {
  let cycles = @cycles;
  @reset_cycles();
  (prim "cyclesAdd" : (Nat) -> ()) (cycles);
};

// Function called by backend to zero cycles on context switch.
// DO NOT RENAME without modifying compilation.
func @reset_cycles() {
  @cycles := 0;
};


// The @ in the name ensures that this cannot be shadowed by user code, so
// compiler passes can rely on them being in scope

// Implementations for overloaded dot operations
// Note that these return functions!
// (Some optimizations in the backend might be feasible.)

func @immut_array_get<A>(xs : [A]) : Nat -> A =
  func (n : Nat) : A = xs[n];
func @mut_array_get<A>(xs : [var A]) : Nat -> A =
  func (n : Nat) : A = xs[n];
func @immut_array_size<A>(xs : [A]) : () -> Nat =
  func () : Nat = (prim "array_len" : [A] -> Nat) xs;
func @mut_array_size<A>(xs : [var A]) : () -> Nat =
  func () : Nat = (prim "array_len" : [var A] -> Nat) xs;
func @mut_array_put<A>(xs : [var A]) : (Nat, A) -> () =
  func (n : Nat, x : A) = (xs[n] := x);
func @immut_array_keys<A>(xs : [A]) : () -> @Iter<Nat> =
  func () : @Iter<Nat> = object {
    var i = 0;
    let l = xs.size();
    public func next() : ?Nat { if (i >= l) null else {let j = i; i += 1; ?j} };
  };
func @mut_array_keys<A>(xs : [var A]) : () -> @Iter<Nat> =
  func () : @Iter<Nat> = object {
    var i = 0;
    let l = xs.size();
    public func next() : ?Nat { if (i >= l) null else {let j = i; i += 1; ?j} };
  };
func @immut_array_vals<A>(xs : [A]) : () -> @Iter<A> =
  func () : @Iter<A> = object {
    var i = 0;
    let l = xs.size();
    public func next() : ?A { if (i >= l) null else {let j = i; i += 1; ?xs[j]} };
  };
func @mut_array_vals<A>(xs : [var A]) : () -> @Iter<A> =
  func () : @Iter<A> = object {
    var i = 0;
    let l = xs.size();
    public func next() : ?A { if (i >= l) null else {let j = i; i += 1; ?xs[j]} };
  };
func @blob_size(xs : Blob) : () -> Nat =
  func () : Nat = (prim "blob_size" : Blob -> Nat) xs;
func @blob_vals(xs : Blob) : () -> @Iter<Nat8> =
  func () : @Iter<Nat8> = object {
    type BlobIter = Any; // not exposed
    let i = (prim "blob_vals_iter" : Blob -> BlobIter) xs;
    public func next() : ?Nat8 {
      if ((prim "blob_iter_done" : BlobIter -> Bool) i)
        null
      else
        ?((prim "blob_iter_next" : BlobIter -> Nat8) i)
    };
  };
func @text_size(xs : Text) : () -> Nat =
  func () : Nat = (prim "text_len" : Text -> Nat) xs;
func @text_chars(xs : Text) : () -> @Iter<Char> =
  func () : @Iter<Char> = object {
    type TextIter = Any; // not exposed
    let i = (prim "text_iter" : Text -> TextIter) xs;
    public func next() : ?Char {
      if ((prim "text_iter_done" : TextIter -> Bool) i)
        null
      else
        ?((prim "text_iter_next" : TextIter -> Char) i)
    };
  };


// Internal helper functions for the show translation

// The text_of functions do not need to be exposed; the user can just use
// the show above.

func @text_of_num(x : Nat, base : Nat, sep : Nat, digits : Nat -> Text) : Text {
  var text = "";
  var n = x;

  if (n == 0) return "0";

  var i = 0;
  while (n > 0) {
    let rem = n % base;
    if (sep > 0 and i == sep) { text := "_" # text; i := 0 };
    text := digits rem # text;
    n := n / base;
    i += 1;
  };
  text
};

func @left_pad(pad : Nat, char : Text, t : Text) : Text {
  if (pad > t.size()) {
    var i : Nat = pad - t.size();
    var text = t;
    while (i > 0) {
      text := char # text;
      i -= 1;
    };
    text
  } else {
    t
  }
};

func @digits_dec(x : Nat) : Text =
 (prim "conv_Char_Text" : Char -> Text) (
   (prim "num_conv_Nat32_Char" : Nat32 -> Char) (
     (prim "num_wrap_Int_Nat32" : Int -> Nat32) (
       x + 0x30
     )
   )
 );

func @text_of_Nat(x : Nat) : Text {
  @text_of_num(x, 10, 3, @digits_dec);
};

func @text_of_Int(x : Int) : Text {
  if (x == 0) "0" else (if (x < 0) "-" else "+") #
  @text_of_Nat((prim "abs" : Int -> Nat) x)
};

func @digits_hex(x : Nat) : Text =
 (prim "conv_Char_Text" : Char -> Text) (
   (prim "num_conv_Nat32_Char" : Nat32 -> Char) (
     (prim "num_wrap_Int_Nat32" : Int -> Nat32) (
       x + (if (x < 10) 0x30 else 55)
     )
   )
 );

// There is some duplication with the prim_module, but we need these here
// before we can load the prim module
func @int64ToInt(n : Int64) : Int = (prim "num_conv_Int64_Int" : Int64 -> Int) n;
func @int32ToInt(n : Int32) : Int = (prim "num_conv_Int32_Int" : Int32 -> Int) n;
func @int16ToInt(n : Int16) : Int = (prim "num_conv_Int16_Int" : Int16 -> Int) n;
func @int8ToInt(n : Int8) : Int = (prim "num_conv_Int8_Int" : Int8 -> Int) n;
func @nat64ToNat(n : Nat64) : Nat = (prim "num_conv_Nat64_Nat" : Nat64 -> Nat) n;
func @nat32ToNat(n : Nat32) : Nat = (prim "num_conv_Nat32_Nat" : Nat32 -> Nat) n;
func @nat16ToNat(n : Nat16) : Nat = (prim "num_conv_Nat16_Nat" : Nat16 -> Nat) n;
func @nat8ToNat(n : Nat8) : Nat = (prim "num_conv_Nat8_Nat" : Nat8 -> Nat) n;

func @text_of_Nat8(x : Nat8) : Text = @text_of_Nat (@nat8ToNat x);
func @text_of_Nat16(x : Nat16) : Text = @text_of_Nat (@nat16ToNat x);
func @text_of_Nat32(x : Nat32) : Text = @text_of_Nat (@nat32ToNat x);
func @text_of_Nat64(x : Nat64) : Text = @text_of_Nat (@nat64ToNat x);
func @text_of_Int8(x : Int8) : Text = @text_of_Int (@int8ToInt x);
func @text_of_Int16(x : Int16) : Text = @text_of_Int (@int16ToInt x);
func @text_of_Int32(x : Int32) : Text = @text_of_Int (@int32ToInt x);
func @text_of_Int64(x : Int64) : Text = @text_of_Int (@int64ToInt x);
func @text_of_Float(x : Float) : Text = (prim "Float->Text" : Float -> Text) x;


func @text_of_Bool(b : Bool) : Text {
  if (b) "true" else "false"
};

func @text_of_Text(t : Text) : Text {
  // TODO: Escape properly
  "\"" # t # "\"";
};

func @text_of_Char(c : Char) : Text {
  // TODO: Escape properly
  "\'" # (prim "conv_Char_Text" : Char -> Text) c # "\'";
};

func @text_of_Blob(blob : Blob) : Text {
  var t = "\"";
  for (b in blob.vals()) {
    // Could do more clever escaping, e.g. leave ascii and utf8 in place
    t #= "\\" # @left_pad(2, "0", @text_of_num(@nat8ToNat b, 16, 0, @digits_hex));
  };
  t #= "\"";
  return t;
};



func @text_has_parens(t : Text) : Bool {
  switch (t.chars().next()) {
    case (?'(') true;
    case _ false;
  }
};

func @text_needs_parens(t : Text) : Bool {
  switch (t.chars().next()) {
    case (?('+' or '-' or '?' or '#')) true;
    case _ false;
  }
};

func @text_of_option<T>(f : T -> Text, x : ?T) : Text {
  switch (x) {
    case (?y) {
      let fy = f y;
      if (@text_needs_parens(fy)) "?(" # fy # ")"
      else "?" # fy
    };
    case null {"null"};
  }
};

func @text_of_variant<T>(l : Text, f : T -> Text, x : T) : Text {
  let fx = f x;
  if (fx == "()") "#" # l
  else if (@text_has_parens(fx)) "#" # l # fx
  else "#" # l # "(" # fx # ")"
};

func @text_of_array<T>(f : T -> Text, xs : [T]) : Text {
  var text = "[";
  var first = true;
  for (x in xs.vals()) {
    if first {
      first := false;
    } else {
      text #= ", ";
    };
    text #= f x;
  };
  text # "]"
};

func @text_of_array_mut<T>(f : T -> Text, xs : [var T]) : Text {
  var text = "[var";
  var first = true;
  for (x in xs.vals()) {
    if first {
      first := false;
      text #= " ";
    } else {
      text #= ", ";
    };
    text #= f x;
  };
  text # "]"
};

func @equal_array<T>(eq : (T, T) -> Bool, a : [T], b : [T]) : Bool {
  if (a.size() != b.size()) {
    return false;
  };
  var i = 0;
  let s = a.size();
  while (i < s) {
    if (not eq(a[i],b[i])) {
      return false;
    };
    i += 1;
  };
  return true;
};

type @Cont<T> = T -> () ;
type @Async<T> = (@Cont<T>,@Cont<Error>) -> {
  #suspend;
  #schedule : () -> ();
};

type @Refund = Nat;
type @Result<T> = {#ok : (refund : @Refund, value: T); #error : Error};

type @Waiter<T> = (@Refund,T) -> () ;

var @refund : @Refund = 0;

// Function called by backend to zero refunds on context switch.
// DO NOT RENAME without modifying compilation.
func @reset_refund() {
  @refund := 0;
};

func @getSystemRefund() : @Refund {
  return (prim "cyclesRefunded" : () -> Nat) ();
};

func @new_async<T <: Any>() : (@Async<T>, @Cont<T>, @Cont<Error>) {
  let w_null = func(r : @Refund, t : T) { };
  let r_null = func(_ : Error) {};
  var result : ?(@Result<T>) = null;
  var ws : @Waiter<T> = w_null;
  var rs : @Cont<Error> = r_null;

  func fulfill(t : T) {
    switch result {
      case null {
        let refund = @getSystemRefund();
        result := ?(#ok (refund, t));
        let ws_ = ws;
        ws := w_null;
        rs := r_null;
        ws_(refund, t);
      };
      case (? _) { assert false };
    };
  };

  func fail(e : Error) {
    switch result {
      case null {
        result := ?(#error e);
        let rs_ = rs;
        ws := w_null;
        rs := r_null;
        rs_(e);
      };
      case (? _) { assert false };
    };
  };

  func enqueue(k : @Cont<T>, r : @Cont<Error>) : {
    #suspend;
    #schedule : () -> ();
  } {
    switch result {
      case null {
        let ws_ = ws;
        ws := func(r : @Refund, t : T) {
          ws_(r, t);
          @reset_cycles();
          @refund := r;
          k(t);
        };
        let rs_ = rs;
        rs := func(e : Error) {
          rs_(e);
          @reset_cycles();
          @reset_refund();
          r(e)
        };
        #suspend
      };
      case (? (#ok (r, t))) {
        #schedule (func () { @refund := r; k(t) });
      };
      case (? (#error e)) {
        #schedule (func () { r(e) });
      };
    };
  };

  (enqueue, fulfill, fail)
};

// Subset of IC management canister interface required for our use
module @ManagementCanister = {
  public type wasm_module = Blob;
  public type canister_settings = {
    controllers : ?[Principal];
    compute_allocation: ?Nat;
    memory_allocation: ?Nat;
    freezing_threshold: ?Nat;
  };
};

let @ic00 = actor "aaaaa-aa" :
  actor {
    create_canister : {
      settings : ?@ManagementCanister.canister_settings
    } -> async { canister_id : Principal };
    install_code : {
      mode : { #install; #reinstall; #upgrade };
      canister_id : Principal;
      wasm_module : @ManagementCanister.wasm_module;
      arg : Blob;
    } -> async ()
 };

func @ic00_create_canister() : shared {
      settings : ?@ManagementCanister.canister_settings
    } -> async { canister_id : Principal } {
  @ic00.create_canister
};

func @ic00_install_code() : shared {
    mode : { #install; #reinstall; #upgrade };
    canister_id : Principal;
    wasm_module : @ManagementCanister.wasm_module;
    arg : Blob;
  } -> async () {
  @ic00.install_code
};

// It would be desirable if create_actor_helper can be defined
// without paying the extra self-remote-call-cost
// TODO: This helper is now only used by Prim.createActor and could be removed, except
// that Prim.createActor was mentioned on the forum and might be in use. (#3420)
func @create_actor_helper(wasm_module_ : Blob, arg_ : Blob) : async Principal = async {
  let available = (prim "cyclesAvailable" : () -> Nat) ();
  let accepted = (prim "cyclesAccept" : Nat -> Nat) (available);
  @cycles += accepted;
  let { canister_id = canister_id_ } =
    await @ic00.create_canister({settings = null});
  await @ic00.install_code({
    mode = #install;
    canister_id = canister_id_;
    wasm_module = wasm_module_;
    arg = arg_;
  });
  return canister_id_;
};

// raw calls
func @call_raw(p : Principal, m : Text, a : Blob) : async Blob {
  await (prim "call_raw" : (Principal, Text, Blob) -> async Blob) (p, m, a);
};


// helpers for reifying ic0.call_perform failures as errors
func @call_succeeded() : Bool {
  (prim "call_perform_status" : () -> Nat32) () == 0;
};

func @call_error() : Error {
  let status = (prim "call_perform_status" : () -> Nat32) ();
  let message = (prim "call_perform_message" : () -> Text) ();
  let code = #call_error({err_code = status});
  (prim "cast" : ({#call_error : {err_code : Nat32}}, Text) -> Error)
    (code, message)
};

// default timer mechanism implementation
// fundamental node invariant: max_exp pre <= expire <= min_exp post
// corollary: if expire == 0 then the pre is completely expired
//
// Note: Below the `expire` field is an encoding of an aliased mutable field with
//       a single-element mutable array. It eliminates `--experimental-field-aliasing`
//       while compiling this file at the cost of slightly higher syntactic noise
//       as well as increased allocation and runtime cost accessing the data. Oh well.
//
type @Node = { expire : [var Nat64]; id : Nat; delay : ?Nat64; job : () -> async (); pre : ?@Node; post : ?@Node };

var @timers : ?@Node = null;

func @prune(n : ?@Node) : ?@Node = switch n {
  case null null;
  case (?n) {
    if (n.expire[0] == 0) {
      @prune(n.post) // by corollary
    } else {
      ?{ n with pre = @prune(n.pre); post = @prune(n.post) }
    }
  }
};

func @nextExpiration(n : ?@Node) : Nat64 = switch n {
  case null 0;
  case (?n) {
    var exp = @nextExpiration(n.pre); // TODO: use the corollary for expire == 0
    if (exp == 0) {
      exp := n.expire[0];
      if (exp == 0) {
        exp := @nextExpiration(n.post)
      }
    };
    exp
  }
};

// Function called by backend to run eligible timed actions.
// DO NOT RENAME without modifying compilation.
func @timer_helper() : async () {
  func Array_init<T>(len : Nat,  x : T) : [var T] {
    (prim "Array.init" : <T>(Nat, T) -> [var T])<T>(len, x)
  };
  let now = (prim "time" : () -> Nat64)();
  let exp = @nextExpiration @timers;
  let prev = (prim "global_timer_set" : Nat64 -> Nat64) exp;

  // debug { assert prev == 0 };

  if (exp == 0) {
    return
  };

  var gathered = 0;
  let thunks = Array_init<?(() -> async ())>(10, null); // we want max 10

  func gatherExpired(n : ?@Node) = switch n {
    case null ();
    case (?n) {
      gatherExpired(n.pre);
      if (n.expire[0] > 0 and n.expire[0] <= now and gathered < thunks.size()) {
        thunks[gathered] := ?(n.job);
        switch (n.delay) {
          case (?delay) if (delay != 0) {
            // re-add the node
            let expire = n.expire[0] + delay;
            n.expire[0] := 0;
            // N.B. reinsert only works on pruned nodes
            func reinsert(m : ?@Node) : @Node = switch m {
              case null ({ n with expire = [var expire]; pre = null; post = null });
              case (?m) {
                assert m.expire[0] != 0;
                if (expire < m.expire[0]) ({ m with pre = ?reinsert(m.pre) })
                else ({ m with post = ?reinsert(m.post) })
              }
            };
            @timers := ?reinsert(@prune(@timers));
          };
          case _ ()
        };
        n.expire[0] := 0;
        gathered += 1;
      };
      gatherExpired(n.post);
    }
  };

  gatherExpired(@timers);

  for (k in thunks.keys()) {
    ignore switch (thunks[k]) { case (?thunk) ?thunk(); case _ null };
  }
};

var @lastTimerId = 0;

func @setTimer(delayNanos : Nat64, recurring : Bool, job : () -> async ()) : (id : Nat) {
  @lastTimerId += 1;
  let id = @lastTimerId;
  let now = (prim "time" : () -> Nat64) ();
  let expire = now + delayNanos;
  let delay = if recurring ?delayNanos else null;
  // only works on pruned nodes
  func insert(n : ?@Node) : @Node =
    switch n {
      case null ({ expire = [var expire]; id; delay; job; pre = null; post = null });
      case (?n) {
        assert n.expire[0] != 0;
        if (expire < n.expire[0]) ({ n with pre = ?insert(n.pre) })
        else ({ n with post = ?insert(n.post) })
      }
    };
  @timers := ?insert(@prune(@timers));

  let exp = @nextExpiration @timers;
  if (exp == 0) @timers := null;
  ignore (prim "global_timer_set" : Nat64 -> Nat64) exp;

  id
};

func @cancelTimer(id : Nat) {
  func graft(onto : ?@Node, branch : ?@Node) : ?@Node = switch (onto, branch) {
    case (null, null) null;
    case (null, _) branch;
    case (_, null) onto;
    case (?onto, _) { ?{ onto with post = graft(onto.post, branch) } }
  };

  func hunt(n : ?@Node) : ?@Node = switch n {
    case null n;
    case (?{ id = node; pre; post }) {
      if (node == id) {
        graft(pre, post)
      } else do? {
        { n! with pre = hunt pre; post = hunt post }
      }
    }
  };

  @timers := hunt @timers;

  if (@nextExpiration @timers == 0) {
    // no more expirations ahead
    ignore (prim "global_timer_set" : Nat64 -> Nat64) 0;
    @timers := null
  }
};

func @set_global_timer(time : Nat64) = ignore (prim "global_timer_set" : Nat64 -> Nat64) time;

