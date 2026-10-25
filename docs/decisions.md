# Decision log

Why the solution looks the way it does. One entry per decision: what we decided, why, what we rejected, and what it costs.
Status: **decided** (in effect), **proposed** (agreed direction, not built yet), **open** (to be settled later).

## Context in one paragraph

The Delphi app has one window (`uMain.pas` + `uMain.dfm`, like a WinForms view with its code-behind file) and one data unit (`uPersonalstamm.pas`, reads `personal.dat`). The tax calculation, its checks and the annual total live **inside the window class**: they show dialogs and write labels themselves, so nothing can calculate a salary without opening a window. The task is to move that logic into a unit another caller (e.g. a web UI) can use, **without changing any behavior, bugs included**, and to prove it.

---

## D1 Build and run on Windows with Delphi Community Edition, in the IDE
**Decided.** We compile and run the real app instead of submitting uncompiled code.
- **Why:** expected test values must come from the running app; only a real build can run tests.
- **Cost:** Community Edition refuses command-line compiling, and its `dcc32` still exits with 0. Builds happen in the IDE; `run-tests.bat` builds with `dcc32` where the license allows it, uses the IDE-built exe otherwise, and refuses a stale one.
- **Rejected:** submitting without compiling (allowed by the spec, but then nothing is proven).

## D2 Expected values come from the running original, never from reading the code
**Decided.**
- **Why:** reading code gives hypotheses, not facts. The locale bug (all allowances silently 0 on an English Windows) was only found by running the app.
- **How:** behavior record `docs/uMain-behavior.md`: hypothesis, steps, expected from code, **actual from the app**. Clicked through by hand.
- **Rejected:** letting the AI compute expected values. If they're wrong, the tests would pin the AI's mistake.

## D3 The Part 3 artifact is a Claude Code skill, written before Part 1
**Decided.** `.claude/skills/delphi-form-extraction/SKILL.md`.
- **Why:** the spec requires the artifact to be *used* in Parts 1 and 2. Writing it first and following it makes that true; it was corrected twice while being used (D4, review lessons).
- **Rejected:** a checklist written at the end (spec forbids "written afterwards in theory").

## D4 Tests before extraction
**Decided.** First pin the original's behavior with tests, then extract, then run the same tests unchanged.
- **Why:** tests written after a refactoring only describe the new code; they can't prove nothing changed. The first skill draft had this backwards; caught by the user.
- **Consequence:** the tests must work against the original, where the logic is still inside the window (see D6).

## D5 Golden-file tests, curated + recorded
**Decided.** Expected results live in data files, not in test code.
- `curated.txt`: one case per behavior-record row, values observed by hand.
- `grid.golden.txt` (calculation) and `sequence.golden.txt` (event wiring): recorded **once** from the unmodified original, in their own commits, **never re-recorded**.
- **Why:** refactoring can't touch data files by accident; a changed golden file in a refactoring PR is a visible red flag; thousands of combinations are covered without writing them by hand; the same files can later test a service or a port.
- **Rejected:** only hand-written asserts (too few cases); re-recording after changes (would hide regressions).

## D6 Drive the real window in the tests
**Decided.** The test program creates the original `TForm1` without showing it and fires its event handlers like a user.
- **Why:** before the extraction there is no other way to call the logic without changing the code first. It also covers wiring the core will never contain (per-keystroke totals, recalculation on field changes).
- **How:** setting a field's text fires `OnChange`; modal dialogs are closed by a timer and logged; a watchdog fails hanging steps.
- **Cost:** some setup complexity (dialogs, unit initialization order). Explained in `docs/golden-tests.md`.

## D7 Hand-written test runner instead of DUnitX
**Decided.**
- **Why:** DUnitX is only installed for Win64 here, the app is Win32 (D9). Golden files only need "replay and compare"; ~600 lines of plain Delphi without dependencies, explainable line by line.
- **Rejected:** downloading and building DUnitX for Win32 (extra dependency for no gain).

## D8 Pin the German number format before data is loaded
**Decided.** First unit of the test program sets `FormatSettings` to de-DE.
- **Why:** `uPersonalstamm` reads `personal.dat` at program start (in its `initialization` section) with the machine's number format. On an English Windows every allowance is silently 0. Tests must not depend on the machine.

