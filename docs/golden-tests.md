# How the golden-file tests work

Explainer for presenting the test approach. Code: `MiniLohnrechner_Bewerberaufgabe/tests/`.

## The idea in one paragraph

Before changing any code, we pin down what the original app does. A test program opens the **real, unmodified form** without showing it, plays back user actions from text files, and compares what the form displays with what the files say it should display. The expected values come from two trusted sources: what we **saw by hand** in the running app, and what the **original code produced** when we recorded it once. After the refactoring, the same files must still pass. Expected values live in data, so refactoring can't quietly change them.

```
golden/*.txt  ──read──▶  uGoldenRunner  ──drives──▶  TForm1 (original uMain.pas)
  actions                  executes actions             OnChange / OnClick handlers
  expect lines   ◀─compare─ reads edits, label,  ◀─────  fields, total label, dialogs
                           dialog log
```

## The files

| File | Role |
|---|---|
| `GoldenTests.dpr` | Console program. No logic: lists the units and calls `RunGolden`. Includes the app's own `..\uMain.pas` and `..\uPersonalstamm.pas` by path, so the tests always compile against the current app code, never a copy. |
| `uTestSetup.pas` | Environment. **Must be the first unit**: sets the German number format and copies `personal.dat` next to the test exe. |
| `uGoldenRunner.pas` | All the logic: file parser, form driver, dialog catcher, watchdog, recorder. |
| `golden/curated.txt` | 21 hand-written cases, one per row of `docs/uMain-behavior.md`. |
| `golden/grid.golden.txt` | 1680 recorded calculation cases. |
| `golden/sequence.golden.txt` | 16 recorded event-wiring cases. |
| `run-tests.bat` / `run-tests.ps1` | The one command: find or build the exe, refuse a stale one, run, check the result. |

## A case, step by step

```
[case 6 Changing the class recalculates from gross, even after editing net]
type pers 1002
class 1
type netto 860
class 3
expect netto 900
expect total Jahressumme Netto: 900,00 EUR
```

1. `[case …]`: throw away the old form, create a fresh `TForm1`. Same as restarting the app: the total starts at 0.
2. `type pers 1002`: set the Personalnummer edit to `1`, `10`, `100`, `1002`. Each assignment fires `OnChange` once, exactly like four keystrokes.
3. `class 1`: set the combo box index and call its `Change` method. That is what the VCL does when a user picks an item, so `cbSteuerklasseChange` runs.
4. `type netto 860`: three keystrokes into Netto. The form's own handler fills Brutto (`1000`).
5. `class 3`: the handler recalculates **from Brutto** and overwrites Netto. That's quirk 6.
6. `expect …`: compare the text exactly. `900` must be `900`, the label must be the full caption.

Any mismatch prints `FAIL curated.txt:<line> [<case>] netto: expected "900", got "…"`.

## The four tricky parts

**1. Unit initialization order (`uTestSetup`).** `uPersonalstamm` reads `personal.dat` in its `initialization` section, before any test code runs, and parses it with the current number format. On an English Windows, `250,00` doesn't parse and every allowance is silently 0. Delphi runs initialization sections in `uses` order, so `uTestSetup` is listed first and sets `FormatSettings` to German before the data is loaded. A setup check then refuses to run if employee 1001 has no allowance.

**2. Simulating input without a screen.** No mouse or keyboard is involved. Setting `Edit.Text` makes the VCL fire `OnChange`, the same handler a keystroke triggers. `type` appends one character at a time to reproduce per-keystroke behavior (the annual total grows on every keystroke). `set` assigns the whole value at once, like pasting. The form's own re-entrancy guard (`FUpdating`) works as in the app, because we go through the real handlers.

**3. Modal dialogs.** `ShowMessage` and `MessageDlg` open a modal window and wait for OK, which would block the test forever. A `TTimer` solves it: timers only fire while messages are being processed, and during a calculation that only happens inside the dialog's own wait loop. The timer finds the open message form, logs its kind and text (e.g. `warning Brutto darf nicht negativ sein.`), and closes it. The kind is read from the caption: `Warning` means a warning, the application title means `ShowMessage`. `UseLatestCommonDialogs := False` makes Delphi use its own message form instead of a Windows task dialog, which the timer could not see.

**4. Hangs.** If code ever showed a dialog the timer doesn't recognize, the test would wait forever. A watchdog thread checks every half second; if one step runs longer than 10 seconds, it prints the file and line, `RESULT: FAILED`, and ends the process. Side effect: pausing at a breakpoint for more than 10 seconds while debugging the tests ends the process too.

## Where the expected values come from

