unit uContractCases;

{ Part 4 slice: the neutral contract test data and its proof.

  The recorded calculation grid (golden\grid.golden.txt) speaks "window": German
  text, dialog kinds. A service or a port in another language can't be checked
  against that. This unit translates every grid case into the contract format of
  uLohnrechnerVertrag (golden\contract\cases.json: request + expected response)
  and proves the translation lost nothing.

    ExportContractCases   writes cases.json (GoldenTests export-contract)
    RunContractChecks     (GoldenTests contract)
      1. round trip: every case, translated back from the contract into window
         lines, equals the recorded golden lines byte for byte
      2. cases.json is exactly what the export produces (no hand edits, not stale)
      3. the contract function answers every request in cases.json with the
         expected response
      4. a few invalid requests are rejected with INVALID_REQUEST (contract rule,
         not original behavior: the window never sees JSON)
  The annual total is not part of the contract (docs/decisions.md D19); its golden
  lines are skipped here and stay covered by the window tests. }

interface

function ExportContractCases(const GoldenDir: string): Integer;  // exit code
function RunContractChecks(const GoldenDir: string): Integer;    // exit code

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  uPersonalstamm, uLohnrechnerCore, uLohnrechnerVertrag;

type
  TGridCase = record
    Id: string;
    Anfrage: TBerechnungsAnfrage;
    Expected: TArray<string>;  // the recorded expect lines, without the total
  end;

  TContractCase = record
    Id: string;
    Anfrage: TBerechnungsAnfrage;
    Antwort: TBerechnungsAntwort;
  end;

var
  German: TFormatSettings;

function GridFile(const GoldenDir: string): string;
begin
  Result := TPath.Combine(GoldenDir, 'grid.golden.txt');
end;

function CasesFile(const GoldenDir: string): string;
begin
  Result := TPath.Combine(GoldenDir, 'contract\cases.json');
end;

function RealLookup: TFreibetragFunc;
begin
  Result :=
    function(Personalnummer: Integer): Currency
    begin
      Result := Personalstamm.HoleFreibetrag(Personalnummer);
    end;
end;

{ Reading the grid }

// A grid case enters values with: set pers, class, church on, set brutto|netto
function ReadGrid(const FileName: string; out Cases: TArray<TGridCase>): string;
var
  Lines: TStringList;
  Line, Rest: string;
  C: TGridCase;
  Open: Boolean;
  Totals: Integer;

  procedure FinishCase;
  begin
    if Open then
      Cases := Cases + [C];
    Open := False;
  end;

begin
  Result := '';
  Cases := [];
  Open := False;
  Totals := 0;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName, TEncoding.UTF8);
    for Line in Lines do
    begin
      if Line.StartsWith('[case ') then
      begin
        FinishCase;
        C := Default(TGridCase);
        C.Id := Copy(Line, 7, Length(Line) - 7);
        Open := True;
      end
      else if not Open or (Line = '') or Line.StartsWith('#') then
        Continue
      else if Line.StartsWith('set pers ') then
      begin
        // The window turns a non-numeric employee number into 0 (quirk 7a)
        if not TryStrToInt(Copy(Line, 10, MaxInt), C.Anfrage.Personalnummer) then
          C.Anfrage.Personalnummer := 0;
      end
      else if Line.StartsWith('class ') then
        C.Anfrage.Steuerklasse := StrToInt(Copy(Line, 7, MaxInt))
      else if Line = 'church on' then
        C.Anfrage.Kirchensteuer := True
      else if Line.StartsWith('set brutto ') or Line.StartsWith('set netto ') then
      begin
        if Line.StartsWith('set brutto ') then
          C.Anfrage.Richtung := rBruttoZuNetto
        else
          C.Anfrage.Richtung := rNettoZuBrutto;
        Rest := Line.Substring(Line.IndexOf(' ', 4) + 1);
        if not TryStrToCurr(Rest, C.Anfrage.Betrag, German) then
          Exit(Format('%s: amount "%s" is not a number', [C.Id, Rest]));
      end
      else if Line.StartsWith('expect total ') then
        Inc(Totals)
      else if Line.StartsWith('expect ') then
        C.Expected := C.Expected + [Line]
      else
        Exit(Format('%s: unexpected line "%s"', [C.Id, Line]));
    end;
    FinishCase;
    if Totals <> Length(Cases) then
      Result := Format('expected one total line per case, found %d for %d cases', [Totals, Length(Cases)]);
  finally
    Lines.Free;
  end;
end;

{ Translating between window lines and the contract }

function DialogKind(const Code: string): string;
begin
  if Code = 'NO_TAX_CLASS' then
    Result := 'message'
  else
    Result := 'warning';
end;

// Window lines -> contract response
function ToContract(const G: TGridCase; out C: TContractCase): string;
var
  Line, Wanted: string;
  F: TLohnFehler;
  Found: Boolean;