## D9 Win32, same compiler settings as the app
**Decided.** Test program built as Win32 Debug, like the app (range and overflow checks on, no optimization; verified identical in both `.dproj` files).
- **Why:** the Netto → Brutto path loses a cent for some inputs (floating point). Results may differ on another platform; not verified for Win64, so we don't risk it.

## D10 Independent review of the tests before relying on them
**Decided.** A separate AI session reviewed the test PR, looking only for ways the tests could pass while behavior changed.
- **Why:** the author of tests is blind to their gaps. It found real ones: church-tax recalculation and the internal reset were never exercised; a stale exe or a deleted golden file could pass; a hang would block forever. All fixed and verified.

## D11 The annual total belongs to the core, not the window
**Decided.**
- **Why:** the rule "add every net result, never a gross result, reset to 0" is written inside the calculation (`BerechneNetto`), not in the UI code. Keeping it in the core keeps that rule testable and reusable.
- **Note:** *when* calculations happen (on every keystroke) stays a UI matter, so the per-keystroke total behavior remains in the form's wiring.

---

## Part 1: extraction design

## D12 New unit for the core; German names; code moved, not rewritten
**Proposed.** A new unit `uLohnrechnerCore.pas` without any `Vcl` (window) or dialog units.
- **Why German names:** every moved line can be matched to the original by a reviewer. Comments in English.
- **Moved verbatim:** tax-rate table, both formulas, `Trunc` rounding, the `Currency`/`Double` mix, the check order (class before sign). Every preserved quirk gets a `// QUIRK (deliberately not fixed)` comment pointing to its behavior-record row.

## D13 Calculations take all inputs as parameters (stateless)
**Proposed.** `BerechneNetto(Brutto, Personalnummer, Steuerklasse, Kirchensteuer)` instead of a core object that remembers the last employee number, class and church tax.
- **Why:** a future web API is stateless: every request carries all inputs. A core that remembers UI selections fits one window, not a service. The form already holds those values; it passes them on.
- **Rejected:** core object with properties mirroring the form fields (first proposal, revised after thinking through the service case).

## D14 Errors are returned, not shown
**Proposed.** The calculation returns the amount plus an error kind (none / no tax class / negative gross / negative net). The error texts live in the core so every caller shows the same message.
- **Why:** a service has no screen. The window decides how to show it (info box vs. warning, as today); a web API would return an error response.
- **Stays exactly as today:** error result = amount 0, nothing added to the total, same texts, same order of checks.

## D15 Allowance lookup passed in as a function
**Proposed.** The core receives "give me the allowance for employee N" as a function parameter, not the global `Personalstamm` object.
- **Why:** tests can pass a fake (e.g. "file missing" = always 0); a service can later read from a database. A function rather than a Delphi interface, because a reference-counted interface would free the global object.
- **Not changed:** `uPersonalstamm` itself (global object, loads at start, locale-dependent). It is data access, already UI-free; changing it is outside "separate logic from UI" and would risk behavior changes.

## D16 What stays in the window
**Proposed.** Reading and parsing the input fields (incl. "non-numeric employee number becomes 0"), formatting results (`CurrToStr`, the total label, the hard-coded reset text), showing dialogs, the re-entrancy guard, and "recalculate from Brutto whenever a field changes".
- **Why:** these are presentation choices. A web UI would make its own; the core should not dictate them.

## D17 Proof for Part 1
**Proposed.**
1. All golden files pass **unchanged** against the refactored window.
2. A second test mode replays the 1680 calculation cases **directly against the core**, without the window.
3. Unit tests for what the window tests can't reach: missing data file, unknown employee.
4. Deliberately break one rule in the core, confirm the tests go red, revert.

---

## Open (Part 4)

## O1 Where the annual total lives in a service
Per user, per session, persisted? Not decided. The task says not to guess the target architecture; Part 4 will state assumptions.

## O2 Where employee data comes from in a service
`personal.dat` next to the exe won't work for a service. Database or another service, not decided.
