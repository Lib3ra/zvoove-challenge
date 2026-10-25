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
- **Delphi Community Edition cannot compile from the command line.** Its `dcc32` prints an error and still exits with 0. So the script checks whether the exe exists, not the exit code, and then uses the newest `GoldenTests.exe` built in the IDE. To build it: open `MiniLohnrechner_Bewerberaufgabe\tests\GoldenTests.dpr`, platform **Win32**, Build.
- **It refuses a stale exe:** if any `.pas`, `.dfm` or `.dpr` file is newer than the IDE-built exe, it stops with "rebuild" instead of testing old code.
- It passes only if the runner exits with 0 **and** prints `RESULT: OK`. Exit code 0 = passed, 1 = failures (each printed with file, line, case and expected vs. actual), 2 = no usable test exe.
- The logic is in `run-tests.ps1`; `run-tests.bat` only calls it.
- Developed and run with Delphi 13 Community Edition, built in the IDE.

How the runner works internally: [`docs/golden-tests.md`](docs/golden-tests.md).

### What the tests prove

The tests are **golden-file tests of the whole form**: the test program creates the real `TForm1` and drives it through its controls, firing the same event handlers a user does (one change event per keystroke, picking a tax class, the church tax box, the reset button). It compares exactly what the user would see: the text of the input fields, the annual total label, and the type and text of every message dialog. Dialogs are closed automatically and logged.

They were **written and passing before any refactoring**, against the unmodified original code. The same test files must pass unchanged after the refactoring. That is our evidence that behavior did not change, within the limits listed below.

Three golden files in `MiniLohnrechner_Bewerberaufgabe\tests\golden\`:

| File | Cases | What it covers | Where the expected values come from |
|---|---|---|---|
| `curated.txt` | 21 | One case per row of [`docs/uMain-behavior.md`](docs/uMain-behavior.md): success cases, every error dialog and the check order, the preserved quirks | Observed by hand in the running original app, except case 9b (reset), which comes from reading the code. Written by hand. |
| `grid.golden.txt` | 1680 | The calculation: every combination of 5 employee numbers, no class or class I to VI, church tax on/off, 24 gross/net amounts | Recorded from the original code |
| `sequence.golden.txt` | 16 | The event wiring: amount typed key by key, then church tax on **and off**, class change, employee number change, reset, another calculation, clearing the field, checked after every step | Recorded from the original code |

The recorded files are made with `GoldenTests record` on the unmodified original, in their own commits, and are **never re-recorded**: a change to them in a later commit means behavior changed.

- **Exact comparisons.** `900,9` is not `900,90`, a lost cent fails, a different dialog type fails. This catches behavior changes, not just compile errors.
- **The suite can fail:** changing one expected value made it report the two affected cases and exit with 1.
- **Guards against false greens:** every golden file must exist and contain the number of cases it declares; a step that hangs (e.g. a dialog the runner can't close) fails the run after 10 seconds; a stale exe is refused.
- **Pinned environment:** the German number format is set before `personal.dat` is loaded, so results don't depend on the machine's regional settings. Built and run as Win32, like the app. Whether Win64 would give different cents was not checked.

### What they do not prove

- Behavior with a **missing `personal.dat`** or a **non-German regional format**: the data file is loaded once per test process with the pinned format. The first was read from the code, the second observed in the app (see `docs/uMain-behavior.md`).
- Typing is simulated by appending or removing characters at the end. Editing in the middle of a field, selecting text, or focus changes are not simulated.
- Visual details of the form (layout, dialog icons, buttons).

## Part 3 artifact

_To do: `.claude/skills/delphi-form-extraction/SKILL.md`, how it was used._

## Next steps (Part 4)

_To do._

## What was cut or not finished

_To do._
