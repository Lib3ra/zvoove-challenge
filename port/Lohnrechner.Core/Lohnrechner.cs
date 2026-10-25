namespace Lohnrechner.Core;

// Port of uLohnrechnerCore.pas (Delphi), line by line: same order of checks, same
// Currency/Double mix, same Trunc rounding. Existing quirks are kept on purpose and marked
// "QUIRK (deliberately not fixed)" at the same places as in the Delphi unit, with the row of
// docs/uMain-behavior.md where they were observed. Port decisions: docs/decisions.md D22.
//
// Delphi Currency (64-bit integer scaled by 10,000) is held as decimal with at most 4 decimals,
// floating point as Extended (Extended.cs), like the Win32 compiler does.
// Not ported: the annual total. It is a window session counter, not part of the service
// contract (docs/decisions.md D19), and the Delphi window keeps using the Delphi core.

public enum LohnFehler { Keiner, KeineSteuerklasse, BruttoNegativ, NettoNegativ }

// Betrag is 0 when Fehler != Keiner
public readonly record struct LohnErgebnis(decimal Betrag, LohnFehler Fehler);

public sealed class Lohnrechner
{
    // Fiktive, frei erfundene Saetze - keine reale Rechtsgrundlage.
    // QUIRK (deliberately not fixed): classes II and IV share the rate 0.18 - see docs/uMain-behavior.md #10a
    private static readonly double[] SteuersatzFuerKlasse = [0.14, 0.18, 0.10, 0.18, 0.26, 0.30];

    private readonly Func<int, decimal> _holeFreibetrag;

    // holeFreibetrag: allowance (Freibetrag) for an employee number
    public Lohnrechner(Func<int, decimal> holeFreibetrag)
    {
        _holeFreibetrag = holeFreibetrag;
    }

    // The original message texts, so every caller shows the same wording
    public static string FehlerText(LohnFehler fehler) => fehler switch
    {
        LohnFehler.KeineSteuerklasse => "Bitte zuerst eine Steuerklasse waehlen.",
        LohnFehler.BruttoNegativ => "Brutto darf nicht negativ sein.",
        LohnFehler.NettoNegativ => "Netto darf nicht negativ sein.",
        _ => "",
    };

    public static double Steuersatz(int klasse)
    {
        // QUIRK (deliberately not fixed): a class outside 1..6 (e.g. 7 or -1) is not an error, it is
        // taxed at rate 0. From the code, not observable in the window - pinned by the Delphi core
        // unit test ClassOutOfRangeIsTaxFree
        if (klasse < 1 || klasse > 6)
            return 0;
        return SteuersatzFuerKlasse[klasse - 1];
    }

    // steuerklasse: 1..6, 0 = none chosen
    public LohnErgebnis BerechneNetto(decimal brutto, int personalnummer, int steuerklasse, bool kirchensteuer)
    {
        // QUIRK (deliberately not fixed): the tax class is checked before the sign, so a negative
        // amount without a class reports the missing class - see docs/uMain-behavior.md #5b
        // Errors return 0 - see #5a, #5c
        if (steuerklasse == 0)
            return new LohnErgebnis(0, LohnFehler.KeineSteuerklasse);
        if (brutto < 0)
            return new LohnErgebnis(0, LohnFehler.BruttoNegativ);

        // QUIRK (deliberately not fixed): unknown employee numbers silently get allowance 0 - see #7b
        decimal freibetrag = _holeFreibetrag(personalnummer);
        decimal bemessungsgrundlage = brutto - freibetrag;
        if (bemessungsgrundlage < 0)
            bemessungsgrundlage = 0;

        decimal steuer = Delphi.CurrencyMal(bemessungsgrundlage, Delphi.Ext(Steuersatz(steuerklasse)));
        decimal kiSt;
        if (kirchensteuer)
            kiSt = Delphi.CurrencyMal(steuer, Delphi.Literal009);
        else
            kiSt = 0;

        // QUIRK (deliberately not fixed): Trunc cuts off the third decimal instead of rounding;
        // Steuer and KiSt are Currency, so Currency * Double is rounded to 4 decimals first. From the
        // code; the net path has no behavior-record row, it is pinned by grid.golden.txt
        // Currency arithmetic is exact, so decimal gives the same digits as the FPU here
        decimal betrag = Math.Truncate((brutto - steuer - kiSt) * 100) / 100;

        // QUIRK (deliberately not fixed), Delphi only: every successful net calculation adds to the
        // annual total - see #1, #6, #7c. Not ported (see top of file)
        return new LohnErgebnis(betrag, LohnFehler.Keiner);
    }

    public LohnErgebnis BerechneBrutto(decimal netto, int personalnummer, int steuerklasse, bool kirchensteuer)
    {
        // QUIRK (deliberately not fixed): same check order as BerechneNetto, class before sign - see
        // grid.golden.txt case g0348 (no class, Netto -1: class message); #5d covers the sign check
        if (steuerklasse == 0)
            return new LohnErgebnis(0, LohnFehler.KeineSteuerklasse);
        if (netto < 0)
            return new LohnErgebnis(0, LohnFehler.NettoNegativ);

        double rate = Steuersatz(steuerklasse);
        if (kirchensteuer)
            // Computed in Extended, stored back into a Double
            rate = (Delphi.Ext(rate) + Delphi.Ext(rate) * Delphi.Literal009).AlsDouble();
        decimal freibetrag = _holeFreibetrag(personalnummer);

        // QUIRK (deliberately not fixed): the inverse formula ignores the clamp of the taxable base
        // at 0, so a net below the allowance gives a wrong, even negative gross - see #3, #3b
        // QUIRK (deliberately not fixed): computed in floating point and truncated, so some results
        // lose a cent and net -> gross -> net does not round-trip - see #4b, #4e
        // The whole expression is Extended in Delphi Win32; in double, 9 cases of cases.json get a
        // different cent, among them #4e (docs/decisions.md D22)
        Extended r = Delphi.Ext(rate);
        Extended brutto = (Delphi.Ext(netto) - r * Delphi.Ext(freibetrag)) / (Delphi.Ext(1) - r);
        decimal betrag = Delphi.TruncDurch100(brutto * Delphi.Ext(100));

        // QUIRK (deliberately not fixed): the gross calculation never adds to the annual total - see #2a
        return new LohnErgebnis(betrag, LohnFehler.Keiner);
    }
}
