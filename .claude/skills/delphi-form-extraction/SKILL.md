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
6. Each confirmed row becomes a golden-file case in step 3 and, if it is a quirk, a source comment in step 4.

## 2. Map the logic in the form

For each event handler, sort lines into: **UI** (read/write controls, dialogs, focus), **logic** (calculation, validation, rules), **state** (fields that carry over between events). Watch for:
- logic hidden in UI side effects: a handler that writes another edit and relies on its `OnChange` (or a guard flag blocking it)
- dialogs (`ShowMessage`, `MessageDlg`) inside calculations: the core must return an error result instead, and the form shows the dialog, with the same text, type and order of checks
- globals and singletons created in `initialization` sections, file paths relative to the exe
- locale-dependent conversions (`StrToFloat`, `TryStrToCurr`, `Format`, `CurrToStr`) and `Currency` vs `Double` arithmetic
- state the core needs vs state that is UI-only: decide per field, write the decision down

## 3. Pin the behavior with golden-file tests (before any extraction)

Tests written after the refactoring only describe the new code. Pin the original first.
- The test program creates the **original, unmodified form** and drives it through its controls like a user (setting `Edit.Text` fires `OnChange`; call the combo box's `Change`). This also covers wiring that never reaches a core: per-keystroke events, field-change recalculation.
- Expected values live in data files, not code. Two kinds:
  - **curated**: one case per confirmed row of the behavior record, values as observed by hand. Never generated.
  - **grid**: all combinations of the inputs, recorded **once** from the original by the runner's `record` mode, in its own commit.
- Assert **exact** text (`900,9`, the full label caption, dialog kind and text), never "not zero".
- Modal dialogs: close them automatically and log kind + text, so check order and dialog type are tested too.
- Pin the locale **before** units load data in `initialization` (first unit in the test program's `uses`). Same platform as the app (Win32 x87 and Win64 SSE can differ in the last cent).
- One script runs everything and checks the runner's `RESULT:` line, not only the exit code (some compilers print an error and still exit 0).
- All green on the original before you touch it. Commit.

## 4. Extract without changing behavior

- New unit for the core, no `Vcl.*` or `Dialogs` in its `uses`. Dependencies (data lookup, settings) come in through the constructor, so tests can replace them. Careful with interfaces on global objects: reference counting can free them.
- Move code, do not rewrite it: keep the same types (`Currency` stays `Currency`), the same order of operations, the same rounding (`Trunc` stays `Trunc`).
- Every preserved quirk gets a comment right where it happens: `// QUIRK (deliberately not fixed): <what> - see docs/<form>-behavior.md #<row>`.
- The form keeps parsing input and showing output; it must not compute anything itself.
- The golden tests run **unchanged** against the refactored form and stay green. Then add unit tests for the core itself (fake data lookup, plus one test with the real data file).
- Sanity check: break one rule in the core on purpose, confirm a test fails, revert.

**Golden files are never re-recorded after the original is pinned.** A changed golden file in a refactoring PR is a red flag, not a fix.

## Never accept from AI unchecked

- "Fixing" a quirk, or tidying rounding, types or check order while moving code
- Expected test values it computed instead of values observed in the running app
- Re-recording or editing golden files to make tests pass
- Claims that something builds or passes without the actual output
- New behavior in the form (extra validation, different messages) presented as refactoring
