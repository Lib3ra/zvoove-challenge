# Case Study: Mini Payroll Calculator

## Welcome

Thank you for taking the time. This case study mirrors real work on our team: taking an existing Delphi application where UI and business logic are tangled together, making the logic reusable, and leaving the codebase **and the way we work** better than you found it.

We are looking for engineers with an **AI-first mindset**: you use AI tools as a normal part of development, you verify what they produce, and you think about how to improve the system and the team's workflow, and then you act on it rather than just talking about it.

## Ground rules

- **Time:** plan for about 4 hours (please do not spend more than 6). Work through the parts in order. If you run out of time, stop and tell us what you cut. A smaller, well-verified result beats a large unverified one.
- **AI tools are expected.** Use Claude Code, Copilot, ChatGPT or anything else you like. We are interested in how you steer the tools and how you check their output.
- **Toolchain:** Delphi. See the section 'Delphi setup' below. Installing it is recommended but not required.
- **The tax rates are fictional.** This is not about German tax law. It is only about code structure, behavior and workflow.
- **Questions are welcome.**

## Delphi setup

The starter application is written in Delphi (VCL, Windows). The best way to work on it is to build and run it yourself.

- **Free option:** Embarcadero offers a free Delphi Community Edition. Register and download it here: <https://www.embarcadero.com/products/delphi/starter/free-download>. More information: <https://www.embarcadero.com/products/delphi/starter>
- **How it works:** you register, receive a license key by email, and install with the web installer. It runs on Windows only. Please plan about one extra hour for this, on top of the time box.
- **License terms:** the Community Edition is intended for individuals, students, startups and non-profits below a revenue limit, and the license is valid for one year. Please read the terms yourself and make sure you are allowed to use it. We cannot give you legal advice on this.
- **If you cannot or prefer not to install Delphi:** that is fine. Submit the source code and we will build and run it on our side. Tell us in your README that you did not compile it. Small compile errors will not count against you, as long as the design and the tests make sense.

## Starting point

The folder `MiniLohnrechner_Bewerberaufgabe` contains a small Delphi VCL application. It calculates net pay from gross pay (and the reverse). It consists of the form `uMain`, the unit `uPersonalstamm` with a data file `personal.dat`, and the project files.

This is how many of our existing applications look: UI and business logic live in the same form.

## Glossary (German terms in the starter code)

The starter code uses German names, comments and UI texts. You are free to write your own code, comments and tests in English. These are the terms you will meet:

| German | English | Where you will see it |
|---|---|---|
| Bewerberaufgabe | candidate task | folder name |
| Lohnrechner | pay calculator | project and folder name |
| Brutto | gross pay | `BerechneNetto`, `editBrutto` |
| Netto | net pay | `BerechneNetto`, `editNetto` |
| Berechne... | calculate... | `BerechneNetto` = calculate net, `BerechneBrutto` = calculate gross |
| Steuerklasse | tax class (1 to 6, 0 = none chosen) | `FSteuerklasse`, `cbSteuerklasse` |
| Steuersatz | tax rate | `Steuersatz`, `SteuersatzFuerKlasse` |
| Kirchensteuer | church tax (a surcharge on the tax) | `FKirchensteuer`, `KiSt` |
| Freibetrag | allowance (amount that is not taxed) | `HoleFreibetrag` = get allowance, `personal.dat` |
| Bemessungsgrundlage | taxable base (gross minus allowance) | local variable in `BerechneNetto` |
| Personalnummer | employee (personnel) number | `FPersonalnummer`, `editPersonalnummer` |
| Personalstamm | personnel master data | unit `uPersonalstamm`, global `Personalstamm` |
| Jahressumme / Gesamtsumme | annual total / grand total (of net pay) | `FGesamtsummeNetto`, `lblJahressumme` |
| Hinweis | note | `lblHinweis` |

UI messages in the code, in English:

