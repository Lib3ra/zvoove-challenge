// Checks the C# port against the shared contract test data, the same file the Delphi
// implementation passes (tests/golden/contract/cases.json, docs/service-contract.md):
//   1. every case through the contract layer in-process   [port core]
//   2. every case over HTTP against the API, started here on 127.0.0.1 and a free port   [port http]
//   3. the eight malformed requests of the Delphi check, both ways   [port]
// Responses are compared by content: same field names in the same order, same string values.
// Over HTTP the status code must also match the response (docs/decisions.md D22).
// Prints RESULT: OK / RESULT: FAILED; exit code 0 / 1, 2 if the data can't be found.
// Optional argument: the repository root (default: found by walking up from the executable).

using System.Text;
using System.Text.Json;
using Lohnrechner.Api;
using Lohnrechner.Core;
using Microsoft.AspNetCore.Builder;

const int MaxGezeigt = 20;

string? repo = args.Length > 0 ? Path.GetFullPath(args[0]) : LohnrechnerApi.FindeRepo(AppContext.BaseDirectory);
if (repo == null)
{
    Console.WriteLine($"ERROR: repository folder {LohnrechnerApi.RepoOrdner} not found; pass the repository root");
    return 2;
}
string appOrdner = LohnrechnerApi.AppOrdner(repo);
string casesPfad = Path.Combine(appOrdner, "tests", "golden", "contract", "cases.json");
string personalPfad = Path.Combine(appOrdner, "personal.dat");
foreach (string pfad in new[] { casesPfad, personalPfad })
    if (!File.Exists(pfad))
    {
        // A missing personal.dat would silently mean allowance 0 everywhere; refuse instead
        Console.WriteLine($"ERROR: {pfad} not found");
        return 2;
    }

var personalstamm = Personalstamm.Laden(personalPfad);
Func<int, decimal> holeFreibetrag = personalstamm.HoleFreibetrag;
var faelle = LadeFaelle(casesPfad);

// The eight malformed requests of uContractCases.pas, CheckInvalidRequests
string[] ungueltig =
[
    "not json",
    """{"employeeNumber":1001,"taxClass":3,"churchTax":false,"amount":"1000.00"}""",
    """{"direction":"sideways","employeeNumber":1001,"taxClass":3,"churchTax":false,"amount":"1000.00"}""",
    """{"direction":"grossToNet","employeeNumber":"1001","taxClass":3,"churchTax":false,"amount":"1000.00"}""",
    """{"direction":"grossToNet","employeeNumber":1001,"taxClass":3,"churchTax":"no","amount":"1000.00"}""",
    """{"direction":"grossToNet","employeeNumber":1001,"taxClass":3,"churchTax":false,"amount":1000}""",
    """{"direction":"grossToNet","employeeNumber":1001,"taxClass":3,"churchTax":false,"amount":"1.000,50"}""",
    """{"direction":"grossToNet","employeeNumber":1001,"taxClass":3,"churchTax":false,"amount":"1000.12345"}""",
];

int fehlerGesamt = 0;

// 1. In-process
int fehler = 0;
foreach (var fall in faelle)
    fehler += Pruefe("core", fall, Vertrag.BerechneJson(fall.Anfrage, holeFreibetrag), null, fehler);
Console.WriteLine($"[port core] {faelle.Count} cases, {fehler} failed");
fehlerGesamt += fehler;

// 2. Over HTTP
var app = LohnrechnerApi.Erstelle(["--urls", "http://127.0.0.1:0", "--Logging:LogLevel:Default=Warning"], holeFreibetrag);
await app.StartAsync();
try
{
    // After the start, Urls holds the address actually bound, with the port the system chose
    string adresse = app.Urls.Single();
    using var http = new HttpClient { BaseAddress = new Uri(adresse) };

    fehler = 0;
    foreach (var fall in faelle)
    {
        var (status, body) = await Sende(http, fall.Anfrage);
        fehler += Pruefe("http", fall, body, status, fehler);
    }
    Console.WriteLine($"[port http] {faelle.Count} cases, {fehler} failed");
    fehlerGesamt += fehler;

    // 3. Malformed requests, in-process and over HTTP
    int nichtAbgelehnt = 0;
    foreach (string anfrage in ungueltig)
    {
        string inProzess = Vertrag.BerechneJson(anfrage, holeFreibetrag);
        var (status, body) = await Sende(http, anfrage);
        if (!IstUngueltig(inProzess) || !IstUngueltig(body) || status != 400)
        {
            nichtAbgelehnt++;
            Console.WriteLine($"FAIL port: {anfrage} should be rejected, got {inProzess} / HTTP {status} {body}");
        }
    }
    Console.WriteLine($"[port] {ungueltig.Length} invalid requests, {nichtAbgelehnt} not rejected");
    fehlerGesamt += nichtAbgelehnt;
}
finally
{
    await app.StopAsync();
}

