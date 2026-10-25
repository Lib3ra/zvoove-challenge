unit uLohnrechnerVertrag;

(* Service contract for one payroll calculation (Part 4, step 1). A thin wrapper
  around uLohnrechnerCore: it validates and translates a request, calls the core,
  and translates the result. No business logic here, no UI, only System units.
  Specification and examples: docs/service-contract.md.

  Request  {"direction":"grossToNet"|"netToGross","employeeNumber":1001,
            "taxClass":3,"churchTax":false,"amount":"12344.00"}
  Response {"amount":"11134.60"}
        or {"error":"NO_TAX_CLASS","message":"Bitte zuerst eine Steuerklasse waehlen."}

  Amounts are decimal strings with a dot, so no implementation loses a cent to
  binary floating point. Every call is independent: the window's annual total is
  not part of the contract (docs/decisions.md D19).
  Comment delimiters are parenthesis-star here: the JSON examples contain braces. *)

interface

uses
  System.SysUtils, uLohnrechnerCore;

type
  TRichtung = (rBruttoZuNetto, rNettoZuBrutto);

  TBerechnungsAnfrage = record
    Richtung: TRichtung;
    Personalnummer: Integer;
    Steuerklasse: Integer;   // 0 = none chosen
    Kirchensteuer: Boolean;
    Betrag: Currency;
  end;

  TBerechnungsAntwort = record
    Betrag: Currency;        // only meaningful when Fehlercode = ''
    Fehlercode: string;      // '' = success
    Meldung: string;
  end;

const
  FehlercodeUngueltig = 'INVALID_REQUEST';

// One calculation through the core, without JSON
function Berechne(const Anfrage: TBerechnungsAnfrage; const HoleFreibetrag: TFreibetragFunc): TBerechnungsAntwort;

// The contract: JSON request in, JSON response out
function BerechneJson(const AnfrageJson: string; const HoleFreibetrag: TFreibetragFunc): string;

function AnfrageAusJson(const Json: string; out Anfrage: TBerechnungsAnfrage; out Fehler: string): Boolean;
function AnfrageAlsJson(const Anfrage: TBerechnungsAnfrage): string;
function AntwortAlsJson(const Antwort: TBerechnungsAntwort): string;

// "1234.56": dot, at least 2 and at most 4 decimals, no thousands separator
function BetragAlsText(Betrag: Currency): string;
function TextAlsBetrag(const S: string; out Betrag: Currency): Boolean;

function Fehlercode(Fehler: TLohnFehler): string;

implementation

uses
  System.JSON, System.RegularExpressions;

function Fehlercode(Fehler: TLohnFehler): string;
begin
  case Fehler of
    lfKeineSteuerklasse: Result := 'NO_TAX_CLASS';
    lfBruttoNegativ: Result := 'NEGATIVE_GROSS';
    lfNettoNegativ: Result := 'NEGATIVE_NET';
  else
    Result := '';
  end;
end;

function BetragAlsText(Betrag: Currency): string;
begin
  Result := CurrToStrF(Betrag, ffFixed, 4, TFormatSettings.Invariant);
  // Keep two decimals, drop further trailing zeros: 11134.6000 -> 11134.60
  while (Result[Length(Result)] = '0') and (Pos('.', Result) < Length(Result) - 2) do
    Delete(Result, Length(Result), 1);
end;

function TextAlsBetrag(const S: string; out Betrag: Currency): Boolean;
begin
  Result := TRegEx.IsMatch(S, '^-?[0-9]+(\.[0-9]{1,4})?$') and
    TryStrToCurr(S, Betrag, TFormatSettings.Invariant);
end;

function Berechne(const Anfrage: TBerechnungsAnfrage; const HoleFreibetrag: TFreibetragFunc): TBerechnungsAntwort;
var
  Rechner: TLohnrechner;
  Ergebnis: TLohnErgebnis;
begin
  // A fresh core per call: nothing is remembered between requests
  Rechner := TLohnrechner.Create(HoleFreibetrag);
  try
    if Anfrage.Richtung = rBruttoZuNetto then
      Ergebnis := Rechner.BerechneNetto(Anfrage.Betrag, Anfrage.Personalnummer, Anfrage.Steuerklasse,
        Anfrage.Kirchensteuer)
    else
      Ergebnis := Rechner.BerechneBrutto(Anfrage.Betrag, Anfrage.Personalnummer, Anfrage.Steuerklasse,
        Anfrage.Kirchensteuer);
  finally
    Rechner.Free;
  end;
  Result.Betrag := Ergebnis.Betrag;
  Result.Fehlercode := Fehlercode(Ergebnis.Fehler);
  Result.Meldung := FehlerText(Ergebnis.Fehler);
