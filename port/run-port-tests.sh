#!/bin/sh
# Runs the C# port's contract tests (macOS/Linux). Exit code: 0 passed, 1 failed, 2 data not found.
# Same as, from the repository root: dotnet run --project port/Lohnrechner.ContractTests
cd "$(dirname "$0")/.." || exit 2
dotnet run --project port/Lohnrechner.ContractTests
