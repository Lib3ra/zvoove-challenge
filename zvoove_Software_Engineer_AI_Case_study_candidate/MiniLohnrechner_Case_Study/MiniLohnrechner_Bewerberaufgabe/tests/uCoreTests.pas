unit uCoreTests;

{ Unit tests of uLohnrechnerCore, without any window. They cover what the golden
  files can't reach through the form: a missing data file (allowance lookup
  returns 0), the lookup being passed in, and the core's results and total as
  numbers rather than formatted text.
  Expected values come from the original app, never computed here: the row of
  docs/uMain-behavior.md or the case id in grid.golden.txt is named in each test. }

interface

procedure RunCoreUnitTests(out Cases, Failed: Integer);

implementation

uses
  System.SysUtils, System.TypInfo, uPersonalstamm, uLohnrechnerCore;

var
  TestName: string;
  TestFailed: Boolean;

procedure Fail(const Msg: string);
begin
  Writeln(Format('FAIL core unit test [%s] %s', [TestName, Msg]));
  TestFailed := True;
end;

procedure ExpectCurr(Actual, Expected: Currency; const What: string);
begin
  if Actual <> Expected then
    Fail(Format('%s: expected %s, got %s', [What, CurrToStr(Expected), CurrToStr(Actual)]));
end;

procedure ExpectFehler(Actual, Expected: TLohnFehler);
begin
  if Actual <> Expected then
    Fail(Format('error kind: expected %s, got %s', [GetEnumName(TypeInfo(TLohnFehler), Ord(Expected)),
      GetEnumName(TypeInfo(TLohnFehler), Ord(Actual))]));
end;

procedure ExpectText(const Actual, Expected, What: string);
begin
  if Actual <> Expected then
    Fail(Format('%s: expected "%s", got "%s"', [What, Expected, Actual]));
end;

// The real data from personal.dat, as the window uses it.
// Call it as RealLookup(): without the parentheses Delphi passes the function itself
function RealLookup: TFreibetragFunc;
begin
  Result :=
    function(Personalnummer: Integer): Currency
    begin
      Result := Personalstamm.HoleFreibetrag(Personalnummer);
    end;
end;

// Same allowance for everyone; 0 = what a missing or unreadable personal.dat gives
function FixedLookup(Freibetrag: Currency): TFreibetragFunc;
begin
  Result :=
    function(Personalnummer: Integer): Currency
    begin
      Result := Freibetrag;
    end;
end;

{ Tests }

// Row 9a: the en-US run, where no allowance could be read, showed 11109.6 for this input
procedure MissingDataMeansAllowanceZero;
var
  R: TLohnrechner;
  E: TLohnErgebnis;
begin
  R := TLohnrechner.Create(FixedLookup(0));
  try
    E := R.BerechneNetto(12344, 1001, 3, False);
    ExpectFehler(E.Fehler, lfKeiner);
    ExpectCurr(E.Betrag, 11109.6, 'net');
    ExpectCurr(R.GesamtsummeNetto, 11109.6, 'total');
  finally
    R.Free;
  end;
end;

// Row 1 / grid g0154: allowance 250 for 1001 gives 11134.6. Proves the passed-in lookup is used.
procedure LookupIsPassedIn;
var
  R: TLohnrechner;
begin
  R := TLohnrechner.Create(FixedLookup(250));
  try
    ExpectCurr(R.BerechneNetto(12344, 1001, 3, False).Betrag, 11134.6, 'net');
  finally
    R.Free;
  end;
end;

// Row 7b / grid g1160: unknown employee 9999 silently gets allowance 0
procedure UnknownEmployeeGetsAllowanceZero;
var
  R: TLohnrechner;
  E: TLohnErgebnis;
begin
  R := TLohnrechner.Create(RealLookup());
  try
    E := R.BerechneNetto(1000, 9999, 3, False);
    ExpectFehler(E.Fehler, lfKeiner);
    ExpectCurr(E.Betrag, 900, 'net');
  finally
    R.Free;
  end;
end;

// Row 5a: no class: error with the original text, result 0, nothing added to the total
procedure NoClassIsAnError;
var
  R: TLohnrechner;
  E: TLohnErgebnis;
begin
  R := TLohnrechner.Create(RealLookup());
  try
    E := R.BerechneNetto(5, 1002, 0, False);
    ExpectFehler(E.Fehler, lfKeineSteuerklasse);
    ExpectCurr(E.Betrag, 0, 'result');
    ExpectCurr(R.GesamtsummeNetto, 0, 'total');
    ExpectText(FehlerText(E.Fehler), 'Bitte zuerst eine Steuerklasse waehlen.', 'message');
  finally
    R.Free;
  end;
end;

// Row 5b: negative amount without a class reports the missing class (class checked first)
procedure ClassIsCheckedBeforeSign;
var
  R: TLohnrechner;
begin
  R := TLohnrechner.Create(RealLookup());
  try
    ExpectFehler(R.BerechneNetto(-5, 0, 0, False).Fehler, lfKeineSteuerklasse);
    ExpectFehler(R.BerechneBrutto(-5, 0, 0, False).Fehler, lfKeineSteuerklasse);
  finally
    R.Free;
  end;
