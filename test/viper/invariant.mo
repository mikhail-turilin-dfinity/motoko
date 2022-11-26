// @verify

actor {

  var claimed = false;

  var count = 0 : Int;

  assert:invariant claimed and not (-1 == -1) and (-42 == -42) or true;
  assert:invariant count > 0;
  assert:invariant not claimed implies count == 0;

  public shared func claim() : async () {
      assert:func count >= 0;
      assert claimed implies count > 0;
      assert:return count >= 0;
  };

  public shared func loops(/*j : Int*/) : async () {
      var i : Int = 0;
      while (i > 0) {
          i += 1
      }
  }

}
