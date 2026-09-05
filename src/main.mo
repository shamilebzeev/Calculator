/// A stateful calculator canister.
///
/// The accumulator survives canister upgrades (it is a `stable var`), every
/// mutating call is journaled into a bounded history, and operations that can
/// fail (division by zero, square root of a negative) return a `Result`
/// instead of trapping or silently producing NaN.
import Buffer "mo:base/Buffer";
import Float "mo:base/Float";
import Result "mo:base/Result";
import Time "mo:base/Time";

actor Calculator {

  /// Errors a calculation can fail with. Kept as a variant so clients can
  /// pattern-match instead of parsing text.
  public type CalcError = {
    #divisionByZero;
    #negativeSqrt;
    #nonFiniteResult;
  };

  public type CalcResult = Result.Result<Float, CalcError>;

  /// One journaled operation.
  public type Entry = {
    op : Text;        // "add", "sub", "mul", "div", "power", "sqrt", "floor", "reset"
    arg : ?Float;     // operand, or null for unary ops
    result : Float;   // accumulator after the operation
    at : Time.Time;   // nanoseconds since epoch
  };

  /// How many entries `history()` keeps. Older ones are dropped.
  let maxHistory : Nat = 20;

  /// The accumulator. `stable` so an upgrade doesn't wipe the running total.
  stable var counter : Float = 0;

  /// Journal, oldest first. Stored as an array because `Buffer` is not stable.
  stable var history : [Entry] = [];

  // ---------------------------------------------------------------------------
  // Arithmetic
  // ---------------------------------------------------------------------------

  /// Add `x` to the accumulator.
  public func add(x : Float) : async Float {
    commit("add", ?x, counter + x)
  };

  /// Subtract `x` from the accumulator.
  public func sub(x : Float) : async Float {
    commit("sub", ?x, counter - x)
  };

  /// Multiply the accumulator by `x`.
  public func mul(x : Float) : async Float {
    commit("mul", ?x, counter * x)
  };

  /// Divide the accumulator by `x`. Fails with `#divisionByZero` when x == 0.
  public func div(x : Float) : async CalcResult {
    if (x == 0) {
      return #err(#divisionByZero);
    };
    checked("div", ?x, counter / x)
  };

  /// Raise the accumulator to the power `x`.
  /// Fails with `#nonFiniteResult` if the result overflows or is NaN
  /// (e.g. a negative base with a fractional exponent).
  public func power(x : Float) : async CalcResult {
    checked("power", ?x, counter ** x)
  };

  /// Square root of the accumulator. Fails with `#negativeSqrt` when negative.
  public func sqrt() : async CalcResult {
    if (counter < 0) {
      return #err(#negativeSqrt);
    };
    checked("sqrt", null, Float.sqrt(counter))
  };

  /// Round the accumulator down and return it as an integer.
  public func floor() : async Int {
    let floored = Float.floor(counter);
    ignore commit("floor", null, floored);
    Float.toInt(floored)
  };

  /// Set the accumulator back to zero. The history is kept.
  public func reset() : async () {
    ignore commit("reset", null, 0);
  };

  // ---------------------------------------------------------------------------
  // Queries (free, no consensus)
  // ---------------------------------------------------------------------------

  /// Current value of the accumulator.
  public query func see() : async Float {
    counter
  };

  /// The last `maxHistory` operations, oldest first.
  public query func getHistory() : async [Entry] {
    history
  };

  /// Number of journaled operations currently kept.
  public query func historySize() : async Nat {
    history.size()
  };

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// IEEE-754 division by zero yields +inf (Motoko does not trap on Float).
  let inf : Float = 1.0 / 0.0;

  /// Reject NaN/±inf so the accumulator can never get stuck in a state
  /// from which no operation recovers except `reset`.
  func checked(op : Text, arg : ?Float, value : Float) : CalcResult {
    if (Float.isNaN(value) or Float.abs(value) == inf) {
      return #err(#nonFiniteResult);
    };
    #ok(commit(op, arg, value))
  };

  /// Store the new accumulator value and append a journal entry.
  func commit(op : Text, arg : ?Float, value : Float) : Float {
    counter := value;
    let entry : Entry = { op; arg; result = value; at = Time.now() };
    let buf = Buffer.fromArray<Entry>(history);
    buf.add(entry);
    if (buf.size() > maxHistory) {
      ignore buf.remove(0);
    };
    history := Buffer.toArray(buf);
    value
  };
};
