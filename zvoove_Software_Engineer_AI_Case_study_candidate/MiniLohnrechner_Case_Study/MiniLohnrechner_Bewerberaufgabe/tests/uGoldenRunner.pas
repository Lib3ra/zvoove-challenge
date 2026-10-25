unit uGoldenRunner;

{ Replays golden files and compares what a user would see. Two drivers:
  TFormDriver runs the real TForm1; TCoreDriver runs uLohnrechnerCore without any
  window, through a minimal adapter like any other caller would use.

  File format (one statement per line, '#' starts a comment):
    [case <id> <title>]        starts a case with a fresh form (= restarting the app)
    type <field> <text>        appends <text> one character at a time (one OnChange per key)
    clear <field>              deletes the last character until empty (one OnChange per key)
    set <field> <text>         replaces the whole text at once (one OnChange)
    class <1..6>               picks a tax class like the user does (fires OnChange)
    church on|off              sets the church tax check box (fires OnClick when it changes)
    reset                      clicks the reset button
    expect <field> <text>      field text must equal <text>
    expect total <caption>     running total label must equal <caption>
    expect dialog <kind> <text>  next logged dialog must match (kind: message, warning, ...)
    expect no-dialog           no dialog may have been shown since the last dialog check
    # cases: <n>               the file must contain exactly <n> cases (catches truncation)
  <field> is pers, brutto or netto. Dialogs left unchecked at the end of a case fail it.
  Every file in RequiredFiles must exist. A step that does not finish within
  StepTimeoutMs (e.g. a dialog the catcher cannot close) fails the whole run. }

interface

function RunGolden: Integer;  // process exit code: 0 ok, 1 failures, 2 setup error

implementation

uses
  Winapi.Windows, System.SysUtils, System.StrUtils, System.Classes, System.IOUtils, System.UITypes,
  System.SyncObjs, System.Generics.Collections,
  Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs, Vcl.Consts,
  uTestSetup, uPersonalstamm, uMain, uLohnrechnerCore, uCoreTests, uContractCases;

const
  RequiredFiles: array[0..2] of string = ('curated.txt', 'grid.golden.txt', 'sequence.golden.txt');
  StepTimeoutMs = 10000;

var
  BusySince: Int64;          // GetTickCount64 when the current step started, 0 while idle
  CurrentWhere: ShortString; // file:line of the current step, for the watchdog message

type
  // Ends the process if one step hangs, instead of blocking the test run forever
  TWatchdog = class(TThread)
  protected
    procedure Execute; override;
  end;
  // Access to the protected Change, which the VCL calls when the user picks an item
  TComboBoxAccess = class(TComboBox);

  // Closes modal message dialogs while they run and logs '<kind> <text>'
  TDialogCatcher = class
  private
    FTimer: TTimer;
    FLog: TStringList;
    procedure Tick(Sender: TObject);
  public
    constructor Create(Log: TStringList);
    destructor Destroy; override;
  end;

  // What the cases run against. Subclasses perform the actions and report what a
  // user would see; checking and observing is shared.
  TDriver = class
  protected
    FDialogs: TStringList;  // '<kind> <text>' of every message shown, in order
    procedure DoAct(const Line: string); virtual; abstract;
    function FieldText(const Name: string): string; virtual; abstract;
    function TotalCaption: string; virtual; abstract;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Restart; virtual; abstract;
    procedure Act(const Line: string);
    function Check(const Line: string; out Msg: string): Boolean;
    function Observe: TArray<string>;
    function PendingDialogs: string;
  end;

  // The real TForm1, driven through its controls like a user
  TFormDriver = class(TDriver)
  private
    FForm: TForm1;
    FCatcher: TDialogCatcher;
    function Field(const Name: string): TEdit;
  protected
    procedure DoAct(const Line: string); override;
    function FieldText(const Name: string): string; override;
    function TotalCaption: string; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Restart; override;
  end;

  // The core TLohnrechner without any window. A minimal adapter mirrors what TForm1's
  // event handlers do (parse text, call the core, format the result, report the message
  // kind), the way any other caller such as a web API would. Only for cases that enter
  // values with 'set', 'class' and 'church' (the calculation grid).
  TCoreDriver = class(TDriver)
  private
    FRechner: TLohnrechner;
    FPers, FBrutto, FNetto, FTotal: string;
    FPersonalnummer, FSteuerklasse: Integer;
    FKirchensteuer: Boolean;
    procedure ZeigeFehler(Fehler: TLohnFehler);
    procedure AusBrutto;
    procedure AusNetto;
  protected
    procedure DoAct(const Line: string); override;
    function FieldText(const Name: string): string; override;
    function TotalCaption: string; override;
  public
    destructor Destroy; override;
    procedure Restart; override;
  end;

  TStats = record
    Cases, Failed, FileErrors: Integer;
  end;

