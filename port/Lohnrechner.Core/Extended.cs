using System.Numerics;

namespace Lohnrechner.Core;

// Delphi's Extended as the Win32 compiler uses it: the x87 FPU's 80-bit format with a 64-bit
// mantissa, round half to even after every operation. .NET has no such type and calculates in
// 64-bit double on every platform, which gives a different last cent for some net -> gross
// cases (docs/decisions.md D22).
//
// Value = Mantisse * 2^Exponent, |Mantisse| < 2^64. Each operation is done exactly with
// BigInteger and then rounded once, which is what the FPU does. Only what the core needs:
// no infinities, NaN or denormals; the amounts here are far from those ranges.
internal readonly struct Extended
{
    private const int MantissenBits = 64;
    private const int DoubleBits = 53;

    private readonly BigInteger _mantisse;
    private readonly int _exponent;

    private Extended(BigInteger mantisse, int exponent)
    {
        _mantisse = mantisse;
        _exponent = exponent;
    }

    // A double fits into Extended exactly
    public static Extended AusDouble(double wert)
    {
        if (wert == 0)
            return default;
        long bits = BitConverter.DoubleToInt64Bits(wert);
        int rohExponent = (int)((bits >> 52) & 0x7FF);
        long mantisse = bits & 0xF_FFFF_FFFF_FFFFL;
        if (rohExponent == 0)
            rohExponent = 1;              // denormal
        else
            mantisse |= 1L << 52;         // hidden bit
        BigInteger m = wert < 0 ? -mantisse : mantisse;
        return new Extended(m, rohExponent - 1075);
    }

    // A Currency loaded onto the FPU: the scaled integer (exact), divided by 10,000 (rounded)
    public static Extended AusCurrency(decimal wert) =>
        AusBruch(new BigInteger(wert * 10_000m), 10_000);

    // A decimal literal in Delphi source, e.g. 0.09: the nearest Extended
    public static Extended AusBruch(BigInteger zaehler, BigInteger nenner) =>
        Runde(zaehler, nenner, MantissenBits);

    public static Extended operator +(Extended a, Extended b)
    {
        int e = Math.Min(a._exponent, b._exponent);
        BigInteger summe = (a._mantisse << (a._exponent - e)) + (b._mantisse << (b._exponent - e));
        return AusExakt(summe, e);
    }

    public static Extended operator -(Extended a, Extended b) => a + new Extended(-b._mantisse, b._exponent);

    public static Extended operator *(Extended a, Extended b) =>
        AusExakt(a._mantisse * b._mantisse, a._exponent + b._exponent);

    public static Extended operator /(Extended a, Extended b)
    {
        if (b._mantisse.IsZero)
            throw new DivideByZeroException();
        // a / b = (ma / mb) * 2^(ea - eb)
        var (zaehler, nenner) = (a._mantisse, b._mantisse);
        int e = a._exponent - b._exponent;
        if (e >= 0)
            zaehler <<= e;
        else
            nenner <<= -e;
        return Runde(zaehler, nenner, MantissenBits);
    }

    // Stored into a Double variable: rounded to 53 bits
    public double AlsDouble()
    {
        var (zaehler, nenner) = AlsBruch();
        Extended d = Runde(zaehler, nenner, DoubleBits);
        return Math.ScaleB((double)d._mantisse, d._exponent);
    }

    // Trunc: cut toward zero
    public BigInteger Abschneiden()
    {
        var (zaehler, nenner) = AlsBruch();
        return BigInteger.Divide(zaehler, nenner);
    }

    // Stored into an integer (FISTP with the default control word): round half to even
    public BigInteger RundeGanzzahl()
    {
        var (zaehler, nenner) = AlsBruch();
        BigInteger q = BigInteger.DivRem(BigInteger.Abs(zaehler), nenner, out BigInteger rest);
        int vergleich = (rest * 2).CompareTo(nenner);
        if (vergleich > 0 || (vergleich == 0 && !q.IsEven))
            q += 1;
        return zaehler.Sign < 0 ? -q : q;
    }

    private (BigInteger Zaehler, BigInteger Nenner) AlsBruch() =>
        _exponent >= 0 ? (_mantisse << _exponent, BigInteger.One) : (_mantisse, BigInteger.One << -_exponent);

    private static Extended AusExakt(BigInteger mantisse, int exponent) =>
        exponent >= 0
            ? Runde(mantisse << exponent, BigInteger.One, MantissenBits)
            : Runde(mantisse, BigInteger.One << -exponent, MantissenBits);

    // zaehler / nenner (nenner > 0), rounded to `bits` significant bits, round half to even
    private static Extended Runde(BigInteger zaehler, BigInteger nenner, int bits)
    {
        if (zaehler.IsZero)
            return default;
        BigInteger a = BigInteger.Abs(zaehler);
        // Choose s so that 2^(bits-1) <= a * 2^s / nenner < 2^bits
        int s = bits - (int)(a.GetBitLength() - nenner.GetBitLength());
        BigInteger untere = BigInteger.One << (bits - 1);
        BigInteger obere = BigInteger.One << bits;
        BigInteger q, rest, n;
        while (true)
        {
            BigInteger z = s >= 0 ? a << s : a;
            n = s >= 0 ? nenner : nenner << -s;
            q = BigInteger.DivRem(z, n, out rest);
            if (q >= obere)
                s--;
            else if (q < untere)
                s++;
            else
                break;
        }
        int vergleich = (rest * 2).CompareTo(n);
        if (vergleich > 0 || (vergleich == 0 && !q.IsEven))
            q += 1;
        if (q == obere)
        {
            q >>= 1;
            s--;
        }
        return new Extended(zaehler.Sign < 0 ? -q : q, -s);
    }
}
