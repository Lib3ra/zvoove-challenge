# zvoove-challenge: Mini Payroll Calculator

Case study: separate business logic from the UI of a Delphi VCL form without changing its behavior.
Spec: `zvoove_Software_Engineer_AI_Case_study_candidate/MiniLohnrechner_Case_Study/Case_Study_Mini_Payroll_Calculator.md`

## What was separated, what not, and why

_To do (Part 1)._

## How AI tools were used

_To do._

## Tests: how to run them and what they prove

### Run

From the repository root (cmd or PowerShell):

```
.\run-tests.bat
```

- With a licensed Delphi (command-line compiler available), the script builds `tests\GoldenTests.dpr` for Win32 and runs it.
- **Delphi Community Edition cannot compile from the command line.** Its `dcc32` prints an error and still exits with 0. So the script checks whether the exe exists, not the exit code, and then uses a `GoldenTests.exe` built in the IDE. To build it: open `MiniLohnrechner_Bewerberaufgabe\tests\GoldenTests.dpr`, platform **Win32**, Build.
- The script passes only if the runner prints `RESULT: OK`. Exit code 0 = passed, 1 = failures (each printed with file, line, case and expected vs. actual), 2 = no test exe.
- Developed and run with Delphi 13 Community Edition, built in the IDE.

### What the tests prove

The tests are **golden-file tests of the whole form**: the test program creates the real `TForm1` and drives it through its controls the way a user does (one change event per keystroke, picking a tax class, the church tax box, the reset button). It compares exactly what the user would see: the text of the input fields, the annual total label, and the type and text of every message dialog. Dialogs are closed automatically and logged.

They were **written and passing before any refactoring**, against the unmodified original code. The same test files must pass unchanged after the refactoring. That is the proof that behavior did not change.

Two golden files in `MiniLohnrechner_Bewerberaufgabe\tests\golden\`:

| File | Cases | Where the expected values come from |
|---|---|---|
| `curated.txt` | 21 | Observed by hand in the running original app, one case per row of [`docs/uMain-behavior.md`](docs/uMain-behavior.md): success cases, every error dialog and the check order, and the preserved quirks. Written by hand. |
| `grid.golden.txt` | 1680 | Recorded once from the original code (`GoldenTests record`) in its own commit: every combination of 5 employee numbers, no class or class I to VI, church tax on/off, and 24 gross/net amounts. **Never re-recorded**: a change to this file in a later commit means behavior changed. |

- **Exact comparisons.** `900,9` is not `900,90`, a lost cent fails, a different dialog type fails. This catches behavior changes, not just compile errors.
- **The suite can fail:** changing one expected value made it report the two affected cases and exit with 1.
- **Pinned environment:** the German number format is set before `personal.dat` is loaded, so results don't depend on the machine's regional settings. Win32 only: the app's floating-point results can differ in the last cent on Win64.

### What they do not prove

- Behavior with a **missing `personal.dat`** or a **non-German regional format**: the data file is loaded once per test process with the pinned format. Both were observed or read from the code (see `docs/uMain-behavior.md`).
- Visual details of the form (layout, dialog icons, focus).

## Part 3 artifact

_To do: `.claude/skills/delphi-form-extraction/SKILL.md`, how it was used._

## Next steps (Part 4)

_To do._

## What was cut or not finished

_To do._