procedure SplitFirst(const S: string; out Head, Tail: string);
var
  P: Integer;
begin
  P := Pos(' ', S);
  if P = 0 then
  begin
    Head := S;
    Tail := '';
  end
  else
  begin
    Head := Copy(S, 1, P - 1);
    Tail := Copy(S, P + 1, MaxInt);
  end;
end;

{ TWatchdog }

procedure TWatchdog.Execute;
var
  Since: Int64;
begin
  while not Terminated do
  begin
    Sleep(500);
    Since := TInterlocked.Read(BusySince);
    if (Since <> 0) and (Int64(GetTickCount64) - Since > StepTimeoutMs) then
    begin
      Writeln(Format('FAIL %s step did not finish within %d s (a dialog the runner cannot close?)',
        [string(CurrentWhere), StepTimeoutMs div 1000]));
      Writeln('RESULT: FAILED');
      Flush(Output);
      ExitProcess(1);
    end;
  end;
end;

// The message form's caption tells the dialog type; ShowMessage (mtCustom) uses the application title
function DialogKind(const Caption: string): string;
begin
  if Caption = SMsgDlgWarning then
    Result := 'warning'
  else if Caption = SMsgDlgError then
    Result := 'error'
  else if Caption = SMsgDlgInformation then
    Result := 'information'
  else if Caption = SMsgDlgConfirm then
    Result := 'confirmation'
  else
    Result := 'message';
end;

{ TDialogCatcher }

constructor TDialogCatcher.Create(Log: TStringList);
begin
  inherited Create;
  FLog := Log;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 10;
  FTimer.OnTimer := Tick;
end;

destructor TDialogCatcher.Destroy;
begin
  FTimer.Free;
  inherited;
end;

// Only fires while a modal loop pumps messages, i.e. while a dialog is open
procedure TDialogCatcher.Tick(Sender: TObject);
var
  I, J: Integer;
  F: TForm;
  Text: string;
begin
  for I := 0 to Screen.FormCount - 1 do
  begin
    F := Screen.Forms[I];
    if (fsModal in F.FormState) and (F.ModalResult = mrNone) and F.ClassNameIs('TMessageForm') then
    begin
      Text := '?';
      for J := 0 to F.ComponentCount - 1 do
        if F.Components[J] is TLabel then
          Text := TLabel(F.Components[J]).Caption;
      FLog.Add(DialogKind(F.Caption) + ' ' + Text);
      F.ModalResult := mrOk;
    end;
  end;
end;

{ TDriver }

constructor TDriver.Create;
begin
  inherited Create;
  FDialogs := TStringList.Create;
end;

destructor TDriver.Destroy;
begin
  FDialogs.Free;
  inherited;
end;

procedure TDriver.Act(const Line: string);
begin
  TInterlocked.Exchange(BusySince, Int64(GetTickCount64));
  try
    DoAct(Line);
  finally
    TInterlocked.Exchange(BusySince, 0);
  end;
end;

