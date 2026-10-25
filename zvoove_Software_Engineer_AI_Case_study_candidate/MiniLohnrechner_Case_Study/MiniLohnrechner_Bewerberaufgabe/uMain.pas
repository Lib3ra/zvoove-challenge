unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, System.UITypes,
  uPersonalstamm;

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
    FPersonalnummer: Integer;
    FSteuerklasse: Integer;   // 1..6, 0 = nicht gewaehlt
    FKirchensteuer: Boolean;
    FGesamtsummeNetto: Currency;
    FUpdating: Boolean;

    function Steuersatz(Klasse: Integer): Double;
    function BerechneNetto(Brutto: Currency): Currency;
    function BerechneBrutto(Netto: Currency): Currency;
  public
    { Public-Deklarationen }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

const
  // Fiktive, frei erfundene Saetze - keine reale Rechtsgrundlage.
  SteuersatzFuerKlasse: array[1..6] of Double = (0.14, 0.18, 0.10, 0.18, 0.26, 0.30);

procedure TForm1.FormCreate(Sender: TObject);
begin
  FPersonalnummer := 0;
  FSteuerklasse := 0;
  FKirchensteuer := False;
  FGesamtsummeNetto := 0;
  FUpdating := False;
  cbSteuerklasse.ItemIndex := -1;
end;

function TForm1.Steuersatz(Klasse: Integer): Double;
begin
  if (Klasse < 1) or (Klasse > 6) then
    Result := 0
  else
    Result := SteuersatzFuerKlasse[Klasse];
end;

function TForm1.BerechneNetto(Brutto: Currency): Currency;
var
  Bemessungsgrundlage, Steuer, KiSt, Freibetrag: Currency;
begin
  Result := 0;

  if FSteuerklasse = 0 then
  begin
    ShowMessage('Bitte zuerst eine Steuerklasse waehlen.');
    Exit;
  end;
  if Brutto < 0 then
  begin
    MessageDlg('Brutto darf nicht negativ sein.', mtWarning, [mbOK], 0);
    Exit;
  end;

  Freibetrag := Personalstamm.HoleFreibetrag(FPersonalnummer);
  Bemessungsgrundlage := Brutto - Freibetrag;
  if Bemessungsgrundlage < 0 then
    Bemessungsgrundlage := 0;

  Steuer := Bemessungsgrundlage * Steuersatz(FSteuerklasse);
  if FKirchensteuer then
    KiSt := Steuer * 0.09
  else
    KiSt := 0;

  Result := Trunc((Brutto - Steuer - KiSt) * 100) / 100;

  FGesamtsummeNetto := FGesamtsummeNetto + Result;
  lblJahressumme.Caption := Format('Jahressumme Netto: %.2f EUR', [FGesamtsummeNetto]);
end;

function TForm1.BerechneBrutto(Netto: Currency): Currency;
var
  Rate: Double;
  Freibetrag: Currency;
begin
  Result := 0;

  if FSteuerklasse = 0 then
  begin
    ShowMessage('Bitte zuerst eine Steuerklasse waehlen.');
    Exit;
  end;
  if Netto < 0 then
  begin
    MessageDlg('Netto darf nicht negativ sein.', mtWarning, [mbOK], 0);
    Exit;
  end;

  Rate := Steuersatz(FSteuerklasse);
  if FKirchensteuer then
    Rate := Rate + Rate * 0.09;
  Freibetrag := Personalstamm.HoleFreibetrag(FPersonalnummer);

  Result := Trunc(((Netto - Rate * Freibetrag) / (1 - Rate)) * 100) / 100;
end;

procedure TForm1.editPersonalnummerChange(Sender: TObject);
begin
  if not TryStrToInt(editPersonalnummer.Text, FPersonalnummer) then
    FPersonalnummer := 0;
  if editBrutto.Text <> '' then
    editBruttoChange(nil);
end;

procedure TForm1.cbSteuerklasseChange(Sender: TObject);
begin
  FSteuerklasse := cbSteuerklasse.ItemIndex + 1;
  if editBrutto.Text <> '' then
    editBruttoChange(nil);
end;

procedure TForm1.chkKirchensteuerClick(Sender: TObject);
begin
  FKirchensteuer := chkKirchensteuer.Checked;
  if editBrutto.Text <> '' then
    editBruttoChange(nil);
end;

procedure TForm1.editBruttoChange(Sender: TObject);
var
  Brutto, Netto: Currency;
begin
  if FUpdating then
    Exit;
  FUpdating := True;
  try
    if TryStrToCurr(editBrutto.Text, Brutto) then
    begin
      Netto := BerechneNetto(Brutto);
      editNetto.Text := CurrToStr(Netto);
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TForm1.editNettoChange(Sender: TObject);
var
  Netto, Brutto: Currency;
begin
  if FUpdating then
    Exit;
  FUpdating := True;
  try
    if TryStrToCurr(editNetto.Text, Netto) then
    begin
      Brutto := BerechneBrutto(Netto);
      editBrutto.Text := CurrToStr(Brutto);
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TForm1.btnResetJahressummeClick(Sender: TObject);
begin
  FGesamtsummeNetto := 0;
  lblJahressumme.Caption := 'Jahressumme Netto: 0,00 EUR';
end;

end.
