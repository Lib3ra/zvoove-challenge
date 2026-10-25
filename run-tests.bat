@echo off
rem Runs all tests. The logic is in run-tests.ps1 (Bypass only for this one call).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-tests.ps1"
exit /b %errorlevel%