function TDriver.PendingDialogs: string;
begin
  Result := String.Join(' | ', FDialogs.ToStringArray);
end;

function TDriver.Check(const Line: string; out Msg: string): Boolean;
var
  What, Expected, Actual: string;
begin
  SplitFirst(Line, What, Expected);
  if What = 'dialog' then
  begin
    if FDialogs.Count = 0 then
      Actual := '(no dialog)'
    else
    begin
      Actual := FDialogs[0];
      FDialogs.Delete(0);
    end;
  end
  else if What = 'no-dialog' then
  begin
    Actual := PendingDialogs;
    FDialogs.Clear;
  end
  else if What = 'total' then
    Actual := TotalCaption
  else
    Actual := FieldText(What);
  Result := Actual = Expected;
  if not Result then
    Msg := Format('%s: expected "%s", got "%s"', [What, Expected, Actual]);
end;

// Everything the user can see after the actions, as expect lines
function TDriver.Observe: TArray<string>;
var
  D: string;
begin
  Result := [];
  for D in FDialogs do
    Result := Result + ['expect dialog ' + D];
  if FDialogs.Count = 0 then
    Result := Result + ['expect no-dialog'];
  FDialogs.Clear;
  Result := Result + [
    TrimRight('expect brutto ' + FieldText('brutto')),
    TrimRight('expect netto ' + FieldText('netto')),
    'expect total ' + TotalCaption];
end;

{ TFormDriver }

constructor TFormDriver.Create;
begin
  inherited Create;
  FCatcher := TDialogCatcher.Create(FDialogs);
end;

destructor TFormDriver.Destroy;
begin
  FForm.Free;
  FCatcher.Free;
  inherited;
end;

procedure TFormDriver.Restart;
begin
  FreeAndNil(FForm);
  FDialogs.Clear;
  FForm := TForm1.Create(nil);
end;

function TFormDriver.Field(const Name: string): TEdit;
begin
  if Name = 'pers' then
    Result := FForm.editPersonalnummer
  else if Name = 'brutto' then
    Result := FForm.editBrutto
  else if Name = 'netto' then
    Result := FForm.editNetto
  else
    raise Exception.CreateFmt('unknown field "%s"', [Name]);
end;

function TFormDriver.FieldText(const Name: string): string;
begin
  Result := Field(Name).Text;
end;

function TFormDriver.TotalCaption: string;
begin
  Result := FForm.lblJahressumme.Caption;
end;

procedure TFormDriver.DoAct(const Line: string);
var
  Verb, Rest, Name, Value: string;
  E: TEdit;
  C: Char;
begin
  SplitFirst(Line, Verb, Rest);
  if Verb = 'type' then
  begin
    SplitFirst(Rest, Name, Value);
    E := Field(Name);
    for C in Value do
      E.Text := E.Text + C;
  end
  else if Verb = 'clear' then
  begin
    E := Field(Rest);
    while E.Text <> '' do
      E.Text := Copy(E.Text, 1, Length(E.Text) - 1);
  end
  else if Verb = 'set' then
  begin
    SplitFirst(Rest, Name, Value);
    Field(Name).Text := Value;
  end
  else if Verb = 'class' then
  begin
    FForm.cbSteuerklasse.ItemIndex := StrToInt(Rest) - 1;
    TComboBoxAccess(FForm.cbSteuerklasse).Change;
  end
  else if Verb = 'church' then
    FForm.chkKirchensteuer.Checked := Rest = 'on'
  else if Verb = 'reset' then
    FForm.btnResetJahressumme.Click
  else
    raise Exception.CreateFmt('unknown action "%s"', [Line]);
end;

{ TCoreDriver }

destructor TCoreDriver.Destroy;
begin
  FRechner.Free;
  inherited;
end;

