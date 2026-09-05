# Calculator canister

[![CI](https://github.com/shamilebzeev/Calculator/actions/workflows/ci.yml/badge.svg)](https://github.com/shamilebzeev/Calculator/actions/workflows/ci.yml)
[![Motoko](https://img.shields.io/badge/Motoko-dfx%200.27-29ABE2)](dfx.json)
[![Internet Computer](https://img.shields.io/badge/deployed-Internet%20Computer-3B00B9)](https://dashboard.internetcomputer.org/canister/bkqer-kqaaa-aaaak-aeqra-cai)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[English](README.md) · **Русский**

Смарт-контракт-калькулятор с состоянием на [Internet Computer](https://internetcomputer.org),
написанный на [Motoko](https://internetcomputer.org/docs/current/motoko/main/motoko).
Хранит накопитель в блокчейне, журналирует каждую операцию, не даёт загнать
себя в невосстановимое состояние и сохраняет данные при обновлении кода.

Работает в mainnet: [`bkqer-kqaaa-aaaak-aeqra-cai`](https://dashboard.internetcomputer.org/canister/bkqer-kqaaa-aaaak-aeqra-cai)

```bash
dfx canister call Calculator add '(2.5)'    # (2.5 : float64)
dfx canister call Calculator mul '(4.0)'    # (10.0 : float64)
dfx canister call Calculator div '(0.0)'    # (variant { err = variant { divisionByZero } })
dfx canister call Calculator sqrt           # (variant { ok = 3.1622776601683795 : float64 })
dfx canister call Calculator getHistory     # vec { record { op = "add"; arg = opt 2.5; result = 2.5; at = … }; … }
```

## Что здесь показано

- **Ортогональная персистентность как надо.** Накопитель и история —
  `stable var`, поэтому `dfx deploy` новой версии сохраняет числа. Тесты это
  доказывают: канистер обновляется посреди прогона, и состояние проверяется
  на неизменность.
- **Ошибки — это данные.** Операции, которые могут не получиться, возвращают
  `Result<Float, CalcError>` с вариантом (`#divisionByZero`, `#negativeSqrt`,
  `#nonFiniteResult`) — клиенты матчат по паттерну, а не парсят строки, и
  неудавшийся вызов никогда не меняет состояние.
- **Никаких «отравленных» значений.** `Float` в Motoko следует IEEE-754:
  `1e200 ** 2` даёт `+inf`, а `(-4) ** 0.5` — `NaN` без трапа. Каждый результат
  проходит через `checked()`, который отбрасывает неконечные значения, так что
  накопитель никогда не застрянет там, где поможет только `reset`.
- **Ограниченная история в блокчейне.** Последние 20 операций с операндом,
  результатом и меткой времени IC в stable-массиве (для обновления используется
  `Buffer` с конвертацией обратно — буферы не stable).
- **Query против update.** Чтения (`see`, `getHistory`, `historySize`) —
  `query`-вызовы: бесплатные и быстрые, без консенсуса.
- **API под ревью.** [`src/calculator.did`](src/calculator.did) — ровно тот
  Candid-интерфейс, который `dfx` выводит из кода (вместе с doc-комментариями);
  CI падает, если он разошёлся.

## Интерфейс

| Метод | Тип | Возвращает | Примечание |
|-------|-----|------------|------------|
| `add(x)` `sub(x)` `mul(x)` | update | `float64` | новый накопитель |
| `div(x)` | update | `Result` | `#divisionByZero` при `x == 0` |
| `power(x)` | update | `Result` | `#nonFiniteResult` при переполнении / NaN |
| `sqrt()` | update | `Result` | `#negativeSqrt` при накопителе < 0 |
| `floor()` | update | `int` | округляет вниз и сохраняет |
| `reset()` | update | — | накопитель → 0, история остаётся |
| `see()` | query | `float64` | текущий накопитель |
| `getHistory()` | query | `vec Entry` | последние 20 операций, старые первыми |
| `historySize()` | query | `nat` | |

## Запуск локально

Нужен [IC SDK (`dfx`)](https://internetcomputer.org/docs/current/developer-docs/getting-started/install).

```bash
git clone https://github.com/shamilebzeev/Calculator && cd Calculator
dfx start --background
dfx deploy
dfx canister call Calculator add '(40.0)'
dfx canister call Calculator add '(2.0)'
dfx canister call Calculator see        # (42.0 : float64)
```

Или ничего не устанавливая, в официальном dev-образе:

```bash
docker run --rm -it -v "$PWD:/work" -w /work ghcr.io/dfinity/icp-dev-env:latest bash
```

## Тесты

```bash
./scripts/test.sh
# ▶ arithmetic        9 проверок
# ▶ error handling    6 проверок  (неудавшиеся операции не трогают состояние)
# ▶ history           2 проверки  (окно в 20, порядок вытеснения)
# ▶ upgrade keeps state
#   ✔ see() after upgrade == before
#   ✔ history survives upgrade
# passed: 19  failed: 0
```

Скрипт поднимает локальную реплику, деплоит, гоняет канистер через
`dfx canister call`, затем **передеплоивает с `--upgrade-unchanged`** и
проверяет, что ничего не потерялось. CI делает то же на каждый push и
дополнительно сравнивает закоммиченный `.did` со сгенерированным.

## Структура

```
.
├── src/main.mo           канистер
├── src/calculator.did    сгенерированный Candid-интерфейс, закоммичен для ревью
├── scripts/test.sh       интеграционный тест + тест апгрейда
├── dfx.json
├── canister_ids.json     id в mainnet
└── .github/workflows/    CI: dfx build --check → test.sh → проверка дрейфа .did
```

## Лицензия

[MIT](LICENSE) © Шамиль Эбзеев
