# Calculator canister

[![CI](https://github.com/shamilebzeev/Calculator/actions/workflows/ci.yml/badge.svg)](https://github.com/shamilebzeev/Calculator/actions/workflows/ci.yml)
[![Motoko](https://img.shields.io/badge/Motoko-dfx%200.27-29ABE2)](dfx.json)
[![Internet Computer](https://img.shields.io/badge/deployed-Internet%20Computer-3B00B9)](https://dashboard.internetcomputer.org/canister/bkqer-kqaaa-aaaak-aeqra-cai)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**English** · [Русский](README.ru.md)

A stateful calculator smart contract on the [Internet Computer](https://internetcomputer.org),
written in [Motoko](https://internetcomputer.org/docs/current/motoko/main/motoko).
It keeps a running total on-chain, journals every operation, refuses to enter
an unrecoverable state, and keeps its data across code upgrades.

Live on mainnet: [`bkqer-kqaaa-aaaak-aeqra-cai`](https://dashboard.internetcomputer.org/canister/bkqer-kqaaa-aaaak-aeqra-cai)

```bash
dfx canister call Calculator add '(2.5)'    # (2.5 : float64)
dfx canister call Calculator mul '(4.0)'    # (10.0 : float64)
dfx canister call Calculator div '(0.0)'    # (variant { err = variant { divisionByZero } })
dfx canister call Calculator sqrt           # (variant { ok = 3.1622776601683795 : float64 })
dfx canister call Calculator getHistory     # vec { record { op = "add"; arg = opt 2.5; result = 2.5; at = … }; … }
```

## What it demonstrates

- **Orthogonal persistence done right.** The accumulator and the history are
  `stable var`s, so `dfx deploy` of a new version keeps the numbers. The test
  suite proves it: it upgrades the canister mid-run and asserts the state is
  unchanged.
- **Errors as data.** Fallible operations return
  `Result<Float, CalcError>` with a variant (`#divisionByZero`,
  `#negativeSqrt`, `#nonFiniteResult`) — clients pattern-match instead of
  parsing strings, and a failed call never mutates state.
- **No poison values.** Motoko `Float` follows IEEE-754, so `1e200 ** 2` is
  `+inf` and `(-4) ** 0.5` is `NaN` without trapping. Every result passes
  through `checked()` which rejects non-finite values, so the accumulator can
  never get stuck where only `reset` helps.
- **Bounded on-chain history.** The last 20 operations, with operand, result
  and IC timestamp, kept in a stable array (a `Buffer` is used for the update
  and converted back, since buffers are not stable).
- **Query vs update.** Reads (`see`, `getHistory`, `historySize`) are `query`
  calls — free and fast, no consensus.
- **Reviewable API.** [`src/calculator.did`](src/calculator.did) is the exact
  Candid interface `dfx` derives from the code (doc comments included); CI
  fails if it drifts.

## Interface

| Method | Kind | Returns | Notes |
|--------|------|---------|-------|
| `add(x)` `sub(x)` `mul(x)` | update | `float64` | new accumulator |
| `div(x)` | update | `Result` | `#divisionByZero` when `x == 0` |
| `power(x)` | update | `Result` | `#nonFiniteResult` on overflow / NaN |
| `sqrt()` | update | `Result` | `#negativeSqrt` when accumulator < 0 |
| `floor()` | update | `int` | rounds down and stores |
| `reset()` | update | — | accumulator → 0, history kept |
| `see()` | query | `float64` | current accumulator |
| `getHistory()` | query | `vec Entry` | last 20 ops, oldest first |
| `historySize()` | query | `nat` | |

## Run locally

Requires the [IC SDK (`dfx`)](https://internetcomputer.org/docs/current/developer-docs/getting-started/install).

```bash
git clone https://github.com/shamilebzeev/Calculator && cd Calculator
dfx start --background
dfx deploy
dfx canister call Calculator add '(40.0)'
dfx canister call Calculator add '(2.0)'
dfx canister call Calculator see        # (42.0 : float64)
```

Or without installing anything, in the official dev image:

```bash
docker run --rm -it -v "$PWD:/work" -w /work ghcr.io/dfinity/icp-dev-env:latest bash
```

## Tests

```bash
./scripts/test.sh
# ▶ arithmetic        9 checks
# ▶ error handling    6 checks   (failed ops leave state untouched)
# ▶ history           2 checks   (window of 20, eviction order)
# ▶ upgrade keeps state
#   ✔ see() after upgrade == before
#   ✔ history survives upgrade
# passed: 19  failed: 0
```

The script starts a local replica, deploys, drives the canister through
`dfx canister call`, then **redeploys with `--upgrade-unchanged`** and checks
that nothing was lost. CI runs the same on every push and additionally
diffs the committed `.did` against the generated one.

## Layout

```
.
├── src/main.mo           the canister
├── src/calculator.did    generated Candid interface, committed for review
├── scripts/test.sh       integration + upgrade test
├── dfx.json
├── canister_ids.json     mainnet id
└── .github/workflows/    CI: dfx build --check → test.sh → .did drift check
```

## License

[MIT](LICENSE) © Shamil Ebzeev
