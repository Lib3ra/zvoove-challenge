---
name: delphi-form-extraction
description: Extract business logic from a Delphi VCL form into a UI-free core unit without changing behavior, and prove it with tests. Use when a form mixes calculation, validation or state with UI code and the logic must become reusable by another caller.
---

# Extract business logic from a Delphi form, behavior unchanged

Goal: the form only reads controls, calls the core and shows results. The core has no VCL, no dialogs, no globals.
Behavior stays exactly as it was, bugs included. Work through the steps in order; do not skip step 1.

## 1. Record the original's behavior first (before touching code)

Expected values come from the **running, unmodified app**, never from reading the code alone.

1. Build and run the untouched app. Note the toolchain facts (compiler version, whether command-line builds work).
2. Pin the environment: Windows regional format (decimal separator!), working directory, data files next to the exe. Write it at the top of the record.
3. Read the form and list **hypotheses**: every calculation, every error path, every piece of state that survives between events (totals, flags, "last edited" fields), every file or global it reads.
4. Turn each hypothesis into a row in `docs/<form>-behavior.md`: `# | hypothesis | exact steps | expected (from code) | actual (from app)`. Steps must say how input is entered: typing char by char fires `OnChange` per keystroke.
5. Click through, fill in **actual** verbatim (as displayed, e.g. `900,9`, not `900.90`). Where actual differs from expected, actual wins and the code reading was wrong.
6. Each confirmed row becomes a test case in step 4 and, if it is a quirk, a source comment in step 3.

## 2. Map the logic in the form

For each event handler, sort lines into: **UI** (read/write controls, dialogs, focus), **logic** (calculation, validation, rules), **state** (fields that carry over between events). Watch for:
- logic hidden in UI side effects: a handler that writes another edit and relies on its `OnChange` (or a guard flag blocking it)
- dialogs (`ShowMessage`, `MessageDlg`) inside calculations: the core must return an error result instead, and the form shows the dialog, with the same text, type and order of checks
- globals and singletons created in `initialization` sections, file paths relative to the exe
- locale-dependent conversions (`StrToFloat`, `TryStrToCurr`, `Format`, `CurrToStr`) and `Currency` vs `Double` arithmetic
- state the core needs vs state that is UI-only: decide per field, write the decision down

## 3. Extract without changing behavior

- New unit for the core, no `Vcl.*` or `Dialogs` in its `uses`. Dependencies (data lookup, settings) come in through the constructor or an interface, so tests can replace them.
- Move code, do not rewrite it: keep the same types (`Currency` stays `Currency`), the same order of operations, the same rounding (`Trunc` stays `Trunc`).
- Every preserved quirk gets a comment right where it happens: `// QUIRK (deliberately not fixed): <what> - see docs/<form>-behavior.md #<row>`.
- The form keeps parsing input and showing output; it must not compute anything itself.
- Rebuild and repeat a few rows of the behavior record by hand in the refactored app.

## 4. Prove it with tests

- One test per confirmed row of the behavior record: success cases, every error path, every quirk. Assert **exact** values, never "not zero" or "greater than".
- Pin `FormatSettings` in the tests; never depend on the machine's locale.
- Use a fake for data lookups; add one test that loads the real data file format.
- One script runs everything. Check the result itself (test binary exists, report says 0 failures): some compilers print an error and still exit 0.
- Sanity check: break one rule in the core on purpose, confirm a test fails, revert.

## Never accept from AI unchecked

- "Fixing" a quirk, or tidying rounding, types or check order while moving code
- Expected test values it computed instead of values observed in the running app
- Claims that something builds or passes without the actual output
- New behavior in the form (extra validation, different messages) presented as refactoring
