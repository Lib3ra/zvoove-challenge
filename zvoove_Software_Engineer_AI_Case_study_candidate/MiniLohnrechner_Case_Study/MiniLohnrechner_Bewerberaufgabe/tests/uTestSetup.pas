unit uTestSetup;

{ Must be the FIRST unit in GoldenTests.dpr. Its initialization runs before
  the one in uPersonalstamm, which loads personal.dat from the exe folder
  using the current number format. So this unit
  - pins the German number format (the app was observed under de-DE), and
  - copies the app's personal.dat next to the test exe. }

interface

var
  AppDir: string;  // folder with MiniLohnrechner.dpr and personal.dat, '' if not found

implementation

uses
  System.SysUtils, System.IOUtils;

// Walks up from the exe until it finds the app's project file
function FindAppDir: string;
var
  Dir: string;
  I: Integer;
begin
  Dir := ExtractFileDir(ParamStr(0));
  for I := 1 to 6 do
  begin
    if FileExists(TPath.Combine(Dir, 'MiniLohnrechner.dpr')) then
      Exit(IncludeTrailingPathDelimiter(Dir));
    Dir := ExtractFileDir(Dir);
  end;
  Result := '';
end;

var
  ExeDir: string;

initialization
  FormatSettings := TFormatSettings.Create('de-DE');
  AppDir := FindAppDir;
  ExeDir := IncludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0)));
  if (AppDir <> '') and not SameText(AppDir, ExeDir) then
    TFile.Copy(AppDir + 'personal.dat', ExeDir + 'personal.dat', True);
end.