- 'Bitte zuerst eine Steuerklasse waehlen.' = Please choose a tax class first.
- 'Brutto darf nicht negativ sein.' = Gross must not be negative.
- 'Netto darf nicht negativ sein.' = Net must not be negative.
- 'Fiktive, frei erfundene Saetze' = fictional, invented rates.

## Part 1 - Separate business logic from UI (required)

In the medium term we want to connect a web UI to places like this without touching the business logic again. For now the application stays completely in Delphi. A web UI is **not** part of this task.

**Task:** separate business logic and UI so that another caller (for example a web UI) could be connected later without changing the business logic. How you design this (interfaces, structure, naming) is up to you. There is no prescribed pattern.

- The Delphi application must **remain complete and runnable**: it starts as a Windows application, is usable, and the form no longer contains business logic.
- **Goal is not to improve the application.** If you find quirks, inconsistencies or bugs in the existing behavior, **preserve them** and document them **as a comment in the source code** at the relevant place (for example 'deliberately not fixed, see task description'). Do not fix them silently.

## Part 2 - Prove that behavior is unchanged (required)

How do you know your refactoring did not change anything? Show it.

- Write automated tests that capture the behavior of the extracted logic. At minimum: a success case, the error cases, and the edge cases you discovered.
- The tests must run with **one command or script** that we can run too.
- Your tests should be able to catch a change in behavior, not just confirm that the code compiles.

## Part 3 - Make it repeatable (required, keep it small)

Other forms in our codebase look just like this one. Create **one small artifact** that helps a colleague (with or without AI) repeat what you just did faster and with fewer mistakes.

Examples (choose one or invent your own):

- an `AGENTS.md` / `CLAUDE.md`, skill or prompt set with the rules and pitfalls for this kind of extraction
- a script or check that flags typical coupling (UI calls in logic, global state, hidden dependencies)
- a reusable test template or checklist

It must be something you **actually used** in Parts 1 and 2, not something written afterwards in theory. Maximum: about one page or a few small files.

## Part 4 - Next steps (required, keep it small)

We want to move from this intermediate step towards a standalone service. The target architecture is **not decided** yet, so do not guess it. State your assumptions instead.

1. Write down the **three most important next steps**, ranked, with one or two sentences on why in this order.
2. **Implement the smallest meaningful slice of step 1.** It must run and be tested. We do not want a design essay.

## Bonus (optional) - 1:1 port

Port the extracted core logic to a language of your choice (for example C#, TypeScript, Java, Python, Go), **including the deliberately preserved quirks**. The core class alone is enough. If you do this, run the **same test cases** (a shared data file of inputs and expected outputs) against both implementations.

## What to submit

1. The runnable Delphi application (UI, your separation, the extracted core logic) and your tests.
2. The Part 3 artifact and the code of your Part 4 slice.
3. Optional: the port.
4. A short `README` (bullet points are fine) answering:
   - What did you separate, what did you not separate, and why?
   - How did you use AI tools? Include 2 or 3 key prompts or an excerpt of your session, one place where the AI was wrong or incomplete and how you noticed, and what you would never let AI do unchecked.
   - How do we run the tests, and what do they prove?
   - Where is your Part 3 artifact and how is it used?
   - Your ranked next steps (Part 4) and which slice you built.
   - What did you cut or not finish?

Quirks and bugs of the existing behavior belong **in the code as comments** (see Part 1), not in the README.

## How we will look at it

There is no single correct architecture. We look at:

- whether the behavior is preserved and whether you can **prove** it
- whether there is a clear, sensible boundary between logic and UI
- how you use AI: what it did, what you checked, and what you decided yourself
- whether you leave behind something the team can reuse (Part 3)
- your judgment and prioritization on next steps (Part 4)

## What happens next

We will invite you to a conversation of about 60 minutes. You will walk us through your submission and we will work on a small follow-up task together. You should be able to explain every line you submit, whether you or an AI wrote it.

Good luck, and enjoy it!