end;

// TJSONNumber derives from TJSONString, so "is a string" must exclude numbers
function IstText(V: TJSONValue): Boolean;
begin
  Result := (V is TJSONString) and not (V is TJSONNumber);
end;

function AnfrageAusJson(const Json: string; out Anfrage: TBerechnungsAnfrage; out Fehler: string): Boolean;
var
  Wert, Feld: TJSONValue;
  Objekt: TJSONObject;
begin
  Result := False;
  Anfrage := Default(TBerechnungsAnfrage);
  Fehler := '';
  Wert := TJSONObject.ParseJSONValue(Json);
  try
    if not (Wert is TJSONObject) then
    begin
      Fehler := 'request must be a JSON object';
      Exit;
    end;
    Objekt := TJSONObject(Wert);

    Feld := Objekt.Values['direction'];
    if IstText(Feld) and (TJSONString(Feld).Value = 'grossToNet') then
      Anfrage.Richtung := rBruttoZuNetto
    else if IstText(Feld) and (TJSONString(Feld).Value = 'netToGross') then
      Anfrage.Richtung := rNettoZuBrutto
    else
    begin
      Fehler := 'direction must be "grossToNet" or "netToGross"';
      Exit;
    end;

    Feld := Objekt.Values['employeeNumber'];
    if not ((Feld is TJSONNumber) and TryStrToInt(TJSONNumber(Feld).Value, Anfrage.Personalnummer)) then
    begin
      Fehler := 'employeeNumber must be an integer';
      Exit;
    end;

    Feld := Objekt.Values['taxClass'];
    if not ((Feld is TJSONNumber) and TryStrToInt(TJSONNumber(Feld).Value, Anfrage.Steuerklasse)) then
    begin
      Fehler := 'taxClass must be an integer (0 = none chosen)';
      Exit;
    end;

    Feld := Objekt.Values['churchTax'];
    if not (Feld is TJSONBool) then
    begin
      Fehler := 'churchTax must be true or false';
      Exit;
    end;
    Anfrage.Kirchensteuer := TJSONBool(Feld).AsBoolean;

    Feld := Objekt.Values['amount'];
    if not (IstText(Feld) and TextAlsBetrag(TJSONString(Feld).Value, Anfrage.Betrag)) then
    begin
      Fehler := 'amount must be a decimal string like "1234.56" (dot, up to 4 decimals)';
      Exit;
    end;
    Result := True;
  finally
    Wert.Free;
  end;
end;

function AnfrageAlsJson(const Anfrage: TBerechnungsAnfrage): string;
var
  Objekt: TJSONObject;
begin
  Objekt := TJSONObject.Create;
  try
    if Anfrage.Richtung = rBruttoZuNetto then
      Objekt.AddPair('direction', 'grossToNet')
    else
      Objekt.AddPair('direction', 'netToGross');
    Objekt.AddPair('employeeNumber', TJSONNumber.Create(Anfrage.Personalnummer));
    Objekt.AddPair('taxClass', TJSONNumber.Create(Anfrage.Steuerklasse));
    Objekt.AddPair('churchTax', TJSONBool.Create(Anfrage.Kirchensteuer));
    Objekt.AddPair('amount', BetragAlsText(Anfrage.Betrag));
    Result := Objekt.ToJSON;
  finally
    Objekt.Free;
  end;
end;

function AntwortAlsJson(const Antwort: TBerechnungsAntwort): string;
var
  Objekt: TJSONObject;
begin
  Objekt := TJSONObject.Create;
  try
    if Antwort.Fehlercode = '' then
      Objekt.AddPair('amount', BetragAlsText(Antwort.Betrag))
    else
    begin
      Objekt.AddPair('error', Antwort.Fehlercode);
      Objekt.AddPair('message', Antwort.Meldung);
    end;
    Result := Objekt.ToJSON;
  finally
    Objekt.Free;
  end;
end;

function BerechneJson(const AnfrageJson: string; const HoleFreibetrag: TFreibetragFunc): string;
var
  Anfrage: TBerechnungsAnfrage;
  Antwort: TBerechnungsAntwort;
  Fehler: string;
begin
  if AnfrageAusJson(AnfrageJson, Anfrage, Fehler) then
    Antwort := Berechne(Anfrage, HoleFreibetrag)
  else
  begin
    // Contract-level input check, not original behavior: the window never sees invalid JSON
    Antwort.Betrag := 0;
    Antwort.Fehlercode := FehlercodeUngueltig;
    Antwort.Meldung := Fehler;
  end;
  Result := AntwortAlsJson(Antwort);
end;

end.
