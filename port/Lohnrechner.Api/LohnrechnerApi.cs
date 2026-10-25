using System.Text;
using Lohnrechner.Core;

namespace Lohnrechner.Api;

// The service contract over HTTP: one endpoint, POST /calculate, raw JSON body in, contract
// response out. Transport choices (status codes): docs/decisions.md D22.
public static class LohnrechnerApi
{
    public const string RepoOrdner = "zvoove_Software_Engineer_AI_Case_study_candidate";

    // The folder of the Delphi app inside the repository, which holds personal.dat and the tests
    public static string AppOrdner(string repo) =>
        Path.Combine(repo, RepoOrdner, "MiniLohnrechner_Case_Study", "MiniLohnrechner_Bewerberaufgabe");

    // Walks up from the executable until the repository root is found
    public static string? FindeRepo(string start)
    {
        for (var ordner = new DirectoryInfo(start); ordner != null; ordner = ordner.Parent)
            if (Directory.Exists(Path.Combine(ordner.FullName, RepoOrdner)))
                return ordner.FullName;
        return null;
    }

    public static WebApplication Erstelle(string[] args, Func<int, decimal> holeFreibetrag)
    {
        var builder = WebApplication.CreateSlimBuilder(args);
        var app = builder.Build();

        app.MapPost("/calculate", async (HttpRequest request) =>
        {
            using var reader = new StreamReader(request.Body, Encoding.UTF8);
            string body = await reader.ReadToEndAsync();
            BerechnungsAntwort antwort = Vertrag.BerechneAusJson(body, holeFreibetrag);
            return Results.Content(Vertrag.AntwortAlsJson(antwort), "application/json", Encoding.UTF8, Status(antwort));
        });

        return app;
    }

    // 200 success, 422 business error (the request was understood), 400 malformed request
    public static int Status(BerechnungsAntwort antwort) => antwort.Fehlercode switch
    {
        "" => StatusCodes.Status200OK,
        Vertrag.FehlercodeUngueltig => StatusCodes.Status400BadRequest,
        _ => StatusCodes.Status422UnprocessableEntity,
    };
}
