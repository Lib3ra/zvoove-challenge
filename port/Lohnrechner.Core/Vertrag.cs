using System.Globalization;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Lohnrechner.Core;

// Port of uLohnrechnerVertrag.pas: the service contract for one payroll calculation
// (docs/service-contract.md). A thin wrapper around the core: it validates and translates a
// request, calls the core, and translates the result. No business logic here.
//
//   Request  {"direction":"grossToNet"|"netToGross","employeeNumber":1001,
//             "taxClass":3,"churchTax":false,"amount":"12344.00"}
//   Response {"amount":"11134.60"}
//         or {"error":"NO_TAX_CLASS","message":"Bitte zuerst eine Steuerklasse waehlen."}

public enum Richtung { BruttoZuNetto, NettoZuBrutto }

public readonly record struct BerechnungsAnfrage(
    Richtung Richtung, int Personalnummer, int Steuerklasse, bool Kirchensteuer, decimal Betrag);

// Betrag only meaningful when Fehlercode == "" (success)
public readonly record struct BerechnungsAntwort(decimal Betrag, string Fehlercode, string Meldung);

public static partial class Vertrag
{
    public const string FehlercodeUngueltig = "INVALID_REQUEST";

    // Delphi Currency range
    private const decimal CurrencyMax = 922_337_203_685_477.5807m;

    // Escapes like Delphi's ToJSON (\" rather than "); all texts here are ASCII
    private static readonly JsonWriterOptions WriterOptions = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    // \z rather than $: in .NET, $ also matches before a trailing newline
    [GeneratedRegex(@"^-?[0-9]+(\.[0-9]{1,4})?\z")]
    private static partial Regex BetragFormat();

    public static string Fehlercode(LohnFehler fehler) => fehler switch
    {
        LohnFehler.KeineSteuerklasse => "NO_TAX_CLASS",
        LohnFehler.BruttoNegativ => "NEGATIVE_GROSS",
        LohnFehler.NettoNegativ => "NEGATIVE_NET",
        _ => "",
    };

    // The contract: JSON request in, JSON response out
    public static string BerechneJson(string anfrageJson, Func<int, decimal> holeFreibetrag) =>
        AntwortAlsJson(BerechneAusJson(anfrageJson, holeFreibetrag));

    // Same, but the response as a record, so a transport layer can pick e.g. an HTTP status
    public static BerechnungsAntwort BerechneAusJson(string anfrageJson, Func<int, decimal> holeFreibetrag)
    {
        if (AnfrageAusJson(anfrageJson, out BerechnungsAnfrage anfrage, out string fehler))
            return Berechne(anfrage, holeFreibetrag);
        // Contract-level input check, not original behavior: the window never sees invalid JSON
        return new BerechnungsAntwort(0, FehlercodeUngueltig, fehler);
    }

    // One calculation through the core, without JSON
    public static BerechnungsAntwort Berechne(BerechnungsAnfrage anfrage, Func<int, decimal> holeFreibetrag)
    {
        // A fresh core per call: nothing is remembered between requests
        var rechner = new Lohnrechner(holeFreibetrag);
        LohnErgebnis ergebnis = anfrage.Richtung == Richtung.BruttoZuNetto
            ? rechner.BerechneNetto(anfrage.Betrag, anfrage.Personalnummer, anfrage.Steuerklasse, anfrage.Kirchensteuer)
            : rechner.BerechneBrutto(anfrage.Betrag, anfrage.Personalnummer, anfrage.Steuerklasse, anfrage.Kirchensteuer);
        return new BerechnungsAntwort(ergebnis.Betrag, Fehlercode(ergebnis.Fehler), Lohnrechner.FehlerText(ergebnis.Fehler));
    }