// Same start state as the window: empty fields, no class, the label text from uMain.dfm
procedure TCoreDriver.Restart;
begin
  FreeAndNil(FRechner);
  FDialogs.Clear;
  FRechner := TLohnrechner.Create(
    function(Personalnummer: Integer): Currency
    begin
      Result := Personalstamm.HoleFreibetrag(Personalnummer);
    end);
  FPers := '';
  FBrutto := '';
  FNetto := '';
  FTotal := 'Jahressumme Netto: 0,00 EUR';
  FPersonalnummer := 0;
  FSteuerklasse := 0;
  FKirchensteuer := False;
end;

procedure TCoreDriver.ZeigeFehler(Fehler: TLohnFehler);
begin
  case Fehler of
    lfKeineSteuerklasse:
      FDialogs.Add('message ' + FehlerText(Fehler));
    lfBruttoNegativ, lfNettoNegativ:
      FDialogs.Add('warning ' + FehlerText(Fehler));
  end;
end;

procedure TCoreDriver.AusBrutto;
var
  Brutto: Currency;
  Ergebnis: TLohnErgebnis;
begin
  if TryStrToCurr(FBrutto, Brutto) then
  begin
    Ergebnis := FRechner.BerechneNetto(Brutto, FPersonalnummer, FSteuerklasse, FKirchensteuer);
    ZeigeFehler(Ergebnis.Fehler);
    if Ergebnis.Fehler = lfKeiner then
      FTotal := Format('Jahressumme Netto: %.2f EUR', [FRechner.GesamtsummeNetto]);
    FNetto := CurrToStr(Ergebnis.Betrag);
  end;
end;

procedure TCoreDriver.AusNetto;
var
  Netto: Currency;
  Ergebnis: TLohnErgebnis;
begin
  if TryStrToCurr(FNetto, Netto) then
  begin
    Ergebnis := FRechner.BerechneBrutto(Netto, FPersonalnummer, FSteuerklasse, FKirchensteuer);
    ZeigeFehler(Ergebnis.Fehler);
    FBrutto := CurrToStr(Ergebnis.Betrag);
  end;
end;

procedure TCoreDriver.DoAct(const Line: string);
var
  Verb, Rest, Name, Value: string;
begin
  SplitFirst(Line, Verb, Rest);
  if Verb = 'set' then
  begin
    SplitFirst(Rest, Name, Value);
    if Name = 'pers' then
    begin
      FPers := Value;
      if not TryStrToInt(FPers, FPersonalnummer) then
        FPersonalnummer := 0;
      if FBrutto <> '' then
        AusBrutto;
    end
    else if Name = 'brutto' then
    begin
      FBrutto := Value;
      AusBrutto;
    end
    else if Name = 'netto' then
    begin
      FNetto := Value;
      AusNetto;
    end
    else
      raise Exception.CreateFmt('unknown field "%s"', [Name]);
  end
  else if Verb = 'class' then
  begin
    FSteuerklasse := StrToInt(Rest);
    if FBrutto <> '' then
      AusBrutto;
  end
  else if Verb = 'church' then
  begin
    // A check box only fires when its state changes
    if FKirchensteuer <> (Rest = 'on') then
    begin
      FKirchensteuer := Rest = 'on';
      if FBrutto <> '' then
        AusBrutto;
    end;
  end
  else
    raise Exception.CreateFmt('action not supported against the core: "%s"', [Line]);
end;

function TCoreDriver.FieldText(const Name: string): string;
begin
  if Name = 'pers' then
    Result := FPers
  else if Name = 'brutto' then
    Result := FBrutto
  else if Name = 'netto' then
    Result := FNetto
  else
    raise Exception.CreateFmt('unknown field "%s"', [Name]);
end;

function TCoreDriver.TotalCaption: string;
begin
  Result := FTotal;
end;

