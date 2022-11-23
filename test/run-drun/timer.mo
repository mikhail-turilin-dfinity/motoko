//MOC-ENV MOC_UNLOCK_PRIM=yesplease
//MOC-FLAG --experimental-field-aliasing
import { debugPrint; error; time; cancelTimer } = "mo:⛔";

actor {
    var lastId = 0;

    // ad-hoc place for the Timer.mo API
    func setTimer(delaySecs : Nat64, recurring : Bool, job : () -> async ()) : @TimerId {
        lastId += 1;
        let id = lastId;
        let now = time();
        let delayNanos = 1_000_000_000 * delaySecs;
        let expire = now + delayNanos;
        let delay = if recurring ?delayNanos else null;
        // only works on pruned nodes
        func insert(n : ?@Node) : @Node =
            switch n {
              case null ({ var expire; id; delay; job; ante = null; dopo = null });
              case (?n) {
                 assert n.expire != 0;
                 if (expire < n.expire) ({ n with ante = ?insert(n.ante) })
                 else ({ n with dopo = ?insert(n.dopo) })
               }
            };
        @timers := ?insert(@prune(@timers));

        let exp = @nextExpiration @timers;
        if (exp == 0) @timers := null;
        let prev = (prim "global_timer_set" : Nat64 -> Nat64) exp;
        /*FIXME: this is expensive*/
        if (prev != 0 and prev != 0 and exp > prev) {
            // reinstall
            ignore (prim "global_timer_set" : Nat64 -> Nat64) prev;
        };

        id
    };


  system func timer() : async () {
      await @run_timers();
  };

  var count = 0;
  var max = 10;
  let raw_rand = (actor "aaaaa-aa" : actor { raw_rand : () -> async Blob }).raw_rand;

  public shared func go() : async () {
     var attempts = 0;

     let id1 = setTimer(1, false, func () : async () { count += 1; debugPrint "YEP!" });
     let id2 = setTimer(2, true, func () : async () { count += 1; debugPrint "DIM!" });
     let id3 = setTimer(3, false, func () : async () {
         count += 1;
         debugPrint "ROOK!";
         ignore setTimer(1, true, func () : async () { count += 1; debugPrint "BATT!" })
     });

     while (count < max) {
       ignore await raw_rand(); // yield to scheduler
       attempts += 1;
       if (count > 5) { cancelTimer id2 };
       if (attempts >= 100 and count == 0)
         throw error("he's dead Jim");
     };
     debugPrint(debug_show {count});
  };
};

//SKIP run
//SKIP run-low
//SKIP run-ir
//SKIP ic-ref-run

//CALL ingress go "DIDL\x00\x00"
