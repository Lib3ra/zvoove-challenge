# zvoove-challenge: Mini Payroll Calculator

Case study: separate business logic from the UI of a Delphi VCL form without changing its behavior.
Spec: `zvoove_Software_Engineer_AI_Case_study_candidate/MiniLohnrechner_Case_Study/Case_Study_Mini_Payroll_Calculator.md`

## What was separated, what not, and why

Before: the tax calculation, its checks and the annual total were private methods of the window class `TForm1` (`uMain.pas`). They showed dialogs and wrote labels themselves, so nothing could calculate without opening a window.

**Separated** into the new unit `uLohnrechnerCore.pas` (no window units, no dialogs; a check in `run-tests` enforces it):
- tax rates, `BerechneNetto` (gross → net), `BerechneBrutto` (net → gross), the checks and their order, the annual total
- calculations take **all inputs as parameters** (employee number, class, church tax, amount), so a stateless caller like a web API can use them; the only state is the annual total
- errors are **returned** (amount 0 + error kind, with the original texts) instead of shown
- the allowance lookup is **passed in** as a function, so tests or a service can supply their own data

**Not separated**, kept in the window on purpose:
- parsing the input fields and formatting results (text field matters, e.g. "non-numeric employee number becomes 0", German comma, label text)
- showing dialogs and choosing their type
- the event wiring: *when* a calculation runs (on every keystroke and field change). The per-keystroke quirks therefore still happen exactly as before.

**Not changed:** `uPersonalstamm.pas` (data access, already free of UI; it only gained comments) and `uMain.dfm` (the window layout).

The code was moved line by line with the same types and rounding. Every preserved quirk has a `QUIRK (deliberately not fixed)` comment where it happens. Reasons for each choice: [`docs/decisions.md`](docs/decisions.md) (D11–D18).

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
- It checks that `uLohnrechnerCore.pas` uses no window or dialog units, then runs the test exe twice: **window mode** (all golden files against the real window) and **core mode** (the calculation grid against the core without any window, plus core unit tests).
- It passes only if both runs exit with 0 **and** print `RESULT: OK`. Exit code 0 = passed, 1 = failures (each printed with file, line, case and expected vs. actual), 2 = no usable test exe.
- The logic is in `run-tests.ps1`; `run-tests.bat` only calls it.
- Developed and run with Delphi 13 Community Edition, built in the IDE.

How the runner works internally: [`docs/golden-tests.md`](docs/golden-tests.md).

### What the tests prove

The tests are **golden-file tests of the whole form**: the test program creates the real `TForm1` and drives it through its controls, firing the same event handlers a user does (one change event per keystroke, picking a tax class, the church tax box, the reset button). It compares exactly what the user would see: the text of the input fields, the annual total label, and the type and text of every message dialog. Dialogs are closed automatically and logged.

They were **written and passing before any refactoring**, against the unmodified original code. After the extraction, the **same, unchanged** golden files pass against the refactored window. That is our evidence that behavior did not change, within the limits listed below.

The extracted core is also tested **on its own**, without any window:
- **Core mode** replays the 1680 calculation cases directly against `TLohnrechner`, through a small adapter that does what any other caller (e.g. a web API) would do: parse, call, format. This shows another caller can use the logic unchanged.
- **11 core unit tests** (`tests/uCoreTests.pas`): missing data file (lookup returns 0), the lookup being passed in, unknown employee, every error with its text and the check order, the lost cent, the negative gross, the annual total and reset. Expected values come from the behavior record or recorded cases, each named in the test. One exception, marked as such: a tax class outside 1..6 (e.g. 7) is taxed at rate 0 without an error. The window can't produce it, so the expected values come from the code; it matters for future callers such as a web API.

Core mode proves the core on its own; **only window mode proves the window**. The core-mode adapter is a copy of the *new* window handlers, so a mistake shared by both would pass core mode. It would still fail window mode, whose expected values come from the original.

