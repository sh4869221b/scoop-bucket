BeforeDiscovery {
    $scripts = @(Get-ChildItem (Join-Path $PSScriptRoot '../../bin') -Filter '*.ps1' -File)
    $scriptCases = @($scripts | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
    $wrapperCases = @('auto-pr', 'checkhashes', 'checkurls', 'checkver', 'formatjson', 'missing-checkver' | ForEach-Object { @{ Name = $_ } })
}
Describe 'PowerShell syntax: <Name>' -ForEach $scriptCases {
    It 'parses in this PowerShell edition' {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
    }
}
Describe 'Scoop wrapper: <Name>' -ForEach $wrapperCases {
    BeforeAll {
        $previousHome = $env:SCOOP_HOME
        $env:SCOOP_HOME = Join-Path $TestDrive 'Scoop home with spaces'
        $null = New-Item (Join-Path $env:SCOOP_HOME 'bin') -ItemType Directory -Force
        $fake = @'
param([string]$Dir, [string]$Upstream, [string]$App, [switch]$Update)
[pscustomobject]@{ Dir = $Dir; Upstream = $Upstream; App = $App; Update = [bool]$Update }
'@
        Set-Content (Join-Path $env:SCOOP_HOME "bin/$Name.ps1") $fake
    }
    AfterAll { $env:SCOOP_HOME = $previousHome }
    It 'preserves spaces, quotes and metacharacters as data and forwards switches' {
        $literal = 'a b; $(throw "must never execute")'
        $result = & (Join-Path $PSScriptRoot "../../bin/$Name.ps1") -App $literal -Update
        $result.App | Should -Be $literal
        $result.Update | Should -BeTrue
        (Resolve-Path $result.Dir).Path | Should -Be (Resolve-Path (Join-Path $PSScriptRoot '../../bucket')).Path
        if ($Name -eq 'auto-pr') { $result.Upstream | Should -Be 'sh4869221b/scoop-bucket:master' }
    }
}
Describe 'Test runner failure guards' {
    BeforeAll {
        $shell = (Get-Process -Id $PID).Path
        $runner = Join-Path $PSScriptRoot '../../bin/test.ps1'
        function Invoke-RunnerProbe([string]$Path, [string]$ResultPath) {
            # Windows PowerShell treats redirected native stderr as ErrorRecord.
            # These child runs intentionally fail; assert the exit code ourselves.
            $ErrorActionPreference = 'Continue'
            $PSNativeCommandUseErrorActionPreference = $false
            $output = & $shell -NoProfile -File $runner -TestPath $Path -ResultPath $ResultPath 2>&1
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
        }
    }
    It 'rejects an empty test directory' {
        $empty = New-Item (Join-Path $TestDrive 'empty') -ItemType Directory
        $probe = Invoke-RunnerProbe $empty.FullName (Join-Path $TestDrive 'empty.xml')
        $probe.ExitCode | Should -Not -Be 0
        ($probe.Output | Out-String) | Should -Match 'No test files were found'
    }
    It 'rejects <Name>' -ForEach @(
        @{ Name = 'a failed test'; Source = "Describe 'failure' { It 'fails' { 1 | Should -Be 2 } }" }
        @{ Name = 'a discovery failure'; Source = "throw 'broken discovery'" }
        @{ Name = 'an all-skipped suite'; Source = "Describe 'skip' { It 'skipped' -Skip { } }" }
    ) {
        $dir = New-Item (Join-Path $TestDrive ($Name.Replace(' ', '-'))) -ItemType Directory
        Set-Content (Join-Path $dir 'Guard.Tests.ps1') $Source
        $probe = Invoke-RunnerProbe $dir.FullName (Join-Path $dir 'results.xml')
        $probe.ExitCode | Should -Not -Be 0
    }
}