    // Every field's JSON kind is checked by hand. Deliberately no model binding: it would coerce
    // "1001" into 1001 and accept requests the contract rejects.
    public static bool AnfrageAusJson(string json, out BerechnungsAnfrage anfrage, out string fehler)
    {
        anfrage = default;
        fehler = "";
        JsonDocument dokument;
        try
        {
            dokument = JsonDocument.Parse(json);
        }
        catch (JsonException)
        {
            fehler = "request must be a JSON object";
            return false;
        }
        using (dokument)
        {
            JsonElement objekt = dokument.RootElement;
            if (objekt.ValueKind != JsonValueKind.Object)
            {
                fehler = "request must be a JSON object";
                return false;
            }

            Richtung richtung;
            string? direction = IstText(objekt, "direction", out JsonElement directionFeld) ? directionFeld.GetString() : null;
            if (direction == "grossToNet")
                richtung = Richtung.BruttoZuNetto;
            else if (direction == "netToGross")
                richtung = Richtung.NettoZuBrutto;
            else
            {
                fehler = "direction must be \"grossToNet\" or \"netToGross\"";
                return false;
            }

            if (!TryGanzzahl(objekt, "employeeNumber", out int personalnummer))
            {
                fehler = "employeeNumber must be an integer";
                return false;
            }

            if (!TryGanzzahl(objekt, "taxClass", out int steuerklasse))
            {
                fehler = "taxClass must be an integer (0 = none chosen)";
                return false;
            }

            if (!TryFeld(objekt, "churchTax", out JsonElement churchTax)
                || churchTax.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            {
                fehler = "churchTax must be true or false";
                return false;
            }

            if (!IstText(objekt, "amount", out JsonElement amount) || !TextAlsBetrag(amount.GetString()!, out decimal betrag))
            {
                fehler = "amount must be a decimal string like \"1234.56\" (dot, up to 4 decimals)";
                return false;
            }

            anfrage = new BerechnungsAnfrage(richtung, personalnummer, steuerklasse,
                churchTax.ValueKind == JsonValueKind.True, betrag);
            return true;
        }
    }

    public static string AntwortAlsJson(BerechnungsAntwort antwort)
    {
        using var puffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(puffer, WriterOptions))
        {
            writer.WriteStartObject();
            if (antwort.Fehlercode == "")
                writer.WriteString("amount", BetragAlsText(antwort.Betrag));
            else
            {
                writer.WriteString("error", antwort.Fehlercode);
                writer.WriteString("message", antwort.Meldung);
            }
            writer.WriteEndObject();
        }
        return System.Text.Encoding.UTF8.GetString(puffer.ToArray());
    }

    // "1234.56": dot, at least 2 and at most 4 decimals, no thousands separator
    public static string BetragAlsText(decimal betrag) =>
        Math.Round(betrag, 4, MidpointRounding.ToEven).ToString("0.00##", CultureInfo.InvariantCulture);

    public static bool TextAlsBetrag(string text, out decimal betrag)
    {
        betrag = 0;
        return BetragFormat().IsMatch(text)
            && decimal.TryParse(text, NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint,
                CultureInfo.InvariantCulture, out betrag)
            && Math.Abs(betrag) <= CurrencyMax;
    }

    // The first field with this name, like Delphi's TJSONObject.Values (TryGetProperty takes the last)
    private static bool TryFeld(JsonElement objekt, string name, out JsonElement feld)
    {
        foreach (JsonProperty eigenschaft in objekt.EnumerateObject())
            if (eigenschaft.NameEquals(name))
            {
                feld = eigenschaft.Value;
                return true;
            }
        feld = default;
        return false;
    }

    // A JSON string; a number is not a string (Delphi: TJSONNumber derives from TJSONString)
    private static bool IstText(JsonElement objekt, string name, out JsonElement feld) =>
        TryFeld(objekt, name, out feld) && feld.ValueKind == JsonValueKind.String;

    // A JSON number written as an integer that fits Int32, like Delphi's TryStrToInt on its text:
    // 1001.0 and 1e3 are not integers
    private static bool TryGanzzahl(JsonElement objekt, string name, out int wert)
    {
        wert = 0;
        return TryFeld(objekt, name, out JsonElement feld)
            && feld.ValueKind == JsonValueKind.Number
            && int.TryParse(feld.GetRawText(), NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out wert);
    }
}
