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

**Tool:** Claude Code (desktop app), as the main working session from start to end, with separate Claude sessions (subagents) for two independent reviews. All work went through git branches and pull requests, one per part, which I reviewed and merged.

**Who did what:**
- **The AI** wrote the code, the tests, the test runner and the docs, ran the test scripts, and proposed designs and next steps.
- **I** decided: the order of work, what counts as business logic, the architecture choices (e.g. the annual total), what to cut. I clicked through the original app by hand to record its behavior (the expected test values come from there), built every Delphi project in the IDE (Community Edition can't compile from the command line), and reviewed and merged every pull request.

### Key prompts

1. **Tests before the extraction.** The first plan had tests after the refactoring. Reading the spec for Part 2, I asked:
   > "part 2 is asking us to prove that we havent changed behavior. we can only prove that by showing what we tested at the start no? shouldnt we start with the tests, extract business logic and then run tests again?"
   
   This changed the whole approach: golden-file tests against the untouched original first, then the extraction with the same tests unchanged.
2. **An independent check of the AI's own work.**
   > "run a /review subagent in parallel so they can assess what we did and also sanity check it. should this be added to the skill?"
   
   Two reviews by separate sessions found real gaps (below). It's now a step in the Part 3 skill.
3. **Deciding the architecture myself.** The AI proposed passing the annual total through the service API. I disagreed:
   > "the total that is added up isnt that a client side "feature", the api should only return the result of a calculation and the client can do what it wants with that"
   
   That became decision D19: the service returns one calculation; the total stays a feature of the window.

Also decisive: when the AI wanted to record the app's behavior by UI automation, I asked it to tell me what to expect and entered everything myself, so the expected values are my observations, not the AI's.

### Where the AI was wrong, and how I noticed

- **The skill had the steps in the wrong order.** The first draft of the Part 3 skill said "extract, then test". Tests written after a refactoring only describe the new code; they can't prove nothing changed. *Noticed by me*, comparing the plan with Part 2 of the spec, before any code was written. Fixed in the skill (7f57964).
- **Wrong references in its own quirk comments.** Three of the `QUIRK (deliberately not fixed)` comments the AI wrote cited the wrong row of the behavior record, e.g. a row "#4" that doesn't exist. The code was right; the comments looked plausible. *Noticed by the independent review*, which checked every reference against `docs/uMain-behavior.md`; I verified each finding before it was fixed (6813a72).
- **Code that didn't compile, twice in a row.** In the Part 4 contract unit the AI put JSON examples inside a Delphi `{ }` comment; the first `}` of the JSON ended the comment, and the rest of the file was read as code. Its fix then contained a literal `*)` inside the new `(* *)` comment, which closed that one early. *Noticed by the compiler* when I built in the IDE. The AI could not compile anything itself, so every claim of "should work" was only true after my build.

Smaller ones of the same kind: a guess presented as fact (that Win64 would give different cents; never verified, now worded as untested), and instructions for running the test exe that didn't work in PowerShell.

### What I would never let AI do unchecked

- **Define expected values.** If the AI computes what the right result is, the tests pin the AI's mistake. Here they came from my click-through of the running original or were recorded from the original code.
- **Change golden files or "fix" behavior.** Re-recording a golden file to make tests pass would hide exactly the regression the tests exist for. Same for quietly fixing a quirk the task says to keep.
- **Report "it builds" or "tests pass" without the output.** The AI couldn't compile the Delphi code, so every Delphi build was mine, in the IDE. (The C# port is the exception: built and run by the AI on the Mac, with the output in its pull request.) Test results in this README come from actual test output, not from a description of it; after each key step I ran the suite in my own terminal.
- **Make the design decisions.** What is business logic, what the service returns, what to cut: the AI proposed, I decided, and the reasons are in `docs/decisions.md`.
- **Merge its own work.** Every part went through a pull request I reviewed.

## Tests: how to run them and what they prove

### Run

From the repository root (cmd or PowerShell):

```
.\run-tests.bat
```

- With a licensed Delphi (command-line compiler available), the script builds `tests\GoldenTests.dpr` for Win32 and runs it.
- **Delphi Community Edition cannot compile from the command line.** Its `dcc32` prints an error and still exits with 0. So the script checks whether the exe exists, not the exit code, and then uses the newest `GoldenTests.exe` built in the IDE. To build it: open `MiniLohnrechner_Bewerberaufgabe\tests\GoldenTests.dpr`, platform **Win32**, Build.
- **It refuses a stale exe:** if any `.pas`, `.dfm` or `.dpr` file is newer than the IDE-built exe, it stops with "rebuild" instead of testing old code.
- It checks that the core and the contract wrapper use no window or dialog units, then runs the test exe three times: **window mode** (all golden files against the real window), **core mode** (the calculation grid against the core without any window, plus core unit tests) and **contract mode** (the Part 4 service contract, see below).
- It passes only if all runs exit with 0 **and** print `RESULT: OK`. Exit code 0 = passed, 1 = failures (each printed with file, line, case and expected vs. actual), 2 = no usable test exe.
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
- **Guards against false greens:** every golden file must exist and contain the number of cases it declares; a step that hangs (e.g. a dialog the runner can't close) fails the run after 10 seconds (proven with `GoldenTests selftest-watchdog`: ended after 10.2 s with exit code 1); a stale exe is refused; the core may only use `System` units and the contract wrapper only `System` units plus the core (an allow-list, checked after removing comments; units used indirectly by those are not checked).
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

## Next steps towards a standalone service (Part 4)

The target architecture isn't decided, so I don't guess it. These are my assumptions, and the steps are chosen to be right whatever is decided later.

### Assumptions

- **A1** "Standalone service" means: other programs (e.g. a future web frontend) call the payroll calculation over a network instead of it being built into the Delphi window.
- **A2** Behavior stays identical, quirks included, until the business explicitly decides otherwise.
- **A3** The Delphi app keeps working throughout; nothing is switched off before its replacement is proven.
- **A4** Target stack and hosting are open (Delphi service, port to another language, cloud or on-premises).
- **A5** In a service, employee data won't come from a `personal.dat` next to an exe; where it comes from is open.
- **A6** The service returns the result of **one calculation**. The window's annual total is a UI session counter, not part of the service; a real annual total per employee and year would be a new feature.
- **A7** A web frontend is not a step towards the service; it comes after the service exists.

### The three most important next steps, ranked

1. **Define the service contract and make the proof portable.** A language-neutral request/response for one calculation, and the golden calculation cases as neutral test data, proven lossless against the recordings. *First, because every option in A4 needs exactly this and it depends on no open decision. Today's golden files speak "window" (German commas, dialog types), so a service can't be checked against them.*
2. **Remove the hidden dependencies that break as a service.** Employee data is loaded at program start, from the exe's folder, with the machine's number format. On an English server every allowance would silently be 0. Make data source and number format explicit and replaceable, with the Delphi app passing exactly what it does today. *Second, because it's the biggest risk of any server deployment, and making it replaceable needs no decision on the final data source.*
3. **Host the core behind the contract, then migrate callers.** A thin network layer that replays the neutral cases over the network; then the Delphi app switches to the service behind a fallback, and a frontend can follow. If the stack isn't Delphi, the port happens here, checked by the same cases. *Last, because it depends on the open stack decision; steps 1 and 2 make it low-risk.*

In one sentence: first make the behavior **checkable** outside the window, then **safe to run on a server**, then **host it and move callers over**.

### The slice built: step 1

- **Contract wrapper** `MiniLohnrechner_Bewerberaufgabe/uLohnrechnerVertrag.pas`: JSON request in, JSON response out, around the unchanged core. Stable error codes (`NO_TAX_CLASS`, `NEGATIVE_GROSS`, `NEGATIVE_NET`) instead of dialogs, amounts as decimal strings so no stack loses a cent, a fresh core per call (stateless). No business logic, only `System` units.
- **Neutral test data** `tests/golden/contract/cases.json`: all 1680 recorded calculation cases as request + expected response, generated from `grid.golden.txt`. Any implementation in any stack can be checked against it.
- **Proof**, part of `.\run-tests.bat` (third run, `contract`):
  - **round trip:** every case translated into the contract and back into the window's format equals the recorded golden lines byte for byte. `cases.json` says exactly what the original app showed.
  - **freshness:** `cases.json` is exactly what the converter generates (no hand edits, not stale).
  - **contract function:** all 1680 requests through the wrapper give the expected response.
  - **invalid requests:** malformed requests are rejected with `INVALID_REQUEST`, the one new behavior (the window never receives JSON).

Specification, examples and how to check another implementation: [`docs/service-contract.md`](docs/service-contract.md). Reasons: [`docs/decisions.md`](docs/decisions.md) D19–D21.

**Deliberately not in the slice:** hosting (step 3), the data source (step 2), the annual total (A6), and a small command-line program for live demos (useful, but not needed by the next steps).

### Open questions for the team

- Where does employee data come from in a service (A5)?
- Is a real annual total per employee and year wanted (A6)?
- Which stack and hosting (A4)?
- Should any quirk ever be fixed? That's a business decision per quirk, with golden files and `cases.json` deliberately updated.

## Bonus: C# port

The extracted core, quirks included, ported to C# and served as an ASP.NET Core minimal API (`POST /calculate`) that speaks the Part 4 contract. Code in `port/`, decisions in [`docs/decisions.md`](docs/decisions.md) D22.

**Run** (.NET 10 SDK, from the repository root; tested on macOS only so far):

```
dotnet run --project port/Lohnrechner.ContractTests
```

On macOS/Linux also `./port/run-port-tests.sh`. To try the API by hand: `dotnet run --project port/Lohnrechner.Api`, then `POST` a request to `http://127.0.0.1:5151/calculate`.

**What it proves:** the port behaves like the Delphi implementation on the **same, unchanged** test data. The runner reads `cases.json` and checks all 1680 cases twice, in-process and over HTTP against the API started on a free local port, plus the 8 malformed requests of the Delphi check. Responses are compared field by field (`"11134.60"` is not `"11134.6"`). Output:

```
[port core] 1680 cases, 0 failed
[port http] 1680 cases, 0 failed
[port] 8 invalid requests, 0 not rejected
RESULT: OK
```

**The lost cent needed 80-bit arithmetic.** A straightforward port with `double` failed 9 net → gross cases by one cent, among them the observed quirk 4e. Delphi Win32 calculates on the x87 FPU with 80-bit intermediates; .NET has no such type. The port emulates it exactly (`port/Lohnrechner.Core/Extended.cs`), and all 1680 pass. Deliberately replacing truncation with rounding makes 314 cases fail per run, the same count as on the Delphi side.

**Not ported:** the annual total (not part of the contract, D19) and the machine-culture parsing of `personal.dat` (quirk 9a, a step 2 problem). `run-tests.bat` doesn't run the port yet.

## What was cut or not finished

**Not done:**
- **The bonus port is not part of `run-tests.bat` yet.** It runs with its own command (see "Bonus: C# port"); the Windows script still has to get an optional step for it.
- **Part 4 steps 2 and 3** (service-safe data loading; hosting). By design: only the slice of step 1 was required.

**Cut on purpose, with the risk stated:**
- **Golden recordings for unusual input and other environments.** No recorded cases for input like `1.000`, `1E3` or more than 4 decimals, for overflow with huge amounts, or for the window under English number format or without `personal.dat`. The extraction moved the code unchanged, so I judged these not worth the time (decision D18).
- **The rule "update the total label only after a successful calculation"** is protected by a source comment, not by a test: it only makes a visible difference under English number format.
- **A demo command-line program** for the service contract (JSON in, JSON out). Nice for showing, not needed by the next steps (D21).

**Not verified:**
- **Rows 8 and 9b** of the behavior record (missing `personal.dat`, the reset text) were not checked in the running app; their expectations come from reading the code.
- **Only the Debug build is tested**, the configuration the app was observed in, not an optimized Release build.
- **No CI.** Community Edition can't compile from the command line, so tests run locally against an exe built in the IDE (`run-tests.bat` refuses a stale one).

**Size of the Part 3 skill:** about 1,030 words, short when rendered but more than one printed page. Kept as is: every part of it was used.
