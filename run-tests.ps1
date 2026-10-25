# Runs the golden-file tests of MiniLohnrechner (Win32). Called by run-tests.bat.
#  1. Builds tests\GoldenTests.dpr with dcc32 into tests\bin, if this Delphi allows
#     command-line builds. Community Edition does not: dcc32 prints an error and still
#     exits 0, so success is judged by the exe existing, not by the exit code.
#  2. On Community Edition, uses the newest GoldenTests.exe built in the IDE, and refuses
#     it if it is older than any source file (it would test old code).
#  3. Checks that the extracted core unit only uses System units (no UI).
#  4. Runs the exe twice (window mode and core mode); passes only if both exit with 0
#     AND print "RESULT: OK".
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

# The extracted core must not depend on the UI. Allow-list: its uses clauses may only name
# System units (System, System.SysUtils, ...). Comments are removed first so they can't hide
# or end a uses clause. Only direct dependencies are checked, not units used by those units.
function Get-UsedUnits([string]$path) {
  $src = Get-Content $path -Raw
  $src = [regex]::Replace($src, '(?s)\{.*?\}|\(\*.*?\*\)|//[^\r\n]*', ' ')
  foreach ($m in [regex]::Matches($src, '(?is)\buses\b(.*?);')) {
    foreach ($part in $m.Groups[1].Value.Split(',')) {
      ($part -replace "(?is)\bin\s+'[^']*'", '').Trim()
    }
  }
}
$failed = $false
$notAllowed = @(Get-UsedUnits (Join-Path $app 'uLohnrechnerCore.pas') | Where-Object { $_ -notmatch '^System(\.|$)' })
if ($notAllowed.Count -gt 0) {
  Write-Output "FAIL uLohnrechnerCore.pas uses units outside System: $($notAllowed -join ', ')"
  $failed = $true
} else {
  Write-Output 'uLohnrechnerCore.pas uses only System units (no UI)'
}

# Mode '' = every golden file against the real window; 'core' = the calculation grid
# against the core without a window, plus the core unit tests
foreach ($mode in @('', 'core')) {
  Write-Output "Running $($exe.FullName) $mode"
  $output = if ($mode) { & $exe.FullName $mode } else { & $exe.FullName }
  $code = $LASTEXITCODE
  $output | Write-Output
  if ($code -ne 0 -or -not ($output -contains 'RESULT: OK')) {
    Write-Output "FAILED: mode '$mode' (exit code $code)"
    $failed = $true
  }
}

if (-not $failed) {
  Write-Output 'TESTS PASSED'
  exit 0
}
Write-Output 'TESTS FAILED'
exit 1
