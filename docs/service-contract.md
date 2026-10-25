# Service contract: one payroll calculation

Part 4, step 1. The language- and UI-independent contract for the calculation that a future standalone service (in any stack) must offer, plus the test data that proves an implementation behaves like the original app.

- **Reference implementation:** `MiniLohnrechner_Bewerberaufgabe/uLohnrechnerVertrag.pas`, a thin wrapper around `uLohnrechnerCore.pas`. No business logic of its own, no UI, only `System` units.
- **Test data:** `MiniLohnrechner_Bewerberaufgabe/tests/golden/contract/cases.json`, 1680 request/response pairs, generated from the recorded golden grid.
- **Second implementation:** the C# port in `port/` (bonus), `POST /calculate` as an ASP.NET Core minimal API. It passes the same `cases.json`, in-process and over HTTP: `dotnet run --project port/Lohnrechner.ContractTests`. Port choices: [`decisions.md`](decisions.md) D22.
- **Why it looks like this:** [`decisions.md`](decisions.md) D19–D21.

## Request

```json
{"direction":"grossToNet","employeeNumber":1001,"taxClass":3,"churchTax":false,"amount":"12344.00"}
```

| Field | Type | Meaning |
|---|---|---|
| `direction` | string | `"grossToNet"` (Brutto → Netto) or `"netToGross"` (Netto → Brutto) |
| `employeeNumber` | integer | Personalnummer. Unknown numbers get allowance 0, without an error (original behavior) |
| `taxClass` | integer | Steuerklasse 1–6; `0` = none chosen (→ error). Outside 0–6: taxed at rate 0, without an error (original behavior, see below) |
| `churchTax` | boolean | Kirchensteuer |
| `amount` | string | Decimal string with a dot, up to 4 decimals, no thousands separator: `"1234.56"`, `"-5"`, `"0.01"` |

All five fields are required. Additional fields are ignored.

## Response

Success:
```json
{"amount":"11134.60"}
```
Error:
```json
{"error":"NO_TAX_CLASS","message":"Bitte zuerst eine Steuerklasse waehlen."}
```

| `error` | When | `message` (original text) |
|---|---|---|
| `NO_TAX_CLASS` | `taxClass` is 0. Checked **before** the sign of the amount | `Bitte zuerst eine Steuerklasse waehlen.` |
| `NEGATIVE_GROSS` | `grossToNet` with a negative amount | `Brutto darf nicht negativ sein.` |
| `NEGATIVE_NET` | `netToGross` with a negative amount | `Netto darf nicht negativ sein.` |
| `INVALID_REQUEST` | Not valid JSON, a field missing or of the wrong type, `amount` not in the format above | English description of the problem |

`amount` in a success response always has at least two decimals (`"1000.00"`, `"-46.51"`).

**Amounts are strings on purpose.** JSON numbers are usually read as binary floating point, which can't hold `0.1` exactly. The calculation works in exact decimal (Delphi `Currency`, 4 decimals), and single cents matter here. Every stack can parse a decimal string exactly.

**`INVALID_REQUEST` is the only new behavior.** The window never receives malformed input in this form, so there is no original behavior to keep. The contract rejects instead of guessing (no "1.000,50", no numbers given as JSON numbers, no more than 4 decimals).

## Behavior the contract keeps on purpose

The service must calculate exactly like the original app, quirks included (README, assumption A2). Examples straight from `cases.json`:

| Request | Response | Quirk |
|---|---|---|
| `grossToNet`, 1001, class 3, `"12344.00"` | `{"amount":"11134.60"}` | normal case (allowance 250) |
| `netToGross`, 1002, class 2, `"82.00"` | `{"amount":"99.99"}` | net → gross loses a cent (behavior record 4b) |
| `netToGross`, 1003, class 1, `"100.00"` | `{"amount":"-46.51"}` | inverse formula ignores the allowance clamp, negative gross (3) |
| `grossToNet`, 1002, class 0, `"-1.00"` | `{"error":"NO_TAX_CLASS",...}` | class checked before sign (5b) |

Also kept: results are truncated, not rounded; a tax class outside 1–6 is taxed at rate 0; unknown employees get allowance 0. Each is marked `QUIRK (deliberately not fixed)` in `uLohnrechnerCore.pas`.

## Not part of the contract

- **The annual total** ("Jahressumme"). It's a session counter of the window (it even adds up every keystroke), not a payroll figure. A client that wants it adds up the `amount` of successful `grossToNet` responses itself. A real annual total per employee and year would be a new feature (decision D19).
- **Where employee data comes from.** The reference implementation still reads `personal.dat`. That's step 2 of the next steps.
- **Transport.** HTTP, message queue or anything else is step 3 and depends on the undecided target architecture. The contract is the payload.

## How to check an implementation

Any implementation, in any language, is checked the same way:

1. Read `cases.json`. It has a `"cases"` array; each entry has `"id"`, `"request"` and `"response"`.
2. For each entry, send `request` to the implementation.
3. Compare the response with `response`: the same fields and the same string values. `"11134.60"` is not `"11134.6"`.
4. All 1680 must match.

The `id` (`g0001`…`g1680`) is the case id in `golden/grid.golden.txt`, so every case traces back to the recording of the original app.

## How to run the checks here

From the repository root:

```
.\run-tests.bat
```

The third run (`contract`) does four things and prints one line each:

1. **Round trip:** translates every grid case into the contract and back into the window's format, and compares with the recorded golden lines byte for byte. This proves `cases.json` says exactly what the original app showed. The annual total line is skipped (not in the contract).
2. **Freshness:** `cases.json` must be exactly what the converter generates. A hand edit or a stale file fails.
3. **Contract function:** all 1680 requests through `uLohnrechnerVertrag`, each response compared with the expected one.
4. **Invalid requests:** eight malformed requests must be rejected with `INVALID_REQUEST`.

To run only the contract checks: `MiniLohnrechner_Bewerberaufgabe\tests\GoldenTests.exe contract`.

**Regenerating `cases.json`** (`GoldenTests.exe export-contract`) is only needed if the converter itself changes. It refuses to write if the round trip isn't lossless. Like the golden files, the content must never change because the code changed: a different `cases.json` in a pull request means behavior changed.

For building the test exe (Delphi Community Edition only builds in the IDE), see the README section "Tests".
