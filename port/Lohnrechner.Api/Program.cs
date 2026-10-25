using Lohnrechner.Api;
using Lohnrechner.Core;

// Allowances from the repository's personal.dat, loaded once at start like the Delphi app.
// Another file: --personalDat <path>
var config = new ConfigurationBuilder().AddCommandLine(args).Build();
string? pfad = config["personalDat"];
if (pfad == null)
{
    string? repo = LohnrechnerApi.FindeRepo(AppContext.BaseDirectory);
    if (repo == null)
    {
        Console.Error.WriteLine($"Repository folder {LohnrechnerApi.RepoOrdner} not found; pass --personalDat <path>");
        return 2;
    }
    pfad = Path.Combine(LohnrechnerApi.AppOrdner(repo), "personal.dat");
}
var personalstamm = Personalstamm.Laden(pfad);

var app = LohnrechnerApi.Erstelle(args, personalstamm.HoleFreibetrag);
app.Run();
return 0;
