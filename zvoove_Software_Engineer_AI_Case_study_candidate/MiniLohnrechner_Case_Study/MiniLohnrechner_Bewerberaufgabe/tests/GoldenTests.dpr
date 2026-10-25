program GoldenTests;

{ Golden-file tests for MiniLohnrechner. Drives the real TForm1 through its
  controls and compares against tests\golden\*.txt.
    GoldenTests           verify all golden files (prints RESULT: OK / FAILED)
    GoldenTests record    re-record golden\grid.golden.txt from the current code;
                          only ever on the unmodified original
  Build as Win32, like the app: floating point results differ on Win64. }

{$APPTYPE CONSOLE}

uses
  uTestSetup in 'uTestSetup.pas',  // first: pins locale and places personal.dat before uPersonalstamm loads it
  uPersonalstamm in '..\uPersonalstamm.pas',
  uMain in '..\uMain.pas' {Form1},
  uGoldenRunner in 'uGoldenRunner.pas';

begin
  ExitCode := RunGolden;
end.