// Guard against a false green: no cases means nothing was checked
if (fehlerGesamt == 0 && faelle.Count > 0)
{
    Console.WriteLine("RESULT: OK");
    return 0;
}
Console.WriteLine("RESULT: FAILED");
return 1;

// Returns 1 if the case failed; prints the first failures of each run
static int Pruefe(string lauf, Fall fall, string tatsaechlich, int? status, int bisher)
{
    string? grund = null;
    if (!GleicherInhalt(fall.Antwort, tatsaechlich))
        grund = $"expected {fall.Antwort}, got {tatsaechlich}";
    else if (status != null && status != ErwarteterStatus(fall.Antwort))
        grund = $"HTTP status {status}, expected {ErwarteterStatus(fall.Antwort)}";
    if (grund == null)
        return 0;
    if (bisher < MaxGezeigt)
        Console.WriteLine($"FAIL port {lauf} {fall.Id}: {grund}");
    return 1;
}

static List<Fall> LadeFaelle(string pfad)
{
    using var dokument = JsonDocument.Parse(File.ReadAllText(pfad, Encoding.UTF8));
    var faelle = new List<Fall>();
    foreach (JsonElement eintrag in dokument.RootElement.GetProperty("cases").EnumerateArray())
        faelle.Add(new Fall(eintrag.GetProperty("id").GetString()!,
            eintrag.GetProperty("request").GetRawText(), eintrag.GetProperty("response").GetRawText()));
    return faelle;
}

static async Task<(int Status, string Body)> Sende(HttpClient http, string anfrage)
{
    using var inhalt = new StringContent(anfrage, Encoding.UTF8, "application/json");
    using var antwort = await http.PostAsync("/calculate", inhalt);
    return ((int)antwort.StatusCode, await antwort.Content.ReadAsStringAsync());
}

// Same field names in the same order, every value a string with the same text
static bool GleicherInhalt(string erwartet, string tatsaechlich)
{
    try
    {
        using var a = JsonDocument.Parse(erwartet);
        using var b = JsonDocument.Parse(tatsaechlich);
        if (a.RootElement.ValueKind != JsonValueKind.Object || b.RootElement.ValueKind != JsonValueKind.Object)
            return false;
        var felderA = a.RootElement.EnumerateObject().ToList();
        var felderB = b.RootElement.EnumerateObject().ToList();
        return felderA.Count == felderB.Count && felderA.Zip(felderB).All(p =>
            p.First.Name == p.Second.Name
            && p.First.Value.ValueKind == JsonValueKind.String
            && p.Second.Value.ValueKind == JsonValueKind.String
            && p.First.Value.GetString() == p.Second.Value.GetString());
    }
    catch (JsonException)
    {
        return false;
    }
}

static int ErwarteterStatus(string antwort)
{
    using var dokument = JsonDocument.Parse(antwort);
    if (!dokument.RootElement.TryGetProperty("error", out JsonElement code))
        return 200;
    return code.GetString() == Vertrag.FehlercodeUngueltig ? 400 : 422;
}

static bool IstUngueltig(string antwort)
{
    try
    {
        using var dokument = JsonDocument.Parse(antwort);
        return dokument.RootElement.TryGetProperty("error", out JsonElement code)
            && code.ValueKind == JsonValueKind.String && code.GetString() == Vertrag.FehlercodeUngueltig;
    }
    catch (JsonException)
    {
        return false;
    }
}

record Fall(string Id, string Anfrage, string Antwort);