begin
  Result := '';
  C.Id := G.Id;
  C.Anfrage := G.Anfrage;
  C.Antwort := Default(TBerechnungsAntwort);
  for Line in G.Expected do
    if Line.StartsWith('expect dialog ') then
    begin
      Found := False;
      for F := Low(TLohnFehler) to High(TLohnFehler) do
        if (F <> lfKeiner) and Line.EndsWith(' ' + FehlerText(F)) then
        begin
          C.Antwort.Fehlercode := Fehlercode(F);
          C.Antwort.Meldung := FehlerText(F);
          Found := True;
        end;
      if not Found then
        Exit(Format('%s: unknown dialog "%s"', [G.Id, Line]));
      Exit;
    end;
  if G.Anfrage.Richtung = rBruttoZuNetto then
    Wanted := 'expect netto '
  else
    Wanted := 'expect brutto ';
  for Line in G.Expected do
    if Line.StartsWith(Wanted) then
    begin
      if not TryStrToCurr(Copy(Line, Length(Wanted) + 1, MaxInt), C.Antwort.Betrag, German) then
        Exit(Format('%s: result "%s" is not a number', [G.Id, Line]));
      Exit;
    end;
  Result := Format('%s: no result line', [G.Id]);
end;

// Contract case -> the window lines the golden file must contain, in the recorder's order
function BackToWindow(const C: TContractCase): TArray<string>;
var
  Eingabe, Ausgabe: string;
begin
  if C.Antwort.Fehlercode <> '' then
    Result := ['expect dialog ' + DialogKind(C.Antwort.Fehlercode) + ' ' + C.Antwort.Meldung]
  else
    Result := ['expect no-dialog'];
  Eingabe := CurrToStr(C.Anfrage.Betrag, German);
  if C.Antwort.Fehlercode <> '' then
    Ausgabe := '0'  // the window writes the error result 0 into the other field
  else
    Ausgabe := CurrToStr(C.Antwort.Betrag, German);
  if C.Anfrage.Richtung = rBruttoZuNetto then
    Result := Result + ['expect brutto ' + Eingabe, 'expect netto ' + Ausgabe]
  else
    Result := Result + ['expect brutto ' + Ausgabe, 'expect netto ' + Eingabe];
end;

function SameLines(const A, B: TArray<string>): Boolean;
var
  I: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for I := 0 to High(A) do
      if A[I] <> B[I] then
        Exit(False);
end;

{ cases.json }

function BuildCasesJson(const Cases: TArray<TContractCase>): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('{').Append(sLineBreak);
    SB.Append('  "source": "golden/grid.golden.txt, recorded from the original app. ')
      .Append('Generated by GoldenTests export-contract; do not edit.",').Append(sLineBreak);
    SB.Append('  "cases": [').Append(sLineBreak);
    for I := 0 to High(Cases) do
    begin
      SB.Append('    {"id":"').Append(Cases[I].Id)
        .Append('","request":').Append(AnfrageAlsJson(Cases[I].Anfrage))
        .Append(',"response":').Append(AntwortAlsJson(Cases[I].Antwort)).Append('}');
      if I < High(Cases) then
        SB.Append(',');
      SB.Append(sLineBreak);
    end;
    SB.Append('  ]').Append(sLineBreak).Append('}').Append(sLineBreak);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Grid -> contract cases, with the round-trip check; returns the number of failures
function Translate(const GoldenDir: string; out Cases: TArray<TContractCase>; Verbose: Boolean): Integer;
var
  Grid: TArray<TGridCase>;
  G: TGridCase;
  C: TContractCase;
  Err: string;
begin
  Result := 0;
  Cases := [];
  Err := ReadGrid(GridFile(GoldenDir), Grid);
  if Err <> '' then
  begin
    Writeln('FAIL contract: ', Err);
    Exit(1);
  end;
  for G in Grid do
  begin
    Err := ToContract(G, C);
    if Err = '' then
    begin
      Cases := Cases + [C];
      if not SameLines(BackToWindow(C), G.Expected) then
        Err := Format('%s: round trip differs: "%s" vs recorded "%s"',
          [G.Id, String.Join(' | ', BackToWindow(C)), String.Join(' | ', G.Expected)]);
    end;
    if Err <> '' then
    begin
      Inc(Result);
      if Verbose or (Result <= 20) then
        Writeln('FAIL contract round trip ', Err);
    end;
  end;
  Writeln(Format('[contract] %d grid cases translated, round trip identical for %d',
    [Length(Grid), Length(Grid) - Result]));
end;

function ExportContractCases(const GoldenDir: string): Integer;
var
  Cases: TArray<TContractCase>;
