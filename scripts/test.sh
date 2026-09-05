#!/usr/bin/env bash
# Integration test: deploy to a local replica and exercise every method,
# including the upgrade path that proves state is actually stable.
#
#   ./scripts/test.sh            # starts/stops its own replica
#   KEEP_REPLICA=1 ./scripts/test.sh
set -euo pipefail

cd "$(dirname "$0")/.."

CANISTER=Calculator
PASS=0
FAIL=0

# dfx prints Candid over several lines; flatten so answers compare as strings.
call()  { dfx canister call "$CANISTER" "$@" 2>&1 | tr -d '\n' | sed 's/  */ /g; s/^ //; s/ $//'; }
check() { # check DESCRIPTION EXPECTED ACTUAL
  if [[ "$3" == "$2" ]]; then
    printf '  \033[32m✔\033[0m %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  \033[31m✘\033[0m %s\n      want: %s\n      got:  %s\n' "$1" "$2" "${3:0:300}"; FAIL=$((FAIL+1))
  fi
}

cleanup() {
  if [[ -z "${KEEP_REPLICA:-}" && -n "${STARTED_REPLICA:-}" ]]; then
    dfx stop >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ! dfx ping >/dev/null 2>&1; then
  echo "▶ starting local replica"
  dfx start --clean --background >/dev/null 2>&1
  STARTED_REPLICA=1
fi

echo "▶ deploying $CANISTER"
dfx deploy "$CANISTER" --yes >/dev/null 2>&1

echo "▶ arithmetic"
call reset >/dev/null
check "see() starts at 0"          "(0.0 : float64)"                  "$(call see)"
check "add(2.5) -> 2.5"            "(2.5 : float64)"                  "$(call add '(2.5)')"
check "mul(4) -> 10"               "(10.0 : float64)"                 "$(call mul '(4.0)')"
check "sub(1) -> 9"                "(9.0 : float64)"                  "$(call sub '(1.0)')"
check "div(3) -> ok 3"             "(variant { ok = 3.0 : float64 })" "$(call div '(3.0)')"
check "power(2) -> ok 9"           "(variant { ok = 9.0 : float64 })" "$(call power '(2.0)')"
check "sqrt() -> ok 3"             "(variant { ok = 3.0 : float64 })" "$(call sqrt)"
call add '(0.75)' >/dev/null
check "floor() -> 3 and stores it" "(3 : int)"                        "$(call floor)"
check "see() -> 3"                 "(3.0 : float64)"                  "$(call see)"

echo "▶ error handling"
check "div(0) -> err divisionByZero"        "(variant { err = variant { divisionByZero } })" "$(call div '(0.0)')"
check "accumulator untouched by failed div" "(3.0 : float64)"                                "$(call see)"
call reset >/dev/null; call sub '(4.0)' >/dev/null
check "sqrt() of -4 -> err negativeSqrt"        "(variant { err = variant { negativeSqrt } })"    "$(call sqrt)"
check "power(0.5) of -4 -> err nonFiniteResult" "(variant { err = variant { nonFiniteResult } })" "$(call power '(0.5)')"
call reset >/dev/null; call add '(1e200)' >/dev/null
BEFORE_OVERFLOW="$(call see)"
check "power(2) overflow -> err nonFiniteResult" "(variant { err = variant { nonFiniteResult } })" "$(call power '(2.0)')"
check "accumulator untouched by overflow"        "$BEFORE_OVERFLOW"                               "$(call see)"

echo "▶ history"
call reset >/dev/null
for _ in $(seq 1 25); do call add '(1.0)' >/dev/null; done
check "history is capped at 20 entries" "(20 : nat)" "$(call historySize)"
HIST="$(call getHistory)"
# 26 ops happened (reset + 25 adds); the window keeps the last 20: adds 6..25.
if [[ "$HIST" == *'result = 6.0 : float64'* && "$HIST" == *'result = 25.0 : float64'* \
      && "$HIST" != *'result = 5.0 : float64'* && "$HIST" != *'op = "reset"'* ]]; then
  check "window holds adds 6..25, older entries evicted" ok ok
else
  check "window holds adds 6..25, older entries evicted" "6.0 … 25.0 present; 5.0 and reset evicted" "$HIST"
fi

echo "▶ upgrade keeps state"
BEFORE="$(call see)"
dfx deploy "$CANISTER" --upgrade-unchanged --yes >/dev/null 2>&1
check "see() after upgrade == before" "$BEFORE"   "$(call see)"
check "history survives upgrade"      "(20 : nat)" "$(call historySize)"

echo
echo "passed: $PASS  failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
