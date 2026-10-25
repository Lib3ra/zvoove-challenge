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
  if not FileExists(Pfad) then
    Exit;
  Zeilen := TStringList.Create;
  try
    Zeilen.LoadFromFile(Pfad);
    for Zeile in Zeilen do
    begin
      Teile := Zeile.Split([';']);
      if Length(Teile) = 2 then
        if TryStrToInt(Teile[0], PersNr) and TryStrToCurr(Teile[1], Freibetrag) then
          FFreibetraege.AddOrSetValue(PersNr, Freibetrag);
    end;
  finally
    Zeilen.Free;
  end;
end;

function TPersonalstamm.HoleFreibetrag(Personalnummer: Integer): Currency;
begin
  if not FFreibetraege.TryGetValue(Personalnummer, Result) then
    Result := 0;
end;

initialization
  Personalstamm := TPersonalstamm.Create;

finalization
  Personalstamm.Free;

end.
