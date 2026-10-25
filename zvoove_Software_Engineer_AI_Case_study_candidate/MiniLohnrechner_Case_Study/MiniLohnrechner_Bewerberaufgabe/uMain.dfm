object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'Mini-Lohnrechner'
  ClientHeight = 400
  ClientWidth = 420
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 15
  object lblPersonalnummer: TLabel
    Left = 24
    Top = 24
    Width = 96
    Height = 15
    Caption = 'Personalnummer:'
  end
  object lblSteuerklasse: TLabel
    Left = 24
    Top = 64
    Width = 78
    Height = 15
    Caption = 'Steuerklasse:'
  end
  object lblBrutto: TLabel
    Left = 24
    Top = 112
    Width = 89
    Height = 15
    Caption = 'Brutto (EUR):'
  end
  object lblNetto: TLabel
    Left = 24
    Top = 152
    Width = 78
    Height = 15
    Caption = 'Netto (EUR):'
  end
  object lblJahressumme: TLabel
    Left = 24
    Top = 230
    Width = 180
    Height = 15
    Caption = 'Jahressumme Netto: 0,00 EUR'
  end
  object lblHinweis: TLabel
    Left = 24
    Top = 270
    Width = 372
    Height = 60
    AutoSize = False
    WordWrap = True
    Caption =
      'Hinweis: Steuersaetze sind frei erfunden, keine reale Rechtsgr' +
      'undlage. Es geht nur um Code-Struktur. Testbare Personalnummer' +
      'n: 1001, 1002, 1003 (siehe personal.dat).'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -11
    Font.Name = 'Segoe UI'
    Font.Style = [fsItalic]
    ParentFont = False
  end
  object editPersonalnummer: TEdit
    Left = 160
    Top = 21
    Width = 145
    Height = 23
    TabOrder = 0
    OnChange = editPersonalnummerChange
  end
  object cbSteuerklasse: TComboBox
    Left = 160
    Top = 61
    Width = 145
    Height = 23
    Style = csDropDownList
    TabOrder = 1
    OnChange = cbSteuerklasseChange
    Items.Strings = (
      'I'
      'II'
      'III'
      'IV'
      'V'
      'VI')
  end
  object chkKirchensteuer: TCheckBox
    Left = 160
    Top = 90
    Width = 145
    Height = 17
    Caption = 'Kirchensteuerpflichtig'
    TabOrder = 2
    OnClick = chkKirchensteuerClick
  end
  object editBrutto: TEdit
    Left = 160
    Top = 109
    Width = 145
    Height = 23
    TabOrder = 3
    OnChange = editBruttoChange
  end
  object editNetto: TEdit
    Left = 160
    Top = 149
    Width = 145
    Height = 23
    TabOrder = 4
    OnChange = editNettoChange
  end
  object btnResetJahressumme: TButton
    Left = 24
    Top = 190
    Width = 180
    Height = 25
    Caption = 'Jahressumme zuruecksetzen'
    TabOrder = 5
    OnClick = btnResetJahressummeClick
  end
end
