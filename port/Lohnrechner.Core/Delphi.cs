using System.Numerics;

namespace Lohnrechner.Core;

// The Delphi Win32 arithmetic steps the core relies on, in one place so each can be checked
// against what the compiler does (docs/port-csharp-brief.md, "Delphi semantics"). Floating
// point goes through Extended (x87, 80 bit), not double: see Extended.cs. cases.json is the
// judge of this model.
internal static class Delphi
{
    private const decimal CurrencyScale = 10_000m;

    // The literal 0.09 in Delphi source is an Extended constant, not a double
    public static readonly Extended Literal009 = Extended.AusBruch(9, 100);

    public static Extended Ext(double wert) => Extended.AusDouble(wert);
    public static Extended Ext(decimal currency) => Extended.AusCurrency(currency);
    public static Extended Ext(int wert) => Extended.AusBruch(wert, 1);

    // Currency := Currency * <float>. The FPU multiplies the scaled 64-bit integer (exact) and
    // stores the product as an integer, rounded half to even: 4 decimals.
    public static decimal CurrencyMal(decimal currency, Extended faktor)
    {
        Extended skaliert = Extended.AusBruch(new BigInteger(currency * CurrencyScale), 1) * faktor;
        return (decimal)skaliert.RundeGanzzahl() / CurrencyScale;
    }

    // Currency := Trunc(x) / 100: x cut toward zero, then two decimals
    public static decimal TruncDurch100(Extended x)
    {
        decimal betrag = (decimal)x.Abschneiden() / 100;
        // Currency has no negative zero; decimal does, and it would format as "-0.00"
        return betrag == 0 ? 0m : betrag;
    }
}
