# Working notes: Mini Payroll Calculator case study

Handover notes for continuing the work in a fresh session (e.g. on the Windows machine).
Spec: `zvoove_Software_Engineer_AI_Case_study_candidate/MiniLohnrechner_Case_Study/Case_Study_Mini_Payroll_Calculator.md`
Starter code: `.../MiniLohnrechner_Case_Study/MiniLohnrechner_Bewerberaufgabe/`

## Decisions so far

- **Compile and run on Windows.** Delphi Community Edition on the Windows machine. The Windows session is the main working session because it is the only place that can compile and run tests. The repo (git) is the sync channel; no live session bridging.
- **Expected test values come from the running original, not from reading the code.** Run the unmodified app/logic first, record outputs, then refactor against them.
- **Part 3 artifact = a Claude Code skill** in `.claude/skills/<name>/SKILL.md`, committed to the repo. It is written early and used during Parts 1 and 2 (spec requires it to be actually used).
- **Bonus port: shelved** for now.
- **Annual total ownership: open.** Is the net-pay accumulation business logic (moves to the core) or UI state (stays in the form)? Decide before Part 1.

## First steps on Windows

1. Install Delphi Community Edition, clone the repo.
2. Check whether command-line builds work (`msbuild` via `rsvars.bat`, or `dcc32`). Community Edition may refuse command-line compiling; this affects R12 ("one command or script"). If it refuses: ship `run-tests.bat` for the reviewers and run tests from the IDE ourselves, and say so in the README.
3. Build and run the untouched starter app. Click through the quirks list below and confirm or refute each one. Note exact outputs (these become test expectations).
4. Write the skill draft, then start Part 1.

## Requirements

M = mandatory, O = optional, as labeled in the spec.

| ID | Requirement | M/O | Notes |
|---|---|---|---|
| R1 | ~4h, max 6h; parts in order; say what was cut | M | Feeds R27 |
| R2 | Use AI tools; show how they are steered and checked | M | Feeds R24 |
| R3 | Delphi install recommended, not required | O | If not compiled, must say so in README |
| R4 | Separate logic and UI so another caller (e.g. web UI) could connect without changing the logic | M | Design is free |
| R5 | App stays complete and runnable as a Windows app | M | |
| R6 | Form no longer contains business logic | M | Ambiguous: annual total, validation-message order |
| R7 | Do not improve the app; preserve quirks and bugs | M | |
| R8 | Document each quirk as a source comment at the relevant place, not in the README | M | |
| R9 | Web UI is out of scope | — | |
| R10 | Automated tests for the extracted logic | M | |
| R11 | At minimum: success case, error cases, discovered edge cases | M | |
| R12 | Tests run with one command or script the reviewers can run | M | See Community Edition CLI risk |
| R13 | Tests catch behavior changes, not just compilation | M | Exact expected values |
| R14 | One small artifact to help repeat this extraction | M | Decided: skill |
| R15 | Artifact actually used in Parts 1 and 2 | M | Write it first |
| R16 | About one page or a few small files max | M | |
| R17 | Three next steps toward a standalone service, ranked, 1-2 sentences why | M | |
| R18 | Do not guess the target architecture; state assumptions | M | |
| R19 | Implement the smallest meaningful slice of step 1 | M | |
| R20 | Slice runs and is tested; not a design essay | M | |
| R21 | Bonus: port core logic incl. quirks to another language | O | Shelved |
| R22 | Bonus: shared data file of test cases run against both implementations | O | Shelved |
| R23 | README: what was separated, what not, why | M | |
| R24 | README: AI use (2-3 key prompts or session excerpt, one place the AI was wrong/incomplete and how it was noticed, what never to let AI do unchecked) | M | Keep notes while working |
| R25 | README: how to run tests, what they prove | M | |
| R26 | README: where the Part 3 artifact is and how it is used; ranked next steps and the slice built | M | |
| R27 | README: what was cut or not finished | M | |
| R28 | Be able to explain every submitted line in the follow-up | M | |

## Quirks (hypotheses from reading the code, not yet verified)

Each confirmed quirk needs a preserving source comment and a test.

1. `BerechneNetto` adds every result to the annual total, so every keystroke in Brutto and every change of employee number, tax class or church tax (they call `editBruttoChange`) adds to it.
2. `BerechneBrutto` never adds to the annual total.
3. The inverse formula ignores the clamp of the taxable base at 0. When net < allowance the gross is wrong, possibly negative. Example: employee 1003 (allowance 1000), class I, net 100 gives (100 - 140) / 0.86, about -46.51.
4. Rounding uses `Trunc`, not round. `Steuer`/`KiSt` are `Currency` (assigning `Currency * Double` rounds to 4 decimals); the Brutto path stays in `Double`, so values like x.xx9999 may lose a cent. Netto -> Brutto -> Netto does not round-trip.
5. Error paths return 0, and the form writes `0` into the other field. Check order: tax class first, then negative input. Different dialogs (`ShowMessage` vs `MessageDlg` warning), shown again on every keystroke.
6. Changing employee number, tax class or church tax always recalculates from Brutto, even if Netto was edited last.
7. Non-numeric employee number becomes 0; unknown employee number gives allowance 0, silently.
8. `personal.dat` is loaded from the exe directory by a global singleton in unit `initialization`; missing file means all allowances are 0, silently. Main obstacle to testability.
9. Locale-dependent parsing: `"250,00"` only parses with a German decimal separator. The reset caption is hard-coded `'0,00'` while the running total uses `%.2f` with the current locale. Tests must pin `FormatSettings`.
10. Possibly intended: classes II and IV share rate 0.18; `CurrToStr` shows `1234,5` rather than `1234,50`; division by zero is unreachable (max rate 0.30 * 1.09).

Data: `personal.dat` = `1001;250,00`, `1002;0,00`, `1003;1000,00` (CRLF).