procedure RunFile(Runner: TDriver; const FileName: string; var Stats: TStats);
var
  Lines: TStringList;
  I, LineNo, FileCases, DeclaredCases: Integer;
  Line, CaseId, Verb, Rest, Msg: string;
  CaseFailed: Boolean;

  procedure Fail(const S: string);
  begin
    Writeln(Format('FAIL %s:%d [%s] %s', [ExtractFileName(FileName), LineNo, CaseId, S]));
    CaseFailed := True;
  end;

  procedure FinishCase;
  begin
    if CaseId = '' then
      Exit;
    if Runner.PendingDialogs <> '' then
      Fail('unexpected dialog: ' + Runner.PendingDialogs);
    Inc(Stats.Cases);
    Inc(FileCases);
    if CaseFailed then
      Inc(Stats.Failed);
  end;

begin
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName, TEncoding.UTF8);
    CaseId := '';
    CaseFailed := False;
    LineNo := 0;
    FileCases := 0;
    DeclaredCases := -1;
    for I := 0 to Lines.Count - 1 do
    begin
      LineNo := I + 1;
      CurrentWhere := ShortString(Format('%s:%d', [ExtractFileName(FileName), LineNo]));
      Line := Trim(Lines[I]);
      if Line.StartsWith('# cases:') then
        DeclaredCases := StrToInt(Trim(Copy(Line, 9, MaxInt)));
      if (Line = '') or Line.StartsWith('#') then
        Continue;
      if Line.StartsWith('[case ') and Line.EndsWith(']') then
      begin
        FinishCase;
        CaseId := Copy(Line, 7, Length(Line) - 7);
        CaseFailed := False;
        Runner.Restart;
        Continue;
      end;
      if CaseId = '' then
        raise Exception.CreateFmt('%s:%d: statement outside a case', [FileName, LineNo]);
      try
        SplitFirst(Line, Verb, Rest);
        if Verb = 'expect' then
        begin
          if not Runner.Check(Rest, Msg) then
            Fail(Msg);
        end
        else
          Runner.Act(Line);
      except
        on E: Exception do
          Fail('error: ' + E.Message);
      end;
    end;
    FinishCase;
    if DeclaredCases < 0 then
    begin
      Writeln(Format('FAIL %s: no "# cases: <n>" line', [ExtractFileName(FileName)]));
      Inc(Stats.FileErrors);
    end
    else if DeclaredCases <> FileCases then
    begin
      Writeln(Format('FAIL %s: declares %d cases, contains %d', [ExtractFileName(FileName), DeclaredCases, FileCases]));
      Inc(Stats.FileErrors);
    end;
  finally
    Lines.Free;
  end;
end;

{ Recording. Steps are action lines; 'observe' writes what the form shows at that point. }

procedure RecordCase(Runner: TDriver; Lines: TStringList; const Id: string; const Steps: TArray<string>);
var
  S, O: string;
begin
  Lines.Add('');
  Lines.Add('[case ' + Id + ']');
  Runner.Restart;
  for S in Steps do
    if S = 'observe' then
    begin
      for O in Runner.Observe do
        Lines.Add(O);
    end
    else
    begin
      Lines.Add(S);
      Runner.Act(S);
    end;
end;

procedure SaveRecording(Lines: TStringList; Count: Integer; const FileName: string);
begin
  Lines.Insert(0, '# Recorded from the ORIGINAL uMain.pas with "GoldenTests record".');
  Lines.Insert(1, '# Never re-record after the refactoring: a change here means behavior changed.');
  Lines.Insert(2, '# cases: ' + IntToStr(Count));
  Lines.SaveToFile(FileName, TEncoding.UTF8);
end;

const
  GridPers: array[0..4] of string = ('1001', '1002', '1003', '9999', 'abc');
  GridBrutto: array[0..10] of string = ('-1', '0', '0,01', '1', '249,99', '250', '250,01', '1000',
    '1234,56', '12344', '99999,99');
  GridNetto: array[0..12] of string = ('-1', '0', '0,01', '1', '70', '74', '82', '86', '90', '100',
    '860', '1234,56', '99999,99');

