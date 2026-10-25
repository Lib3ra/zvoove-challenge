# Behavior record: uMain (original app, unmodified)

Step 1 of `.claude/skills/delphi-form-extraction/SKILL.md`.

**Environment**
- Delphi 13 Community Edition (Studio 37.0), Win32. Command-line compiling refused (`dcc32` prints an error, exits 0); built from the IDE.
- Exe built into the source folder, `personal.dat` next to it.
- Regional format: German (Germany) unless a row says otherwise.

"Restart" = close and start the app again, so the running total starts at 0.
Type inputs one character at a time (as a user would) unless the row says otherwise.
**Expected** comes from reading `uMain.pas`; **Actual** is exactly what the app shows.

| # | Hypothesis | Steps | Expected | Actual |
|---|---|---|---|---|
| 1 | Every Netto calculation adds to the total, per keystroke | Restart. `1001`, class III, type `12344` into Brutto | Netto `11134,6`, total `12406,20 EUR` (1 + 12 + 123 + 1135,6 + 11134,6) | `11134,6`, `12406,20 EUR` ✔ |
| 9a | `personal.dat` parsing depends on locale | Regional format **en-US**, same steps as 1 | Allowance silently 0: Netto `11109.6`, total `12342.60 EUR` | `11109.6`, `12342.60 EUR` ✔ |
| 2a | Brutto path never adds to total | Restart. Pers.nr `1002`, class I. Type `860` into **Netto** | Brutto `1000` (or `999,99`, see 4). Total stays `0,00 EUR` | Brutto `1000`, total `0,00 EUR` ✔ |
| 6 | Field changes recalc from Brutto | Continue from 2a: switch class to III | Netto overwritten with `900` (or `899,99`). Total now `900,00` (or `899,99`) | Netto `900`, total `900,00 EUR` ✔ |
| 3 | Inverse ignores clamp at 0 | Restart. `1003`, class I. Type `100` into Netto | Brutto `-46,51` | `1` → `-161,62`, `10` → `-151,16`, `100` → `-46,51`; total `0,00 EUR` ✔ |
| 3b | Same, Netto 0 | Continue: clear Netto, type `0` | Brutto `-162,79` | Brutto `-162,79` ✔ (values while deleting not recorded) |
| 4a | Double path loses cents | `1002`, class I, Netto `86` | `100` or `99,99`? | `100` |
| 4b | | `1002`, class II, Netto `82` | `100` or `99,99`? | **`99,99`** ✔ cent lost |
| 4c | | `1002`, class III, Netto `90` | `100` or `99,99`? | `100` |
| 4d | | `1002`, class V, Netto `74` | `100` or `99,99`? | `100` |
| 4e | | `1002`, class VI, Netto `70` | `100` or `99,99`? | **`99,99`** ✔ cent lost |
| 4f | | `1002`, class I + church tax, Netto `100` | Rate 0,14 * 1,09 = 0,1526; 100 / 0,8474 = 118,008... -> `118` | `118` ✔ |
| 5a | No class selected | Restart. Pers.nr `1002`, no class. Type `5` into Brutto | Info box "Bitte zuerst eine Steuerklasse waehlen.", Netto `0`. Next keystroke: box again | Info box, Netto `0`; again on next key; total `0,00 EUR` ✔ |
| 5b | Check order | Restart, no class. Type `-5` into Brutto | `-` alone: nothing. `-5`: **class** message (not negative), Netto `0` | `-`: nothing; `-5`: class message, Netto `0` ✔ |
| 5c | Negative input | Class I. Clear Brutto, type `-5` | Warning box "Brutto darf nicht negativ sein.", Netto `0`, total unchanged | Warning already fires when class I is picked (Brutto still `-5`); Netto `0` ✔ |
| 5d | Negative Netto | Class I. Clear Netto, type `-5` | Warning "Netto darf nicht negativ sein.", Brutto `0` | `-`: nothing; `-5`: warning, Brutto `0` ✔ |
| 7a | Non-numeric pers.nr | Restart. Class III, Brutto `1000`, then pers.nr `abc` | Netto `900` (allowance 0), no message | Netto `900`, no message ✔ |
| 7b | Unknown pers.nr | Change pers.nr to `9999` | Netto `900`, no message | Netto `900`, no message ✔ |
| 7c | Pers.nr keystrokes add | Restart. Empty pers.nr, class III, Brutto `1000` (total 0,9 + 9 + 90 + 900 = `999,90`). Then type `1001` into pers.nr | `1`, `10`, `100` add 900 each, `1001` adds 925. Netto `925`, total `4624,90` | Netto `925`, total `4624,90 EUR` ✔ |
| 8 | Missing `personal.dat` | Rename `personal.dat` next to the exe, restart. `1001`, class III, Brutto `1000` | Netto `900`, no error. Rename it back | Not checked in the app (skipped); expectation from code only |
| 9b | Reset caption | Any total, click reset | `Jahressumme Netto: 0,00 EUR` (hard-coded; under en-US it would still show `0,00`) | Not checked in the app (skipped); expectation from code only |
| 10a | II and IV share a rate | `1002`, Brutto `1000`, class II, then IV | Both `820` | `820` both ✔ |
| 10b | `CurrToStr` drops trailing zero | `1002`, class III, Brutto `1001` | Netto `900,9` (not `900,90`) | `900,9` ✔ |
