unit uMain;

{ The window. Reads the input fields, calls the calculation in uLohnrechnerCore,
  and shows results and messages. Contains no business logic since the
  extraction; when and how the calculation is triggered (event wiring) stays
  here unchanged. Design decisions: docs/decisions.md (D13, D16). }

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, System.UITypes,
  uPersonalstamm, uLohnrechnerCore;

type
  TForm1 = class(TForm)
    lblPersonalnummer: TLabel;
    lblSteuerklasse: TLabel;
    lblBrutto: TLabel;
    lblNetto: TLabel;
    lblJahressumme: TLabel;
    lblHinweis: TLabel;
    editPersonalnummer: TEdit;
    cbSteuerklasse: TComboBox;
    chkKirchensteuer: TCheckBox;
    editBrutto: TEdit;
    editNetto: TEdit;
    btnResetJahressumme: TButton;
    procedure FormCreate(Sender: TObject);
    procedure editPersonalnummerChange(Sender: TObject);
    procedure cbSteuerklasseChange(Sender: TObject);
    procedure chkKirchensteuerClick(Sender: TObject);
    procedure editBruttoChange(Sender: TObject);
    procedure editNettoChange(Sender: TObject);
    procedure btnResetJahressummeClick(Sender: TObject);
  private
    // Current input values, passed to the calculation on every call
    FPersonalnummer: Integer;
    FSteuerklasse: Integer;   // 1..6, 0 = nicht gewaehlt
    FKirchensteuer: Boolean;
    FUpdating: Boolean;
    FRechner: TLohnrechner;

    procedure ZeigeFehler(Fehler: TLohnFehler);
  public
    destructor Destroy; override;
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

procedure TForm1.FormCreate(Sender: TObject);
begin
  FPersonalnummer := 0;
  FSteuerklasse := 0;
  FKirchensteuer := False;
  FUpdating := False;
  cbSteuerklasse.ItemIndex := -1;
  // The global Personalstamm is read on every call, as before the extraction
  FRechner := TLohnrechner.Create(
    function(Personalnummer: Integer): Currency
    begin
      Result := Personalstamm.HoleFreibetrag(Personalnummer);
    end);
end;

destructor TForm1.Destroy;
begin
  FRechner.Free;
  inherited;
end;

// QUIRK (deliberately not fixed): a missing tax class is a plain message box, a negative
// amount a warning - different dialog types - see docs/uMain-behavior.md #5a, #5c, #5d
procedure TForm1.ZeigeFehler(Fehler: TLohnFehler);
begin
  case Fehler of
    lfKeineSteuerklasse:
      ShowMessage(FehlerText(Fehler));
    lfBruttoNegativ, lfNettoNegativ:
      MessageDlg(FehlerText(Fehler), mtWarning, [mbOK], 0);
  end;
end;

procedure TForm1.editPersonalnummerChange(Sender: TObject);
begin
  // QUIRK (deliberately not fixed): a non-numeric employee number silently becomes 0 - see #7a
  if not TryStrToInt(editPersonalnummer.Text, FPersonalnummer) then
    FPersonalnummer := 0;
  // QUIRK (deliberately not fixed): recalculates from Brutto on every keystroke, even if Netto
  // was edited last; each recalculation adds to the annual total - see #6, #7c
  if editBrutto.Text <> '' then
    editBruttoChange(nil);
end;

procedure TForm1.cbSteuerklasseChange(Sender: TObject);
begin
  FSteuerklasse := cbSteuerklasse.ItemIndex + 1;
  // QUIRK (deliberately not fixed): always recalculates from Brutto, even if Netto was edited
  // last - see #6, #5c
  if editBrutto.Text <> '' then
    editBruttoChange(nil);
end;

procedure TForm1.chkKirchensteuerClick(Sender: TObject);
begin
  FKirchensteuer := chkKirchensteuer.Checked;
  // QUIRK (deliberately not fixed): always recalculates from Brutto - see #6
  if editBrutto.Text <> '' then
    editBruttoChange(nil);
end;

procedure TForm1.editBruttoChange(Sender: TObject);
var
  Brutto: Currency;
  Ergebnis: TLohnErgebnis;
begin
  if FUpdating then
    Exit;
  FUpdating := True;
  try
    // QUIRK (deliberately not fixed): parsing uses the machine's number format, so "250,00"
    // only parses with a German decimal separator - see #9a
    if TryStrToCurr(editBrutto.Text, Brutto) then
    begin
      // Runs on every keystroke: errors show their dialog again each time - see #1, #5a
      Ergebnis := FRechner.BerechneNetto(Brutto, FPersonalnummer, FSteuerklasse, FKirchensteuer);
      ZeigeFehler(Ergebnis.Fehler);
      // QUIRK (deliberately not fixed): the total label is only rewritten after a successful
      // calculation, as before the extraction. Rewriting it on errors too would look the same
      // in German format but turn the hard-coded reset text "0,00" into "0.00" in English
      // format. Not covered by the golden tests (German format) - see docs/decisions.md D13
      if Ergebnis.Fehler = lfKeiner then
        lblJahressumme.Caption := Format('Jahressumme Netto: %.2f EUR', [FRechner.GesamtsummeNetto]);
      // QUIRK (deliberately not fixed): on errors the 0 result is written into Netto;
      // CurrToStr drops trailing zeros ("900,9", not "900,90") - see #5a, #10b
      editNetto.Text := CurrToStr(Ergebnis.Betrag);
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TForm1.editNettoChange(Sender: TObject);
var
  Netto: Currency;
  Ergebnis: TLohnErgebnis;
begin
  if FUpdating then
    Exit;
  FUpdating := True;
  try
    if TryStrToCurr(editNetto.Text, Netto) then
    begin
      Ergebnis := FRechner.BerechneBrutto(Netto, FPersonalnummer, FSteuerklasse, FKirchensteuer);
      ZeigeFehler(Ergebnis.Fehler);
      editBrutto.Text := CurrToStr(Ergebnis.Betrag);
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TForm1.btnResetJahressummeClick(Sender: TObject);
begin
  FRechner.ResetGesamtsumme;
  // QUIRK (deliberately not fixed): hard-coded text with a German comma, while the running
  // total is formatted with the machine's number format - see #9b
  lblJahressumme.Caption := 'Jahressumme Netto: 0,00 EUR';
end;

end.
