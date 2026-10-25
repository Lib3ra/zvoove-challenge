# Brief: C# port as a minimal API (bonus)

Handover for the session that implements the port on a machine with the .NET SDK. Branch: `port-csharp`. Everything needed is in this file and the documents it links; read them before writing code.

## Goal

Port the extracted payroll core **including its deliberately preserved quirks** to C#, expose it as an ASP.NET Core **minimal API** that speaks the existing service contract, and prove it with the **same test data** the Delphi implementation passes:

> **The ultimate test:** every one of the 1680 cases in `cases.json` sent to the running service over HTTP returns the expected response.

This is the optional bonus of the case study ("port the core logic to another language, including the quirks; run the same test cases, a shared data file, against both implementations"). The Delphi side already passes `cases.json` (`run-tests.bat`, contract mode).

## Read first

| File | Why |
|---|---|
| `docs/service-contract.md` | The contract you implement: request, response, error codes, amount format, kept quirks with examples, how to check an implementation |
| `zvoove_Software_Engineer_AI_Case_study_candidate/MiniLohnrechner_Case_Study/MiniLohnrechner_Bewerberaufgabe/uLohnrechnerCore.pas` | The core to port, line by line. Every `QUIRK (deliberately not fixed)` comment marks behavior you must keep |
| `.../MiniLohnrechner_Bewerberaufgabe/uLohnrechnerVertrag.pas` | The Delphi contract wrapper: validation rules, amount formatting, error mapping. Your API must behave the same |
| `.../MiniLohnrechner_Bewerberaufgabe/uPersonalstamm.pas` + `personal.dat` | The allowance data and how it's read |
| `.../MiniLohnrechner_Bewerberaufgabe/tests/golden/contract/cases.json` | **The test data. Never edit it.** |
| `.../MiniLohnrechner_Bewerberaufgabe/tests/uContractCases.pas` | How the Delphi side checks the contract, incl. the 8 invalid requests (`CheckInvalidRequests`) to reproduce |
| `docs/decisions.md` D19–D21, `README.md` Part 4 | Why the contract looks like this; the annual total is **not** part of it |
| `docs/uMain-behavior.md` | Observed behavior of the original app; quirk comments in the port should cite its rows |

## Scope

**Build:**
1. **`Lohnrechner.Core`** (class library): the port of `uLohnrechnerCore` (calculation, checks, error kinds and texts) plus the contract layer (request validation and parsing, response building) as plain C# with no ASP.NET dependency.
2. **`Lohnrechner.Api`** (minimal API): one endpoint, `POST /calculate`, which reads the raw request body, calls the contract layer and returns the contract response. Nothing else: no annual total, no other routes.
3. **`Lohnrechner.ContractTests`** (console program): reads `cases.json` and checks all 1680 cases **twice**, against the core in-process **and** over HTTP against the API started in-process on a free local port. Plus the 8 invalid requests. Prints a summary and `RESULT: OK` / `RESULT: FAILED`, exit code 0/1.

