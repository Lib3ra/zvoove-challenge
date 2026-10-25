unit uPersonalstamm;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TPersonalstamm = class
  private
    FFreibetraege: TDictionary<Integer, Currency>;
    procedure Laden;
  public
    constructor Create;
    destructor Destroy; override;
    function HoleFreibetrag(Personalnummer: Integer): Currency;
  end;

var
  Personalstamm: TPersonalstamm;

implementation

constructor TPersonalstamm.Create;
begin
  inherited Create;
  FFreibetraege := TDictionary<Integer, Currency>.Create;
  Laden;
end;

destructor TPersonalstamm.Destroy;
begin
  FFreibetraege.Free;
  inherited;
end;

procedure TPersonalstamm.Laden;
var
  Zeilen: TStringList;
  Zeile: string;
  Teile: TArray<string>;
  PersNr: Integer;
  Freibetrag: Currency;
  Pfad: string;
begin
  Pfad := ExtractFilePath(ParamStr(0)) + 'personal.dat';
  // QUIRK (deliberately not fixed): a missing file is ignored silently, every allowance
  // is then 0 - see docs/uMain-behavior.md #8
  if not FileExists(Pfad) then
    Exit;
  Zeilen := TStringList.Create;
  try
    Zeilen.LoadFromFile(Pfad);
    for Zeile in Zeilen do
    begin
      Teile := Zeile.Split([';']);
      // QUIRK (deliberately not fixed): TryStrToCurr uses the machine's number format, so
      // "250,00" fails on a non-German Windows and the line is skipped silently - see #9a
      if Length(Teile) = 2 then
        if TryStrToInt(Teile[0], PersNr) and TryStrToCurr(Teile[1], Freibetrag) then
          FFreibetraege.AddOrSetValue(PersNr, Freibetrag);
    end;
  finally
    Zeilen.Free;
  end;
end;

// QUIRK (deliberately not fixed): unknown employee numbers get 0 without any message - see #7b
function TPersonalstamm.HoleFreibetrag(Personalnummer: Integer): Currency;
begin
  if not FFreibetraege.TryGetValue(Personalnummer, Result) then
    Result := 0;
end;

initialization
  // Loaded once at program start from the exe's folder; left unchanged by the extraction
  // (data access, already free of UI) - see docs/decisions.md D15
  Personalstamm := TPersonalstamm.Create;

finalization
  Personalstamm.Free;

end.
