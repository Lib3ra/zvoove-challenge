unit uLohnrechnerCore;

{ Payroll calculation, moved out of the form TForm1 (uMain) without changing
  its behavior. No UI: no Vcl units, no dialogs. Callers pass all inputs on
  every call; the only state is the running annual net total.

  The code is moved, not rewritten: same types (Currency/Double mix), same
  order of operations, same Trunc rounding, same order of checks.
  Existing quirks are kept on purpose and marked "QUIRK (deliberately not
  fixed)", with the row of docs/uMain-behavior.md where they were observed.
  Design decisions: docs/decisions.md (D12-D16). }

interface

type
  TLohnFehler = (lfKeiner, lfKeineSteuerklasse, lfBruttoNegativ, lfNettoNegativ);

  TLohnErgebnis = record
    Betrag: Currency;     // 0 when Fehler <> lfKeiner
    Fehler: TLohnFehler;
  end;

  // Allowance (Freibetrag) for an employee number
  TFreibetragFunc = reference to function(Personalnummer: Integer): Currency;

  TLohnrechner = class
  private
    FHoleFreibetrag: TFreibetragFunc;
    FGesamtsummeNetto: Currency;
  public
    constructor Create(const HoleFreibetrag: TFreibetragFunc);
    class function Steuersatz(Klasse: Integer): Double; static;
    // Steuerklasse: 1..6, 0 = none chosen
    function BerechneNetto(Brutto: Currency; Personalnummer, Steuerklasse: Integer;
      Kirchensteuer: Boolean): TLohnErgebnis;
    function BerechneBrutto(Netto: Currency; Personalnummer, Steuerklasse: Integer;
      Kirchensteuer: Boolean): TLohnErgebnis;
    procedure ResetGesamtsumme;
    property GesamtsummeNetto: Currency read FGesamtsummeNetto;
  end;

// The original message texts, so every caller shows the same wording
function FehlerText(Fehler: TLohnFehler): string;

implementation

const
  // Fiktive, frei erfundene Saetze - keine reale Rechtsgrundlage.
  // QUIRK (deliberately not fixed): classes II and IV share the rate 0.18 - see docs/uMain-behavior.md #10a
  SteuersatzFuerKlasse: array[1..6] of Double = (0.14, 0.18, 0.10, 0.18, 0.26, 0.30);

function FehlerText(Fehler: TLohnFehler): string;
begin
  case Fehler of
    lfKeineSteuerklasse: Result := 'Bitte zuerst eine Steuerklasse waehlen.';
    lfBruttoNegativ: Result := 'Brutto darf nicht negativ sein.';
    lfNettoNegativ: Result := 'Netto darf nicht negativ sein.';
  else
    Result := '';
  end;
end;

constructor TLohnrechner.Create(const HoleFreibetrag: TFreibetragFunc);
begin
  inherited Create;
  FHoleFreibetrag := HoleFreibetrag;
  FGesamtsummeNetto := 0;
end;

class function TLohnrechner.Steuersatz(Klasse: Integer): Double;
begin
  if (Klasse < 1) or (Klasse > 6) then
    Result := 0
  else
    Result := SteuersatzFuerKlasse[Klasse];
end;

function TLohnrechner.BerechneNetto(Brutto: Currency; Personalnummer, Steuerklasse: Integer;
  Kirchensteuer: Boolean): TLohnErgebnis;
var
  Bemessungsgrundlage, Steuer, KiSt, Freibetrag: Currency;
begin
  Result.Betrag := 0;
  Result.Fehler := lfKeiner;

  // QUIRK (deliberately not fixed): the tax class is checked before the sign, so a negative
  // amount without a class reports the missing class - see docs/uMain-behavior.md #5b
  // Errors return 0 and add nothing to the total - see #5a, #5c
  if Steuerklasse = 0 then
  begin
    Result.Fehler := lfKeineSteuerklasse;
    Exit;
  end;
  if Brutto < 0 then
  begin
    Result.Fehler := lfBruttoNegativ;
    Exit;
  end;

  // QUIRK (deliberately not fixed): unknown employee numbers silently get allowance 0 - see #7b
  Freibetrag := FHoleFreibetrag(Personalnummer);
  Bemessungsgrundlage := Brutto - Freibetrag;
  if Bemessungsgrundlage < 0 then
    Bemessungsgrundlage := 0;

  Steuer := Bemessungsgrundlage * Steuersatz(Steuerklasse);
  if Kirchensteuer then
    KiSt := Steuer * 0.09
  else
    KiSt := 0;

  // QUIRK (deliberately not fixed): Trunc cuts off the third decimal instead of rounding;
  // Steuer and KiSt are Currency, so Currency * Double is rounded to 4 decimals first - see #4
  Result.Betrag := Trunc((Brutto - Steuer - KiSt) * 100) / 100;

  // QUIRK (deliberately not fixed): every successful net calculation adds to the annual total.
  // The form calculates on every keystroke and field change, so the total grows with each
  // one - see #1, #6, #7c
  FGesamtsummeNetto := FGesamtsummeNetto + Result.Betrag;
end;

function TLohnrechner.BerechneBrutto(Netto: Currency; Personalnummer, Steuerklasse: Integer;
  Kirchensteuer: Boolean): TLohnErgebnis;
var
  Rate: Double;
  Freibetrag: Currency;
begin
  Result.Betrag := 0;
  Result.Fehler := lfKeiner;

  // QUIRK (deliberately not fixed): same check order as BerechneNetto, class before sign - see #5b, #5d
  if Steuerklasse = 0 then
  begin
    Result.Fehler := lfKeineSteuerklasse;
    Exit;
  end;
  if Netto < 0 then
  begin
    Result.Fehler := lfNettoNegativ;
    Exit;
  end;

  Rate := Steuersatz(Steuerklasse);
  if Kirchensteuer then
    Rate := Rate + Rate * 0.09;
  Freibetrag := FHoleFreibetrag(Personalnummer);

  // QUIRK (deliberately not fixed): the inverse formula ignores the clamp of the taxable base
  // at 0, so a net below the allowance gives a wrong, even negative gross - see #3, #3b
  // QUIRK (deliberately not fixed): computed in Double and truncated, so some results lose a
  // cent and net -> gross -> net does not round-trip - see #4b, #4e
  Result.Betrag := Trunc(((Netto - Rate * Freibetrag) / (1 - Rate)) * 100) / 100;

  // QUIRK (deliberately not fixed): the gross calculation never adds to the annual total - see #2a
end;

procedure TLohnrechner.ResetGesamtsumme;
begin
  FGesamtsummeNetto := 0;
end;

end.
