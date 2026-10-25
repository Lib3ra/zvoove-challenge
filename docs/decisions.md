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
- **Repeated for the extraction PR**, focused on behavior changes and false greens: no behavior change found (side-effect order, label rule, exceptions, floating point, object lifetime all checked). It found three wrong row references in the AI-written quirk comments, an unmarked quirk (tax class outside 1..6 is taxed at rate 0), and a bypassable no-UI check. All fixed.

## D11 The annual total belongs to the core, not the window
**Decided.**
- **Why:** the rule "add every net result, never a gross result, reset to 0" is written inside the calculation (`BerechneNetto`), not in the UI code. Keeping it in the core keeps that rule testable and reusable.
- **Note:** *when* calculations happen (on every keystroke) stays a UI matter, so the per-keystroke total behavior remains in the form's wiring.

---

## Part 1: extraction design

## D12 New unit for the core; German names; code moved, not rewritten
**Decided.** A new unit `uLohnrechnerCore.pas` without any `Vcl` (window) or dialog units.
- **Why German names:** every moved line can be matched to the original by a reviewer. Comments in English.
- **Moved verbatim:** tax-rate table, both formulas, `Trunc` rounding, the `Currency`/`Double` mix, the check order (class before sign). Every preserved quirk gets a `// QUIRK (deliberately not fixed)` comment pointing to its behavior-record row.

## D13 Calculations take all inputs as parameters (stateless)
**Decided.** `BerechneNetto(Brutto, Personalnummer, Steuerklasse, Kirchensteuer)` instead of a core object that remembers the last employee number, class and church tax.
- **Why:** a future web API is stateless: every request carries all inputs. A core that remembers UI selections fits one window, not a service. The form already holds those values; it passes them on.
- **Rejected:** core object with properties mirroring the form fields (first proposal, revised after thinking through the service case).
- **Keystroke quirks still work:** they come from *when* the window calls the calculation (its `OnChange` handlers fire on every key and on every class / church / employee change), not from the core remembering inputs. The window keeps that wiring unchanged and passes its current values on each call; the core keeps adding every net result to the total. Pinned by curated cases 1, 5a, 6, 7c and the sequence file.
- **Trap found while checking this:** today the total label is only rewritten after a *successful* net calculation (`BerechneNetto` exits before the label update on errors). The window must keep that: update the label only on success. Updating it always would look identical under German format, but on an English Windows would turn the hard-coded reset text `0,00` into `0.00` after an error. The golden tests pin German format and would **not** catch this, so it gets a source comment.

## D14 Errors are returned, not shown
**Decided.** The calculation returns the amount plus an error kind (none / no tax class / negative gross / negative net). The error texts live in the core so every caller shows the same message.
- **Why:** a service has no screen. The window decides how to show it (info box vs. warning, as today); a web API would return an error response.
- **Stays exactly as today:** error result = amount 0, nothing added to the total, same texts, same order of checks.

## D15 Allowance lookup passed in as a function
**Decided.** The core receives "give me the allowance for employee N" as a function parameter, not the global `Personalstamm` object.
- **Why:** tests can pass a fake (e.g. "file missing" = always 0); a service can later read from a database. A function rather than a Delphi interface, because a reference-counted interface would free the global object.
- **Not changed:** `uPersonalstamm` itself (global object, loads at start, locale-dependent). It is data access, already UI-free; changing it is outside "separate logic from UI" and would risk behavior changes.

## D16 What stays in the window
**Decided.** These lines stay in the window **unchanged**: reading and parsing the input fields, formatting results (`CurrToStr`, the total label, the hard-coded reset text), showing dialogs, the re-entrancy guard, and "recalculate from Brutto whenever a field changes".
- **Nothing new is introduced here.** Example: the original already turns a non-numeric employee number into 0 (original `uMain.pas:136-137`, now lines 92-93; quirk 7, observed in row 7a). That code stays where it is; the core receives a number.
- **Why in the window, not the core:** these are presentation choices tied to text fields. A web API receives numbers from JSON, where "abc" can't occur, and decides itself how to reject bad input. Moving the parsing into the core would force that UI quirk on every future caller.
- **Test used to draw the line:** "Would a web API caller need the same rule?" Yes → business logic → core (e.g. "gross must not be negative"). No, it only exists because the input is a text field → window (is `abc` a number, German comma, label decimals).
- **Likely objection:** "invalid input silently means no allowance" sounds like a business policy. The policy ("no known employee → allowance 0") stays in the allowance lookup and applies to every caller; only the text-to-number conversion stays in the window. Together they give exactly today's result.

