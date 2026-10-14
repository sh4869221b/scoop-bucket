#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$TestPath = (Join-Path $PSScriptRoot '../tests/unit'),
    [string]$ResultPath = (Join-Path $PSScriptRoot '../TestResults.xml')
)

$ErrorActionPreference = 'Stop'
Import-Module Pester -RequiredVersion 6.2.0 -ErrorAction Stop
$testFiles = @(Get-ChildItem -LiteralPath $TestPath -Filter '*.Tests.ps1' -File -Recurse -ErrorAction Stop)
if ($testFiles.Count -eq 0) {
    throw "No test files were found in $TestPath. Refusing an empty successful run."
}
$config = New-PesterConfiguration -Hashtable @{
    Run = @{ Path = $testFiles.FullName; PassThru = $true; Exit = $false }
    Output = @{ Verbosity = 'Detailed' }
    TestResult = @{ Enabled = $true; OutputPath = $ResultPath; OutputFormat = 'NUnitXml' }
}
$result = Invoke-Pester -Configuration $config
Write-Host "Test totals: $($result.TotalCount); passed: $($result.PassedCount); failed: $($result.FailedCount); skipped: $($result.SkippedCount); not run: $($result.NotRunCount)"
if ($result.TotalCount -eq 0 -or $result.PassedCount -eq 0 -or $result.Result -ne 'Passed') {
    throw 'Tests failed, discovery failed, or no tests passed. See the Pester results above.'
}
