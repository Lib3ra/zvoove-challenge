unit uGoldenRunner;

{ Replays golden files against TForm1 and compares what the form shows.

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
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.UITypes,
  System.SyncObjs, System.Generics.Collections,
  Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs, Vcl.Consts,
  uTestSetup, uPersonalstamm, uMain;

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
    procedure Tick(Sender: TObject);
  public
    Log: TStringList;
    constructor Create;
    destructor Destroy; override;
  end;

  TCaseRunner = class
  private
    FForm: TForm1;
    FDialogs: TDialogCatcher;
    function Field(const Name: string): TEdit;
    procedure DoAct(const Line: string);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Restart;
    procedure Act(const Line: string);
    function Check(const Line: string; out Msg: string): Boolean;
    function Observe: TArray<string>;
    function PendingDialogs: string;
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

constructor TDialogCatcher.Create;
begin
  inherited Create;
  Log := TStringList.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 10;
  FTimer.OnTimer := Tick;
end;

destructor TDialogCatcher.Destroy;
begin
  FTimer.Free;
  Log.Free;
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
      Log.Add(DialogKind(F.Caption) + ' ' + Text);
      F.ModalResult := mrOk;
    end;
  end;
end;

{ TCaseRunner }

constructor TCaseRunner.Create;
begin
  inherited Create;
  FDialogs := TDialogCatcher.Create;
end;

destructor TCaseRunner.Destroy;
begin
  FForm.Free;
  FDialogs.Free;
  inherited;
end;

procedure TCaseRunner.Restart;
begin
  FreeAndNil(FForm);
  FDialogs.Log.Clear;
  FForm := TForm1.Create(nil);
end;

function TCaseRunner.Field(const Name: string): TEdit;
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

procedure TCaseRunner.Act(const Line: string);
begin
  TInterlocked.Exchange(BusySince, Int64(GetTickCount64));
  try
    DoAct(Line);
  finally
    TInterlocked.Exchange(BusySince, 0);
  end;
end;

procedure TCaseRunner.DoAct(const Line: string);
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

function TCaseRunner.PendingDialogs: string;
begin
  Result := String.Join(' | ', FDialogs.Log.ToStringArray);
end;

function TCaseRunner.Check(const Line: string; out Msg: string): Boolean;
var
  What, Expected, Actual: string;
begin
  SplitFirst(Line, What, Expected);
  if What = 'dialog' then
  begin
    if FDialogs.Log.Count = 0 then
      Actual := '(no dialog)'
    else
    begin
      Actual := FDialogs.Log[0];
      FDialogs.Log.Delete(0);
    end;
  end
  else if What = 'no-dialog' then
  begin
    Actual := PendingDialogs;
    FDialogs.Log.Clear;
  end
  else if What = 'total' then
    Actual := FForm.lblJahressumme.Caption
  else
    Actual := Field(What).Text;
  Result := Actual = Expected;
  if not Result then
    Msg := Format('%s: expected "%s", got "%s"', [What, Expected, Actual]);
end;

// Everything the user can see after the actions, as expect lines
function TCaseRunner.Observe: TArray<string>;
var
  D: string;
begin
  Result := [];
  for D in FDialogs.Log do
    Result := Result + ['expect dialog ' + D];
  if FDialogs.Log.Count = 0 then
    Result := Result + ['expect no-dialog'];
  FDialogs.Log.Clear;
  Result := Result + [
    TrimRight('expect brutto ' + FForm.editBrutto.Text),
    TrimRight('expect netto ' + FForm.editNetto.Text),
    'expect total ' + FForm.lblJahressumme.Caption];
end;

procedure RunFile(Runner: TCaseRunner; const FileName: string; var Stats: TStats);
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

procedure RecordCase(Runner: TCaseRunner; Lines: TStringList; const Id: string; const Steps: TArray<string>);
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
function RecordGrid(Runner: TCaseRunner; const FileName: string): Integer;
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
function RecordSequence(Runner: TCaseRunner; const FileName: string): Integer;
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

function RunAll: Integer;
var
  Runner: TCaseRunner;
  GoldenDir, F: string;
  Files: TArray<string>;
  Stats: TStats;
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

    Runner := TCaseRunner.Create;
    try
      if SameText(ParamStr(1), 'record') then
      begin
        Writeln('Recorded ', RecordGrid(Runner, TPath.Combine(GoldenDir, 'grid.golden.txt')), ' grid cases');
        Writeln('Recorded ', RecordSequence(Runner, TPath.Combine(GoldenDir, 'sequence.golden.txt')), ' sequence cases');
        Exit(0);
      end;

      Stats := Default(TStats);
      for F in RequiredFiles do
        if not FileExists(TPath.Combine(GoldenDir, F)) then
        begin
          Writeln('FAIL missing golden file ', F);
          Inc(Stats.FileErrors);
        end;
      Files := TDirectory.GetFiles(GoldenDir, '*.txt');
      TArray.Sort<string>(Files);
      for F in Files do
        RunFile(Runner, F, Stats);
      Writeln(Format('%d cases in %d files, %d failed, %d file errors',
        [Stats.Cases, Length(Files), Stats.Failed, Stats.FileErrors]));
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