**Suggested layout:** `port/Lohnrechner.sln` with the three projects under `port/`. Target the current LTS (`net10.0`, or `net8.0` if that's what the machine has). **Prefer no NuGet packages**: minimal API and `System.Text.Json` come with the shared framework, and a console runner needs no test framework. That keeps the port buildable offline.

**Not in scope:** the annual total (D19), a data source other than `personal.dat` (Part 4 step 2), deployment or hosting decisions (step 3), changing anything in the Delphi code or in `cases.json`.

## Delphi semantics to reproduce exactly

The Delphi code runs as **Win32**: floating-point math uses the x87 FPU with **80-bit extended** intermediates, round-to-nearest-even. `Currency` is a 64-bit integer scaled by 10,000 (exactly 4 decimals). The core mixes `Currency` and `Double` on purpose (quirk 4). What each line does, as best I know it; **`cases.json` is the judge**, not this table:

| Delphi (`uLohnrechnerCore.pas`) | Types | What happens |
|---|---|---|
| `SteuersatzFuerKlasse = (0.14, 0.18, 0.10, 0.18, 0.26, 0.30)` | `Double` | Rates are the nearest **double** to each decimal. Classes II and IV share 0.18 (quirk 10a). |
| `Steuersatz(Klasse)` | `Double` | Rate 0 for any class outside 1..6, **no error** (quirk). Class 0 never reaches it in the calculations (checked first). |
| `if Steuerklasse = 0 → lfKeineSteuerklasse` then `if Brutto < 0 → lfBruttoNegativ` | | **Class is checked before the sign.** Error result: amount 0, nothing else computed. Same order in `BerechneBrutto` with `lfNettoNegativ`. |
| `Freibetrag := FHoleFreibetrag(Personalnummer)` | `Currency` | Unknown employee → 0, no error. |
| `Bemessungsgrundlage := Brutto - Freibetrag; if < 0 then := 0` | `Currency` | Exact decimal arithmetic. |
| `Steuer := Bemessungsgrundlage * Steuersatz(Klasse)` | `Currency * Double → Currency` | Computed in extended, then stored to `Currency`: rounded to 4 decimals (round-half-even, as the FPU stores it). |
| `KiSt := Steuer * 0.09` | `Currency * literal → Currency` | **The literal `0.09` is Extended**, not Double. Computed in extended, rounded to 4 decimals. |
| `Result := Trunc((Brutto - Steuer - KiSt) * 100) / 100` | `Currency` | **Truncation, not rounding** (quirk). Subtraction exact; ×100 and `Trunc` go through the FPU. |
| `Rate := Steuersatz; if Kirchensteuer then Rate := Rate + Rate * 0.09` | `Double` | `Rate * 0.09` and the sum in extended, then **stored back into a Double** (rounded to 53 bits). |
| `Result := Trunc(((Netto - Rate * Freibetrag) / (1 - Rate)) * 100) / 100` | mixed → `Currency` | The whole expression in **extended**, then truncated. **This is where the lost cent (quirks 4b, 4e) comes from.** Ignores the allowance clamp, so it can go negative (quirk 3). |

Error texts, byte for byte: `Bitte zuerst eine Steuerklasse waehlen.`, `Brutto darf nicht negativ sein.`, `Netto darf nicht negativ sein.` (ASCII, no umlauts).

Allowances (`personal.dat`): lines `employeeNumber;amount`, amount with a **German decimal comma** (`1001;250,00`). Parse it explicitly with German format (`de-DE` or a comma-aware parser), not the machine culture: the original's locale dependence (quirk 9a) is a Part 4 step 2 problem, not something to port. Lines that don't parse are skipped silently, a missing file means all allowances 0 (quirks 8, 9a). Point the port at the repository's `personal.dat`; don't copy the data into code.

## Contract layer: rules to mirror (`uLohnrechnerVertrag.pas`)

- **Read the raw body and validate it yourself.** Do **not** use minimal-API model binding into a DTO: it coerces types (`"1001"` → 1001, numbers → strings), so requests that must be `INVALID_REQUEST` would be accepted. Parse with `JsonDocument` and check every field's JSON kind.
- Required fields and kinds: `direction` string `"grossToNet"` / `"netToGross"`; `employeeNumber` JSON **integer** (fits Int32; `1001.0` or `1e3` is invalid); `taxClass` JSON integer (any value, 0 = none); `churchTax` JSON `true`/`false`; `amount` JSON **string** matching `^-?[0-9]+(\.[0-9]{1,4})?$` and within Delphi `Currency` range (±922337203685477.5807). Extra fields are ignored. Anything else → `INVALID_REQUEST` with an English message (the message text isn't checked; the code is).
- Calculation: a **fresh calculator per request**, so nothing is shared between requests.
- Response, exactly these fields in this order: success `{"amount":"<decimal>"}`; error `{"error":"<CODE>","message":"<text>"}`. Codes: `NO_TAX_CLASS`, `NEGATIVE_GROSS`, `NEGATIVE_NET`, `INVALID_REQUEST`.
- **Amount formatting:** invariant culture, dot, **at least 2 and at most 4 decimals**, further trailing zeros dropped: `11134.60`, `1000.00`, `-46.51`, `0.00`. Never scientific notation, never a JSON number.
- **HTTP status:** the contract doesn't define transport (step 3 is open). Suggestion: `200` for success, `422` for the three business errors, `400` for `INVALID_REQUEST`, always with the contract body. **The tests compare the body**; record the status choice in `docs/decisions.md`.

## How to verify

1. **Build and run** the contract tests from the repository root, e.g. `dotnet run --project port/Lohnrechner.ContractTests`. Expected output, in this shape:
   ```
   [port core] 1680 cases, 0 failed
   [port http] 1680 cases, 0 failed
   [port] 8 invalid requests, 0 not rejected
   RESULT: OK
   ```
2. **Compare responses by content:** parse both JSON bodies and compare field names and string values (`"11134.60"` ≠ `"11134.6"`). Exact string comparison also works if your serializer emits no whitespace, but don't rely on it.
3. **`cases.json` must be unchanged:** `git diff --exit-code -- '*cases.json'` must be clean at the end.
4. **Make it fail on purpose once:** replace the truncation in the net-to-gross formula with rounding, run, confirm failures (the Delphi side lost 314 grid cases to the same change), revert, green again. Note the counts.
5. **Manual smoke test** of the running API, e.g. with `curl` or a `.http` file: the four examples from `docs/service-contract.md` (`g0154` → `11134.60`, `g0450` → `99.99`, `g0741` → `-46.51`, `g0337` → `NO_TAX_CLASS`).

## Pitfalls

- **The lost cent may not reproduce with `double`.** .NET on x64 calculates in 64-bit `double`; Delphi Win32 in 80-bit extended. Cases near a cent boundary can differ. Start with the straightforward port (`decimal` for `Currency`, `double` for rates) and run `cases.json`. If cases fail, **report which ids and why**, then decide with the user: emulate 80-bit extended precision for the affected expressions (e.g. exact rational arithmetic with `BigInteger`, rounded to a 64-bit mantissa after each operation, round-half-even), or document the differing cases as a known porting gap.
- **Never make tests pass by special-casing.** No `if id == "g0450"`, no lookup tables of expected results, no edits to `cases.json`. Fix the arithmetic or report the gap.
- **`0.09` is not one number.** In `KiSt := Steuer * 0.09` and `Rate * 0.09` the literal is an 80-bit Extended in Delphi; a C# `0.09` is a double, and `0.09m` is exact decimal. All three differ.
- **Currency rounding vs. truncation.** Storing a product into `Currency` **rounds** to 4 decimals; `Trunc(...)` **truncates**. Don't use one for the other.
- **`decimal` hides the binary step.** `Math.Truncate((brutto - steuer - kist) * 100m)` is exact; Delphi does `× 100` and `Trunc` on the FPU. For values with 3–4 decimals this could land just below an integer in binary. If gross-to-net cases fail, look here.
- **Culture.** Use `CultureInfo.InvariantCulture` for the contract's amounts and German format only for `personal.dat`. Nothing may depend on the machine's culture.
- **Model binding.** See above: it would silently accept invalid requests.
- **Paths.** Find `cases.json` and `personal.dat` relative to the repository (walk up from the executable until the folder `zvoove_Software_Engineer_AI_Case_study_candidate` exists, or accept a path argument), not by an absolute path.
- **Long paths, line endings.** The repo path is deep, and git converts line endings on Windows; `cases.json` content isn't affected (it's read as JSON).

## Deliver

- The three projects under `port/`, building without errors. `.gitignore` on this branch already ignores their `bin/` and `obj/` folders.
- `QUIRK (deliberately not fixed)` comments in the C# core at the same places as in `uLohnrechnerCore.pas`, citing the same rows of `docs/uMain-behavior.md`.
- **`run-tests.ps1`:** add the port check as an optional step. If `dotnet` is on the PATH, run the contract tests and require `RESULT: OK`; if not, print `SKIPPED port tests (no .NET SDK)` and don't fail. The Delphi part must keep working unchanged on a machine without .NET, and the port step must not need Delphi.
- **Docs:**
  - `README.md`: a short "Bonus: C# port" section (how to run, what it proves, results incl. any differing cases).
  - Update the "What was cut" section, where the port is currently listed as not done.
  - `docs/decisions.md`: a new entry for the port choices (status codes, numeric approach, any accepted gap).
  - `docs/service-contract.md`: mention the C# implementation.
- Commits in small steps; a pull request to `main` with the actual test output in its description.
- **Report honestly:** the output of steps 1 and 4, and the list of any failing case ids. Don't summarize away failures.
