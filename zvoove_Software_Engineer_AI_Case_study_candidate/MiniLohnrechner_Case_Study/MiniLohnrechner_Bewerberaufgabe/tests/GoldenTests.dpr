program GoldenTests;

{ Golden-file tests for MiniLohnrechner, compared against tests\golden\*.txt.
    GoldenTests                     all golden files against the real TForm1 (prints RESULT: OK / FAILED)
    GoldenTests core                the calculation grid against uLohnrechnerCore without
                                    any window, plus the core unit tests (uCoreTests)
    GoldenTests record              re-record the grid and sequence files from the current
                                    code; only ever on the unmodified original
    GoldenTests selftest-watchdog   proves the watchdog ends a hanging step (exit code 1)
    GoldenTests contract            Part 4: checks the service contract (uLohnrechnerVertrag)
                                    against golden\contract\cases.json and the round trip to the grid
    GoldenTests export-contract     regenerates golden\contract\cases.json from the grid
  Build as Win32, like the app: floating point results differ on Win64. }

{$APPTYPE CONSOLE}

uses
  uTestSetup in 'uTestSetup.pas',  // first: pins locale and places personal.dat before uPersonalstamm loads it
  uPersonalstamm in '..\uPersonalstamm.pas',
  uLohnrechnerCore in '..\uLohnrechnerCore.pas',
  uLohnrechnerVertrag in '..\uLohnrechnerVertrag.pas',
  uMain in '..\uMain.pas' {Form1},
  uCoreTests in 'uCoreTests.pas',
  uContractCases in 'uContractCases.pas',
  uGoldenRunner in 'uGoldenRunner.pas';

begin
  ExitCode := RunGolden;
end.
