program MiniLohnrechner;

uses
  Vcl.Forms,
  uMain in 'uMain.pas' {Form1},
  uPersonalstamm in 'uPersonalstamm.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
