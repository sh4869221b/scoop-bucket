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

Describe 'Maintenance workflow revision' {
    BeforeAll {
        $publisher = Join-Path $PSScriptRoot '../../bin/published-revision.ps1'
        $originalOutput = $env:GITHUB_OUTPUT

        function Invoke-TestGit {
            & git @args
            if ($LASTEXITCODE -ne 0) { throw "Git fixture failed: $($args -join ' ')" }
        }

        function Add-TestCommit($Repository, $Message) {
            Invoke-TestGit -C $Repository -c 'user.name=Test' -c 'user.email=test@example.org' -c 'commit.gpgsign=false' commit -q --allow-empty -m $Message
        }

        function Invoke-Publisher($Repository) {
            Push-Location -LiteralPath $Repository
            try { & $publisher } finally { Pop-Location }
        }
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $null = [IO.Directory]::CreateDirectory($root)
        $origin = Join-Path $root 'origin'
        $other = Join-Path $root 'other'
        $bot = Join-Path $root 'bot'
        $env:GITHUB_OUTPUT = Join-Path $root 'output'
        Invoke-TestGit init -q --bare -b master $origin
        Invoke-TestGit init -q -b master $other
        Add-TestCommit $other 'initial'
        Invoke-TestGit -C $other remote add origin $origin
        Invoke-TestGit -C $other push -q origin master
        Invoke-TestGit clone -q $origin $bot
        Invoke-TestGit -C $bot config --local core.logAllRefUpdates true
    }

    AfterAll { $env:GITHUB_OUTPUT = $originalOutput }

    It 'exports the exact direct push even when another writer advances the remote' {
        Add-TestCommit $bot 'Excavator update'
        Invoke-TestGit -C $bot push -q origin master
        $published = Invoke-TestGit -C $bot rev-parse HEAD
        Invoke-TestGit -C $other pull -q --ff-only origin master
        Add-TestCommit $other 'concurrent update'
        Invoke-TestGit -C $other push -q origin master
        Invoke-Publisher $bot
        (Get-Content -LiteralPath $env:GITHUB_OUTPUT) -join ',' | Should -Be "revision=$published,published_ref=refs/heads/master"
        (Invoke-TestGit -C $other rev-parse HEAD) | Should -Not -Be $published
    }

    It 'ignores commits obtained from fetch and commits from a rejected push' {
        Add-TestCommit $other 'concurrent update'
        Invoke-TestGit -C $other push -q origin master
        Invoke-TestGit -C $bot pull -q --ff-only origin master
        Invoke-Publisher $bot
        Test-Path -LiteralPath $env:GITHUB_OUTPUT | Should -BeFalse

        Add-TestCommit $other 'advance again'
        Invoke-TestGit -C $other push -q origin master
        Add-TestCommit $bot 'stale bot update'
        $exitCode = & {
            $ErrorActionPreference = 'Continue'
            $PSNativeCommandUseErrorActionPreference = $false
            git -C $bot push -q origin master 2>$null
            $LASTEXITCODE
        }
        $exitCode | Should -Not -Be 0
        Invoke-Publisher $bot
        Test-Path -LiteralPath $env:GITHUB_OUTPUT | Should -BeFalse
    }

    It 'exports the pushed fallback branch, then omits it if PR creation deleted the ref' {
        Invoke-TestGit -C $bot checkout -q -b 'hash-fix/fixture'
        Add-TestCommit $bot 'hash fix'
        Invoke-TestGit -C $bot push -q origin 'hash-fix/fixture'
        $published = Invoke-TestGit -C $bot rev-parse HEAD
        Invoke-Publisher $bot
        (Get-Content -LiteralPath $env:GITHUB_OUTPUT) -join ',' | Should -Be "revision=$published,published_ref=refs/heads/hash-fix/fixture"
        Remove-Item -LiteralPath $env:GITHUB_OUTPUT
        Invoke-TestGit -C $bot push -q origin --delete 'hash-fix/fixture'
        Invoke-Publisher $bot
        Test-Path -LiteralPath $env:GITHUB_OUTPUT | Should -BeFalse
    }

    It 'returns zero to the workflow shell when the local branch has no remote-tracking ref' {
        Invoke-TestGit -C $bot checkout -q -b 'never-published'
        $shell = (Get-Process -Id $PID).Path
        $step = Join-Path $root 'workflow-step.ps1'
        Set-Content -LiteralPath $step -Value @'
param($Repository, $Publisher)
Set-Location -LiteralPath $Repository
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
& $Publisher
if (Test-Path variable:LASTEXITCODE) { exit $LASTEXITCODE }
'@
        & $shell -NoProfile -File $step $bot $publisher
        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath $env:GITHUB_OUTPUT | Should -BeFalse
    }
}

Describe 'Maintenance CI status routing' {
    It 'reports the published SHA with isolated status permissions and concurrency' {
        $workflows = Join-Path $PSScriptRoot '../../.github/workflows'
        $maintenance = Get-Content -LiteralPath (Join-Path $workflows 'test-maintenance.yml') -Raw
        $tests = Get-Content -LiteralPath (Join-Path $workflows 'ci.yml') -Raw
        $maintenance | Should -Match 'REVISION: \$\{\{ inputs\.revision \}\}'
        $maintenance | Should -Match 'statuses/\$REVISION'
        $maintenance | Should -Not -Match 'statuses/\$GITHUB_SHA'
        $maintenance | Should -Match 'tests:\s+uses: \./\.github/workflows/ci\.yml\s+permissions:\s+contents: read'
        $maintenance | Should -Match 'status:\s+name:[^\r\n]+\s+needs: tests[\s\S]+?permissions:\s+statuses: write'
        $tests | Should -Match "group: tests-.+inputs\.revision && 'maintenance' \|\| github\.event_name"
    }
}