Three golden files in `MiniLohnrechner_Bewerberaufgabe\tests\golden\`:

| File | Cases | What it covers | Where the expected values come from |
|---|---|---|---|
| `curated.txt` | 21 | One case per row of [`docs/uMain-behavior.md`](docs/uMain-behavior.md): success cases, every error dialog and the check order, the preserved quirks | Observed by hand in the running original app, except case 9b (reset), which comes from reading the code. Written by hand. |
| `grid.golden.txt` | 1680 | The calculation: every combination of 5 employee numbers, no class or class I to VI, church tax on/off, 24 gross/net amounts | Recorded from the original code |
| `sequence.golden.txt` | 16 | The event wiring: amount typed key by key, then church tax on **and off**, class change, employee number change, reset, another calculation, clearing the field, checked after every step | Recorded from the original code |

The recorded files are made with `GoldenTests record` on the unmodified original, in their own commits, and are **never re-recorded**: a change to them in a later commit means behavior changed.

- **Exact comparisons.** `900,9` is not `900,90`, a lost cent fails, a different dialog type fails. This catches behavior changes, not just compile errors.
- **The suite catches a real behavior change:** we deliberately "fixed" the lost cent in the core (`Round` instead of `Trunc` in net → gross). Result: 320 window cases and 314 core cases failed, including the hand-observed cases, plus the unit test for lost cents; exit code 1. Then reverted.
- **Guards against false greens:** every golden file must exist and contain the number of cases it declares; a step that hangs (e.g. a dialog the runner can't close) fails the run after 10 seconds (proven with `GoldenTests selftest-watchdog`: ended after 10.2 s with exit code 1); a stale exe is refused; the core may only use `System` units (an allow-list, checked after removing comments; units used indirectly by those are not checked).
- **Pinned environment:** the German number format is set before `personal.dat` is loaded, so results don't depend on the machine's regional settings. Built and run as Win32, like the app. Whether Win64 would give different cents was not checked.

### What they do not prove

- The window with a **missing `personal.dat`** or a **non-German regional format**: the data file is loaded once per test process with the pinned format. The core's side of "no data" (allowance 0) is unit-tested; the file loading itself (`uPersonalstamm`, unchanged) and the English-format display are not. The window's rule "update the total label only after a success" only differs under English format, so it is protected by a source comment, not a test.
- Unusual input (`1.000`, `1E3`, more than 4 decimals) and overflow with huge amounts were not recorded (decision D18).
- Only the Debug build is tested, the configuration the app was observed in. An optimized Release build was not tested; floating-point results could in theory differ there.
- Typing is simulated by appending or removing characters at the end. Editing in the middle of a field, selecting text, or focus changes are not simulated.
- Visual details of the form (layout, dialog icons, buttons).

## Part 3 artifact: the extraction skill

**Where:** [`.claude/skills/delphi-form-extraction/SKILL.md`](.claude/skills/delphi-form-extraction/SKILL.md), one file.

**What it is:** a Claude Code skill, i.e. a Markdown file with instructions that Claude Code loads when a task matches its description ("extract business logic from a Delphi VCL form without changing behavior"). It is plain text, so it works just as well as a checklist for a colleague without AI. It has four steps and a list of things never to accept from AI unchecked:

1. Record the original's behavior in the running app, before touching code
2. Map the logic in the form (UI vs. logic vs. state, and the typical traps)
3. Pin the behavior with golden-file tests against the original, before any extraction
4. Extract without changing behavior, run the same tests unchanged

### How it was used here

It was written **before Part 1** and then followed step by step. Each step produced something in this repository:

| Skill step | What it produced | Where / commits |
|---|---|---|
| 1. Record behavior | Behavior record: 23 hypotheses, clicked through by hand in the running original | [`docs/uMain-behavior.md`](docs/uMain-behavior.md), 67cbfd2, 8804211 (PR #1) |
| 2. Map the logic | What moves to the core, what stays in the window, and why | [`docs/decisions.md`](docs/decisions.md) D11–D16, 5661c9c |
| 3. Golden-file tests | Runner, 21 curated + 1680 + 16 recorded cases, green on the original | `tests/`, ac2a586, 27598bc, 6d1bd87 (PR #2) |
| 3. Independent review | A second AI session hunted for false greens; gaps fixed | 73cbd29 |
| 4. Extract | `uLohnrechnerCore.pas`, `QUIRK (deliberately not fixed)` comments in the format the skill prescribes, same tests green | c196340, 9dfb9fe (PR #3) |
| 4. Break on purpose | "Fixed" the lost cent; 634 golden cases failed; reverted | PR #3 description |
| Never accept unchecked | Expected values only from the running app or recorded from the original; golden files never re-recorded after the extraction; AI-written quirk references checked against the record (three were wrong) | PR #3, 6813a72 |

**It changed while being used**, which is the strongest sign that it was used and not written afterwards:
- **7f57964:** the first draft had tests *after* the extraction, where they can only describe the new code. I caught it before Part 1; tests moved before the extraction, golden-file rules added.
- **73cbd29:** lessons from the independent review added: trigger every event handler after input in both directions, refuse a stale test exe, guard golden files against truncation, let an independent reviewer look for false greens.

### How a colleague uses it on the next form

- **With Claude Code:** open the repository and ask, e.g., "extract the business logic from `uKunde.pas` following the delphi-form-extraction skill", or call it by name with `/delphi-form-extraction`. The skill tells Claude the order of work, what to verify, and what to leave to the human (expected values, approving golden recordings).
- **Without AI:** read it top to bottom as a checklist. Step 1 and the "never accept" list matter most.
- **Test template:** `tests/uGoldenRunner.pas` is reusable for another form. Only the control names in `Field` and the recorded input values are form-specific; the file format, dialog catcher, watchdog and record/verify modes stay the same. How it works: [`docs/golden-tests.md`](docs/golden-tests.md).

## Next steps (Part 4)

_To do._

## What was cut or not finished

_To do._
