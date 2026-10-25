@echo off
rem Runs the golden-file tests of MiniLohnrechner (Win32).
rem  1. Builds tests\GoldenTests.dpr with dcc32 into tests\bin, if this Delphi allows
rem     command-line builds. Community Edition does not: it prints an error and still
rem     exits 0, so success is judged by the exe existing, not by the exit code.
rem  2. Otherwise uses a GoldenTests.exe built in the IDE (tests\, or tests\Win32\Debug|Release).
rem  3. Passes only if the runner prints "RESULT: OK".
setlocal
set "APP=%~dp0zvoove_Software_Engineer_AI_Case_study_candidate\MiniLohnrechner_Case_Study\MiniLohnrechner_Bewerberaufgabe"
set "TESTS=%APP%\tests"
set "BIN=%TESTS%\bin"
set "EXE="

set "RSVARS="
for /d %%D in ("%ProgramFiles(x86)%\Embarcadero\Studio\*") do if exist "%%D\bin\rsvars.bat" set "RSVARS=%%D\bin\rsvars.bat"
if defined RSVARS (
  if not exist "%BIN%\dcu" mkdir "%BIN%\dcu"
  if exist "%BIN%\GoldenTests.exe" del "%BIN%\GoldenTests.exe"
  call "%RSVARS%"
  dcc32 -B -Q -E"%BIN%" -NU"%BIN%\dcu" "%TESTS%\GoldenTests.dpr"
  if exist "%BIN%\GoldenTests.exe" set "EXE=%BIN%\GoldenTests.exe"
)

if not defined EXE (
  echo Command-line build not available. Looking for a GoldenTests.exe built in the IDE.
  if exist "%TESTS%\GoldenTests.exe" set "EXE=%TESTS%\GoldenTests.exe"
  for %%C in (Release Debug) do if exist "%TESTS%\Win32\%%C\GoldenTests.exe" set "EXE=%TESTS%\Win32\%%C\GoldenTests.exe"
)
if not defined EXE (
  echo ERROR: no GoldenTests.exe. Open tests\GoldenTests.dpr in Delphi, platform Win32, and build it.
  exit /b 2
)

echo Running %EXE%
"%EXE%" > "%TEMP%\golden-result.txt"
type "%TEMP%\golden-result.txt"
findstr /x /c:"RESULT: OK" "%TEMP%\golden-result.txt" > nul
if errorlevel 1 (
  echo TESTS FAILED
  exit /b 1
)
echo TESTS PASSED
exit /b 0