// Calculation grid: all combinations, class 0 = none picked, each value entered at once (set)
function RecordGrid(Runner: TDriver; const FileName: string): Integer;
var
  Lines: TStringList;
  N: Integer;
  Pers, Value: string;
  Klasse: Integer;
  Church: Boolean;

  procedure AddCase(const Pers: string; Klasse: Integer; Church: Boolean; const Field, Value: string);
  var
    Steps: TArray<string>;
  begin
    Inc(N);
    Steps := ['set pers ' + Pers];
    if Klasse > 0 then
      Steps := Steps + ['class ' + IntToStr(Klasse)];
    if Church then
      Steps := Steps + ['church on'];
    Steps := Steps + ['set ' + Field + ' ' + Value, 'observe'];
    RecordCase(Runner, Lines, Format('g%.4d', [N]), Steps);
  end;

begin
  N := 0;
  Lines := TStringList.Create;
  try
    for Pers in GridPers do
      for Klasse := 0 to 6 do
        for Church in [False, True] do
        begin
          for Value in GridBrutto do
            AddCase(Pers, Klasse, Church, 'brutto', Value);
          for Value in GridNetto do
            AddCase(Pers, Klasse, Church, 'netto', Value);
        end;
    SaveRecording(Lines, N, FileName);
  finally
    Lines.Free;
  end;
  Result := N;
end;

// Event wiring: amount typed key by key, then every other control changes it, both directions,
// with an observation after each step. Covers recalculation on church tax, class and employee
// number changes, totals per keystroke, reset of the internal total, and the class picked late.
function RecordSequence(Runner: TDriver; const FileName: string): Integer;
const
  Pers: array[0..1] of string = ('1001', '1003');
  Klassen: array[0..1] of Integer = (2, 3);
  Fields: array[0..1] of string = ('brutto', 'netto');
  Amounts: array[0..1] of string = ('1234,5', '860');
var
  Lines: TStringList;
  P, K, F: Integer;
  ClassFirst: Boolean;
  Steps: TArray<string>;
begin
  Result := 0;
  Lines := TStringList.Create;
  try
    for P := 0 to 1 do
      for K := 0 to 1 do
        for F := 0 to 1 do
          for ClassFirst in [True, False] do
          begin
            Inc(Result);
            Steps := ['type pers ' + Pers[P]];
            if ClassFirst then
              Steps := Steps + ['class ' + IntToStr(Klassen[K])];
            Steps := Steps + ['type ' + Fields[F] + ' ' + Amounts[F], 'observe'];
            if not ClassFirst then
              Steps := Steps + ['class ' + IntToStr(Klassen[K]), 'observe'];
            Steps := Steps + [
              'church on', 'observe',
              'church off', 'observe',
              'class ' + IntToStr(Klassen[K] mod 6 + 1), 'observe',
              'clear pers', 'type pers ' + Pers[1 - P], 'observe',
              'reset', 'observe',
              'church on', 'observe',
              'clear ' + Fields[F], 'observe'];
            RecordCase(Runner, Lines, Format('s%.2d', [Result]), Steps);
          end;
    SaveRecording(Lines, Result, FileName);
  finally
    Lines.Free;
  end;
end;

// Proves the watchdog: a plain Windows message box is invisible to the dialog catcher,
// so this step hangs and the watchdog must end the process with exit code 1
function SelfTestWatchdog: Integer;
begin
  Writeln('Watchdog self-test: a message box opens and must be closed by the watchdog within ',
    StepTimeoutMs div 1000, ' s. Do not click it.');
  CurrentWhere := 'selftest-watchdog';
  TInterlocked.Exchange(BusySince, Int64(GetTickCount64));
  MessageBox(0, 'GoldenTests watchdog self-test. Do not click.', 'GoldenTests', MB_OK);
  Writeln('SELFTEST FAILED: the step returned, the watchdog did not end the process');
  Result := 3;
end;

