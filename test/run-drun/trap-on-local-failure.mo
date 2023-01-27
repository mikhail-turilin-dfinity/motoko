//MOC-FLAG --trap-on-call-error
// legacy: trap on local send failure
import Prim "mo:⛔";

actor self {

  func showError(e : Error) : Text = debug_show (Prim.errorCode(e), Prim.errorMessage(e));

  let MAX_SELF_QUEUE_CAPACITY = 500;
  let DOUBLE_CAPACITY = 2 * MAX_SELF_QUEUE_CAPACITY;

  let raw_rand = (actor "aaaaa-aa" : actor { raw_rand : () -> async Blob }).raw_rand;

  // local async functions
  func local() : async () {
  };

  public func test1() : async () {
    var n = 0;
    while (n < DOUBLE_CAPACITY) {
      ignore local();
      n += 1;
    }

  };

  public func test2() : async () {
    try {
      var n = 0;
      while (n < DOUBLE_CAPACITY) {
        ignore local();
        n += 1;
      }
    } catch e {
      Prim.debugPrint("caught " # showError(e));
      throw e;
    }
  };


  public func go() : async () {


    Prim.debugPrint("test1:");

    try {
      await test1();
      assert false;
    }
    catch e {
      assert (Prim.errorCode(e) == #canister_error);
      Prim.debugPrint("test1: " # showError(e));
    };

    let _ = await raw_rand(); // drain queues, can't use await async() as full!

    Prim.debugPrint("test2:");
    try {
      await test2();
      assert false;
    }
    catch e {
      assert (Prim.errorCode(e) == #canister_error);
      Prim.debugPrint("test2: " # showError(e));
    };


  }

};

//SKIP run
//SKIP run-ir
//SKIP run-low
//SKIP ic-ref-run

//await a.go(); //OR-CALL ingress go "DIDL\x00\x00"
