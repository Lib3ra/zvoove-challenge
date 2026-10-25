# Runs the golden-file tests of MiniLohnrechner (Win32). Called by run-tests.bat.
#  1. Builds tests\GoldenTests.dpr with dcc32 into tests\bin, if this Delphi allows
#     command-line builds. Community Edition does not: dcc32 prints an error and still
#     exits 0, so success is judged by the exe existing, not by the exit code.
#  2. On Community Edition, uses the newest GoldenTests.exe built in the IDE, and refuses
#     it if it is older than any source file (it would test old code).
#  3. Passes only if the runner exits with 0 AND prints "RESULT: OK".
# Exit codes: 0 passed, 1 tests failed, 2 no usable test exe.

$ErrorActionPreference = 'Stop'
$app = Join-Path $PSScriptRoot 'zvoove_Software_Engineer_AI_Case_study_candidate\MiniLohnrechner_Case_Study\MiniLohnrechner_Bewerberaufgabe'
$tests = Join-Path $app 'tests'
$bin = Join-Path $tests 'bin'
$exe = $null

$rsvars = Get-ChildItem "${env:ProgramFiles(x86)}\Embarcadero\Studio\*\bin\rsvars.bat" -ErrorAction SilentlyContinue |
  Sort-Object FullName | Select-Object -Last 1
if ($rsvars) {
  New-Item -ItemType Directory -Force (Join-Path $bin 'dcu') | Out-Null
  Remove-Item (Join-Path $bin 'GoldenTests.exe') -ErrorAction SilentlyContinue
  $build = cmd /c "call `"$($rsvars.FullName)`" && dcc32 -B -Q -E`"$bin`" -NU`"$bin\dcu`" `"$tests\GoldenTests.dpr`"" 2>&1 | Out-String
  if (Test-Path (Join-Path $bin 'GoldenTests.exe')) {
    $exe = Get-Item (Join-Path $bin 'GoldenTests.exe')
  } elseif ($build -notmatch 'does not support command line compiling') {
    Write-Output $build
    Write-Output 'ERROR: command-line build failed.'
    exit 2
  } else {
    Write-Output 'Command-line build not available (Community Edition). Using the exe built in the IDE.'
  }
}

if (-not $exe) {
  $exe = @("$tests\GoldenTests.exe", "$tests\Win32\Debug\GoldenTests.exe", "$tests\Win32\Release\GoldenTests.exe") |
    Where-Object { Test-Path $_ } | ForEach-Object { Get-Item $_ } |
    Sort-Object LastWriteTime | Select-Object -Last 1
  if (-not $exe) {
    Write-Output 'ERROR: no GoldenTests.exe. Open tests\GoldenTests.dpr in Delphi, platform Win32, and build it.'
    exit 2
  }
  # The exe compiles in ..\*.pas/.dfm and tests\*.pas/.dpr; any newer source means it is stale
  $newest = Get-ChildItem $app, $tests -File |
    Where-Object { $_.Extension -in '.pas', '.dfm', '.dpr' } |
    Sort-Object LastWriteTime | Select-Object -Last 1
  if ($newest.LastWriteTime -gt $exe.LastWriteTime) {
    Write-Output "ERROR: $($exe.FullName) is older than $($newest.Name). Rebuild GoldenTests in the IDE."
    exit 2
  }
}

Write-Output "Running $($exe.FullName)"
$output = & $exe.FullName
$code = $LASTEXITCODE
$output | Write-Output
if ($code -eq 0 -and ($output -contains 'RESULT: OK')) {
  Write-Output 'TESTS PASSED'
  exit 0
}
Write-Output "TESTS FAILED (exit code $code)"
exit 1
