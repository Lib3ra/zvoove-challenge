using System.Globalization;

namespace Lohnrechner.Core;

// Port of uPersonalstamm.pas: allowances (Freibetraege) per employee number from personal.dat,
// lines "employeeNumber;amount" with a German decimal comma ("1001;250,00").
public sealed class Personalstamm
{
    private readonly Dictionary<int, decimal> _freibetraege = new();

    private Personalstamm() { }

    public static Personalstamm Laden(string pfad)
    {
        var stamm = new Personalstamm();
        // QUIRK (deliberately not fixed): a missing file is ignored silently, every allowance
        // is then 0 - see docs/uMain-behavior.md #8
        if (!File.Exists(pfad))
            return stamm;
        // ReadAllLines accepts \r\n and \n
        foreach (string zeile in File.ReadAllLines(pfad))
        {
            string[] teile = zeile.Split(';');
            // Lines that don't parse are skipped silently, like the original. Unlike the original,
            // the comma is parsed explicitly and not with the machine's number format: that
            // locale dependence (#9a) is Part 4 step 2, not something to port (docs/decisions.md D22)
            if (teile.Length == 2
                && int.TryParse(teile[0], NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out int persNr)
                && TryParseDeutsch(teile[1], out decimal freibetrag))
                stamm._freibetraege[persNr] = freibetrag;
        }
        return stamm;
    }

    // QUIRK (deliberately not fixed): unknown employee numbers get 0 without any message - see #7b
    public decimal HoleFreibetrag(int personalnummer) =>
        _freibetraege.TryGetValue(personalnummer, out decimal freibetrag) ? freibetrag : 0;

    // "250,00" -> 250.00, no thousands separators; stored like a Currency, rounded to 4 decimals
    private static bool TryParseDeutsch(string text, out decimal betrag)
    {
        bool ok = decimal.TryParse(text.Replace(',', '.'), NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint,
            CultureInfo.InvariantCulture, out betrag);
        betrag = Math.Round(betrag, 4, MidpointRounding.ToEven);
        return ok;
    }
}