begin
  if Translate(GoldenDir, Cases, True) > 0 then
  begin
    Writeln('Not exported: the translation is not lossless');
    Exit(1);
  end;
  ForceDirectories(ExtractFilePath(CasesFile(GoldenDir)));
  // UTF-8 without byte order mark: some JSON parsers in other stacks reject one
  TFile.WriteAllBytes(CasesFile(GoldenDir), TEncoding.UTF8.GetBytes(BuildCasesJson(Cases)));
  Writeln('Exported ', Length(Cases), ' cases to ', CasesFile(GoldenDir));
  Result := 0;
end;

{ Checks }

function CheckFileUpToDate(const GoldenDir: string; const Cases: TArray<TContractCase>): Boolean;
var
  OnDisk: string;
begin
  if not FileExists(CasesFile(GoldenDir)) then
  begin
    Writeln('FAIL contract: golden\contract\cases.json is missing (GoldenTests export-contract)');
    Exit(False);
  end;
  // Line endings may be converted by git; compare without CR
  OnDisk := TFile.ReadAllText(CasesFile(GoldenDir), TEncoding.UTF8).Replace(#13, '');
  Result := OnDisk = BuildCasesJson(Cases).Replace(#13, '');
  if Result then
    Writeln('[contract] cases.json is exactly what export-contract generates')
  else
    Writeln('FAIL contract: cases.json differs from what export-contract generates (edited by hand or stale)');
end;

// Every request in cases.json through the contract function, compared to its response
function CheckContractFunction(const GoldenDir: string; out Count: Integer): Integer;
var
  Root: TJSONValue;
  List: TJSONArray;
  Item: TJSONValue;
  Obj: TJSONObject;
  Actual, Expected: string;
begin
  Result := 0;
  Count := 0;
  if not FileExists(CasesFile(GoldenDir)) then
    Exit(1);
  Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(CasesFile(GoldenDir), TEncoding.UTF8));
  try
    if not ((Root is TJSONObject) and (TJSONObject(Root).Values['cases'] is TJSONArray)) then
    begin
      Writeln('FAIL contract: cases.json has no "cases" array');
      Exit(1);
    end;
    List := TJSONArray(TJSONObject(Root).Values['cases']);
    for Item in List do
    begin
      Inc(Count);
      Obj := Item as TJSONObject;
      Expected := Obj.Values['response'].ToJSON;
      Actual := BerechneJson(Obj.Values['request'].ToJSON, RealLookup());
      if Actual <> Expected then
      begin
        Inc(Result);
        if Result <= 20 then
          Writeln(Format('FAIL contract %s: expected %s, got %s', [Obj.Values['id'].Value, Expected, Actual]));
      end;
    end;
  finally
    Root.Free;
  end;
  Writeln(Format('[contract] %d requests through the contract function, %d failed', [Count, Result]));
end;

// Contract rule, not original behavior: malformed requests are rejected, not guessed
function CheckInvalidRequests: Integer;
const
  Invalid: array[0..7] of string = (
    'not json',
    '{"employeeNumber":1001,"taxClass":3,"churchTax":false,"amount":"1000.00"}',
    '{"direction":"sideways","employeeNumber":1001,"taxClass":3,"churchTax":false,"amount":"1000.00"}',
    '{"direction":"grossToNet","employeeNumber":"1001","taxClass":3,"churchTax":false,"amount":"1000.00"}',
    '{"direction":"grossToNet","employeeNumber":1001,"taxClass":3,"churchTax":"no","amount":"1000.00"}',
    '{"direction":"grossToNet","employeeNumber":1001,"taxClass":3,"churchTax":false,"amount":1000}',
    '{"direction":"grossToNet","employeeNumber":1001,"taxClass":3,"churchTax":false,"amount":"1.000,50"}',
    '{"direction":"grossToNet","employeeNumber":1001,"taxClass":3,"churchTax":false,"amount":"1000.12345"}');
var
  Request, Response: string;
begin
  Result := 0;
  for Request in Invalid do
  begin
    Response := BerechneJson(Request, RealLookup());
    if not Response.StartsWith('{"error":"' + FehlercodeUngueltig + '"') then
    begin
      Inc(Result);
      Writeln(Format('FAIL contract: %s should be rejected, got %s', [Request, Response]));
    end;
  end;
  Writeln(Format('[contract] %d invalid requests, %d not rejected', [Length(Invalid), Result]));
end;

function RunContractChecks(const GoldenDir: string): Integer;
var
  Cases: TArray<TContractCase>;
  Failures, Count: Integer;
begin
  Failures := Translate(GoldenDir, Cases, False);
  if not CheckFileUpToDate(GoldenDir, Cases) then
    Inc(Failures);
  Inc(Failures, CheckContractFunction(GoldenDir, Count));
  Inc(Failures, CheckInvalidRequests);
  if (Failures = 0) and (Count > 0) then
  begin
    Writeln('RESULT: OK');
    Result := 0;
  end
  else
  begin
    Writeln('RESULT: FAILED');
    Result := 1;
  end;
end;

initialization
  German := TFormatSettings.Create('de-DE');
end.