## D17 Proof for Part 1
**Decided.**
1. All golden files pass **unchanged** against the refactored window.
2. A second test mode replays the 1680 calculation cases **directly against the core**, without the window.
3. Unit tests for what the window tests can't reach: missing data file, unknown employee.
4. Deliberately break one rule in the core, confirm the tests go red, revert.
- **Result:** 1 and 2 green (1717 window cases; 1680 core cases + 11 core unit tests, the 11th added after the review of this PR). Breaking the core by "fixing" the lost cent (`Round` instead of `Trunc`) failed 320 window cases, 314 core cases and 1 unit test; reverted. The watchdog was proven with a self-test mode. A check in `run-tests` fails if the core ever uses window or dialog units.

## D18 No extra golden files for edge inputs and environment variants
**Decided.** Considered right before the extraction (the last clean moment to record from the original), and skipped.
- **Considered:** an edge-input file (`1.000`, `,5`, `1E3`, more than 4 decimals, amounts large enough to overflow) and golden runs under English format and without `personal.dat`.
- **Why skipped:** not required by the spec: success, error and discovered edge cases are already covered or planned (missing data file and unknown employee via core unit tests, D17). The extraction moves code verbatim with the same types, so behavior on unusual input should not change.
- **Residual risk, accepted and stated:** unusual inputs and overflow behavior are not pinned by a recording; the label-update trap (D13) and English-format behavior are protected by source comments and code review, not by a test.

---

## Part 4: towards a standalone service

The target architecture is not decided, so these decisions are built on stated assumptions (README, Part 4: A1–A7) rather than on a chosen stack.

## D19 The annual total is not part of the service
**Decided.** Replaces open question O1.
- **Why:** the window's total is a UI session counter: it adds up every calculation in a window session, including each keystroke and across employees. It's not a payroll figure. The service answers one question: the result of one calculation.
- **No code change:** the core class keeps the total, because the Delphi window uses it (D11). The service contract simply doesn't expose it.
- **Consequence, stated:** a web client that rebuilds the counter may do it slightly differently (e.g. also add gross results). Acceptable for a client feature.
- **If the business wants a real annual total** (per employee, per year, from actual payroll runs): that's a new feature with its own data, not a port of this one.

## D20 Next steps, ranked
**Decided.**
1. **Service contract + portable proof.** A language-neutral request/response and the golden calculation cases as neutral data, proven lossless. *First, because every option for the open architecture needs it, and it depends on no open decision.*
2. **Remove the hidden dependencies that break as a service.** Employee data is loaded at program start, from the exe's folder, with the machine's number format; on an English server every allowance would silently be 0 (quirk 9a). Make data source and format explicit and replaceable, with the Delphi app passing exactly what it does today. *Second, because it's the biggest risk of any server deployment; making it replaceable needs no decision on the final data source.*
3. **Host the core behind the contract, then migrate callers.** Thin network layer, replay the neutral cases over the network, then switch the Delphi app (behind a fallback) and add a frontend. A port, if the stack isn't Delphi, happens here, checked by the same cases. *Last, because it depends on the open stack decision; steps 1 and 2 make it low-risk.*
- **Considered and rejected as next steps:** a web frontend (comes after the service exists; out of scope per spec); hosting first (would guess the architecture).
- **If the data source were replaced anyway,** step 2 would shrink, and the order would be contract → host → migrate callers.

## D21 The slice of step 1: contract wrapper + neutral cases, no extra program
**Decided.**
- **Built:** `uLohnrechnerVertrag.pas` (JSON in/out, stable error codes, decimal strings), `tests/golden/contract/cases.json` generated from the recorded grid, and checks: lossless round trip back to the golden lines, freshness of `cases.json`, all 1680 requests through the wrapper, malformed requests rejected.
- **Decimal strings for amounts:** JSON numbers are binary floating point in most stacks; amounts here are exact decimals and single cents matter.
- **`INVALID_REQUEST` is new behavior,** the only one: the window never receives malformed JSON, so there is nothing original to keep. The contract rejects instead of guessing.
- **Left out:** a small command-line program for live demos (JSON in, JSON out, without any window code). Useful for showing and as an extra separation proof, but not needed by the next steps; left out to keep the slice smallest.
- **Stopgap until step 2:** like the tests, the reference implementation still relies on `personal.dat` being loaded with German number format.

## Open questions for the team (Part 4)

## O2 Where employee data comes from in a service
`personal.dat` next to the exe won't work for a service. Database or another service, not decided. Step 2 makes it replaceable without deciding it.

## O3 Target stack and hosting
Delphi service, port to another language, cloud or on-premises: not decided. Step 3 depends on it; `cases.json` checks whichever is chosen.

## O4 Should quirks ever be fixed?
Every quirk is kept on purpose. Fixing one is a business decision per quirk, with the golden files and `cases.json` deliberately updated in a reviewed change.