end;

// Rows 5c, 5d: negative amounts with a class, original texts, total unchanged
procedure NegativeAmountsAreErrors;
var
  R: TLohnrechner;
  E: TLohnErgebnis;
begin
  R := TLohnrechner.Create(RealLookup());
  try
    E := R.BerechneNetto(-5, 0, 1, False);
    ExpectFehler(E.Fehler, lfBruttoNegativ);
    ExpectCurr(E.Betrag, 0, 'net result');
    ExpectText(FehlerText(E.Fehler), 'Brutto darf nicht negativ sein.', 'net message');
    E := R.BerechneBrutto(-5, 0, 1, False);
    ExpectFehler(E.Fehler, lfNettoNegativ);
    ExpectCurr(E.Betrag, 0, 'gross result');
    ExpectText(FehlerText(E.Fehler), 'Netto darf nicht negativ sein.', 'gross message');
    ExpectCurr(R.GesamtsummeNetto, 0, 'total');
  finally
    R.Free;
  end;
end;

// Row 2a: net -> gross gives 1000 and never adds to the total
procedure GrossPathDoesNotAddToTotal;
var
  R: TLohnrechner;
begin
  R := TLohnrechner.Create(RealLookup());
  try
    ExpectCurr(R.BerechneBrutto(860, 1002, 1, False).Betrag, 1000, 'gross');
    ExpectCurr(R.GesamtsummeNetto, 0, 'total');
  finally
    R.Free;
  end;
end;

// Rows 4b, 4e: some net -> gross results lose a cent; 4a keeps it
procedure GrossPathLosesCents;
var
  R: TLohnrechner;
begin
  R := TLohnrechner.Create(RealLookup());
  try
    ExpectCurr(R.BerechneBrutto(82, 1002, 2, False).Betrag, 99.99, 'class II');
    ExpectCurr(R.BerechneBrutto(70, 1002, 6, False).Betrag, 99.99, 'class VI');
    ExpectCurr(R.BerechneBrutto(86, 1002, 1, False).Betrag, 100, 'class I');
  finally
    R.Free;
  end;
end;

// Row 3 / grid g0741: the inverse formula ignores the clamp at 0 and goes negative
procedure InverseIgnoresClamp;
var
  R: TLohnrechner;
begin
  R := TLohnrechner.Create(RealLookup());
  try
    ExpectCurr(R.BerechneBrutto(100, 1003, 1, False).Betrag, -46.51, 'gross');
  finally
    R.Free;
  end;
end;

// Row 7c: 1, 10, 100, 1000 (employee 0) give a total of 999.90; after a reset, the next
// result (1001: 925) starts a new total
procedure TotalAccumulatesAndResets;
var
  R: TLohnrechner;
begin
  R := TLohnrechner.Create(RealLookup());
  try
    R.BerechneNetto(1, 0, 3, False);
    R.BerechneNetto(10, 0, 3, False);
    R.BerechneNetto(100, 0, 3, False);
    R.BerechneNetto(1000, 0, 3, False);
    ExpectCurr(R.GesamtsummeNetto, 999.9, 'total after 4 calculations');
    R.ResetGesamtsumme;
    ExpectCurr(R.GesamtsummeNetto, 0, 'total after reset');
    ExpectCurr(R.BerechneNetto(1000, 1001, 3, False).Betrag, 925, 'net');
    ExpectCurr(R.GesamtsummeNetto, 925, 'total after one more');
  finally
    R.Free;
  end;
end;

procedure Run(const Name: string; Test: TProc; var Cases, Failed: Integer);
begin
  TestName := Name;
  TestFailed := False;
  try
    Test;
  except
    on E: Exception do
      Fail('error: ' + E.ClassName + ': ' + E.Message);
  end;
  Inc(Cases);
  if TestFailed then
    Inc(Failed);
end;

procedure RunCoreUnitTests(out Cases, Failed: Integer);
begin
  Cases := 0;
  Failed := 0;
  Run('MissingDataMeansAllowanceZero', MissingDataMeansAllowanceZero, Cases, Failed);
  Run('LookupIsPassedIn', LookupIsPassedIn, Cases, Failed);
  Run('UnknownEmployeeGetsAllowanceZero', UnknownEmployeeGetsAllowanceZero, Cases, Failed);
  Run('NoClassIsAnError', NoClassIsAnError, Cases, Failed);
  Run('ClassIsCheckedBeforeSign', ClassIsCheckedBeforeSign, Cases, Failed);
  Run('NegativeAmountsAreErrors', NegativeAmountsAreErrors, Cases, Failed);
  Run('GrossPathDoesNotAddToTotal', GrossPathDoesNotAddToTotal, Cases, Failed);
  Run('GrossPathLosesCents', GrossPathLosesCents, Cases, Failed);
  Run('InverseIgnoresClamp', InverseIgnoresClamp, Cases, Failed);
  Run('TotalAccumulatesAndResets', TotalAccumulatesAndResets, Cases, Failed);
end;

end.