| File | Source | Why trust it |
|---|---|---|
| `curated.txt` | Observed by hand in the running app (except 9b, from the code) | A person saw these values on screen; no program and no AI computed them |
| `grid.golden.txt` | `GoldenTests record` on the original code | It's the original's own output, recorded before any change |
| `sequence.golden.txt` | same | same |

The curated cases were written **independently** of the recording and passed on the first run. That shows the runner reproduces what a user sees.

**The rule:** recorded files are only ever recorded from the unmodified original, in their own commits. After the refactoring they are never re-recorded. If a refactoring PR changes a golden file, behavior changed. The skill states this rule because "just re-record it" is exactly the shortcut that would hide a regression.

## Record vs. verify

- `GoldenTests` (no argument): **verify.** Runs every `golden/*.txt` and prints the failures, then `N cases in M files, F failed, E file errors` and `RESULT: OK` or `RESULT: FAILED`.
- `GoldenTests record`: **record.** Generates the grid and sequence inputs, plays them on the current code, and writes each step plus `expect` lines for what the form showed.

The grid tests the **calculation**: each case sets employee number, class, church tax and one amount, then checks the result. The sequence file tests the **wiring**: it types an amount key by key, then changes every other control in turn (church tax on and off, class, employee number, reset, clearing the field) and checks after each step. The independent review found the wiring gap: church tax was always ticked *before* an amount was entered, so its recalculation never ran in any test.

## Guards against a false green

A test suite that passes for the wrong reason is worse than none. Guards:

- **Exact text comparison**, including the full total caption and dialog kind and text.
- **Unchecked dialogs fail the case**, so an extra or missing message is caught.
- **Case counts:** each golden file declares `# cases: N`. A truncated file fails, and a missing required file fails.
- **Watchdog** for hangs.
- **Stale exe refused:** Community Edition can't build from the command line, so the script uses the exe built in the IDE. If any source is newer than that exe, the script stops instead of testing old code.
- **Result check:** the script needs exit code 0 **and** the line `RESULT: OK`, because `dcc32` in Community Edition exits 0 even when it refuses to compile.
- **It can fail:** deliberately changing one expected value turned the run red with exit code 1.

## Limits (say these out loud)

- **Not tested:** a missing `personal.dat` and a non-German regional format. The data is loaded once per process with the pinned format. Both are documented in the behavior record. The core's side of "no data" (allowance 0) is covered by a core unit test; the file loading itself and the English-format display are not.
- Typing only appends or removes at the end of a field. Editing in the middle, selection and focus are not simulated.
- Nothing visual: layout, icons, button captions.
- Win32 only, like the app. Whether Win64 gives different cents was not checked.

## Two drivers: with and without the window

After the extraction the runner has two "drivers" behind the same file reader:

- **`TFormDriver`** (default mode): the real window, as described above. Runs all three golden files.
- **`TCoreDriver`** (`GoldenTests core`): no window at all. It holds the field texts as plain strings and calls `TLohnrechner` directly through a small adapter: parse the text, call the core with all inputs, format the result, turn an error kind into `message`/`warning`. That is exactly what any other caller would do. It runs only `grid.golden.txt` (the calculation cases, entered with `set`); typing and field-change wiring only exist in the window.

Both must reproduce the original results. Core mode also runs 11 unit tests (`uCoreTests.pas`) for what the window can't reach, such as a missing data file (lookup returns 0) and the annual total as a number.

A future web API would get a third driver of the same shape: map `set brutto 1000` to a request, map error kinds to HTTP errors, compare numbers instead of German text.

## Proven after the extraction

- Same golden files, unchanged: 1717 window cases green; 1680 core cases + 11 unit tests green.
- Deliberate break: `Round` instead of `Trunc` in the core's net → gross ("fixing" the lost cent). 320 window cases, 314 core cases and 1 unit test failed. Reverted.
- Watchdog: `GoldenTests selftest-watchdog` opens a Windows message box the runner can't close; the watchdog ended the process after 10.2 s with exit code 1.

## Where to see the output

`run-tests.bat` prints everything to the console it runs in: open PowerShell in the repository folder and run `.\run-tests.bat`. Starting `GoldenTests` from the IDE opens a console window that closes as soon as the run ends.

## Likely questions

- **Why not DUnitX?** It's only installed for Win64 here, and the app is Win32. Golden files only need "replay and compare", which takes about 600 lines of plain Delphi that can be explained line by line.
- **Why drive the form instead of testing functions?** Before the extraction, the logic is inside the form, with dialogs and event wiring mixed in. Driving the form is the only way to pin the original without changing it first.
- **Could the AI have made up the expected values?** The curated values came from you, by hand. The recorded ones came from running the original. The AI wrote the runner and the inputs, not the outputs.
- **What if the original behavior is wrong?** That's intended. The task says to keep quirks and bugs, so the tests pin them, and source comments will mark each one.