function RunAll: Integer;
var
  Runner: TDriver;
  GoldenDir, F, Mode: string;
  Files: TArray<string>;
  Stats: TStats;
  UnitCases, UnitFailed: Integer;
begin
  Result := 2;
  try
    Application.Initialize;
    Application.UpdateFormatSettings := False;
    // Classic VCL message form instead of a task dialog, so the catcher can read and close it
    UseLatestCommonDialogs := False;

    if AppDir = '' then
    begin
      Writeln('SETUP ERROR: MiniLohnrechner.dpr not found above ', ParamStr(0));
      Exit;
    end;
    if Personalstamm.HoleFreibetrag(1001) = 0 then
    begin
      Writeln('SETUP ERROR: personal.dat not loaded (missing, or not parsed with German number format)');
      Exit;
    end;
    GoldenDir := TPath.Combine(AppDir, 'tests\golden');
    Mode := LowerCase(ParamStr(1));
    if Mode = 'selftest-watchdog' then
      Exit(SelfTestWatchdog);
    // Part 4 contract: the grid translated into neutral requests/responses (uContractCases)
    if Mode = 'contract' then
      Exit(RunContractChecks(GoldenDir));
    if Mode = 'export-contract' then
      Exit(ExportContractCases(GoldenDir));

    // 'core': the calculation grid against TLohnrechner without the window, plus unit tests.
    // Default: every golden file against the real window.
    if Mode = 'core' then
      Runner := TCoreDriver.Create
    else
      Runner := TFormDriver.Create;
    try
      if Mode = 'record' then
      begin
        Writeln('Recorded ', RecordGrid(Runner, TPath.Combine(GoldenDir, 'grid.golden.txt')), ' grid cases');
        Writeln('Recorded ', RecordSequence(Runner, TPath.Combine(GoldenDir, 'sequence.golden.txt')), ' sequence cases');
        Exit(0);
      end;

      Stats := Default(TStats);
      if Mode = 'core' then
        Files := [TPath.Combine(GoldenDir, 'grid.golden.txt')]
      else
      begin
        for F in RequiredFiles do
          if not FileExists(TPath.Combine(GoldenDir, F)) then
          begin
            Writeln('FAIL missing golden file ', F);
            Inc(Stats.FileErrors);
          end;
        Files := TDirectory.GetFiles(GoldenDir, '*.txt');
        TArray.Sort<string>(Files);
      end;
      for F in Files do
        if FileExists(F) then
          RunFile(Runner, F, Stats)
        else
        begin
          Writeln('FAIL missing golden file ', ExtractFileName(F));
          Inc(Stats.FileErrors);
        end;
      Writeln(Format('[%s] %d cases in %d files, %d failed, %d file errors',
        [IfThen(Mode = 'core', 'core', 'form'), Stats.Cases, Length(Files), Stats.Failed, Stats.FileErrors]));
      if Mode = 'core' then
      begin
        RunCoreUnitTests(UnitCases, UnitFailed);
        Writeln(Format('[core] %d unit tests, %d failed', [UnitCases, UnitFailed]));
        Inc(Stats.Cases, UnitCases);
        Inc(Stats.Failed, UnitFailed);
      end;
      if (Stats.Failed = 0) and (Stats.FileErrors = 0) and (Stats.Cases > 0) then
      begin
        Writeln('RESULT: OK');
        Result := 0;
      end
      else
      begin
        Writeln('RESULT: FAILED');
        Result := 1;
      end;
    finally
      Runner.Free;
    end;
  except
    on E: Exception do
      Writeln('ERROR: ', E.ClassName, ': ', E.Message);
  end;
end;

function RunGolden: Integer;
var
  Watchdog: TWatchdog;
begin
  Watchdog := TWatchdog.Create(False);
  try
    Result := RunAll;
  finally
    Watchdog.Terminate;
    Watchdog.WaitFor;
    Watchdog.Free;
  end;
end;

end.
