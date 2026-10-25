namespace Lohnrechner.Core;

// The Delphi arithmetic steps the core relies on, in one place so each can be checked
// against what the Win32 compiler does (docs/port-csharp-brief.md, "Delphi semantics").
internal static class Delphi
{
    private const decimal CurrencyScale = 10_000m;

    // Currency := Currency * Double. Delphi multiplies the scaled 64-bit integer by the double
    // on the FPU and stores the product rounded to an integer (round half to even), i.e. to
    // 4 decimals.
    public static decimal CurrencyMalDouble(decimal currency, double faktor)
    {
        double skaliert = (double)(long)(currency * CurrencyScale) * faktor;
        return (decimal)Math.Round(skaliert, MidpointRounding.ToEven) / CurrencyScale;
    }

    // Trunc(x) / 100 into a Currency: cut x toward zero, then two decimals
    public static decimal TruncDurch100(double x)
    {
        decimal betrag = (decimal)Math.Truncate(x) / 100;
        // Currency has no negative zero; decimal does, and it would format as "-0.00"
        return betrag == 0 ? 0m : betrag;
    }
}
