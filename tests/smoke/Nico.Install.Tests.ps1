BeforeDiscovery {
    if ($env:OS -ne 'Windows_NT' -or $env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
        throw 'Installation smoke tests require a disposable GitHub-hosted Windows runner.'
    }
}
BeforeAll {
    $shell = (Get-Process -Id $PID).Path
    $oldScoop = $env:SCOOP
    $oldConfig = $env:XDG_CONFIG_HOME
    $oldCache = $env:SCOOP_CACHE
    $oldGlobal = $env:SCOOP_GLOBAL
    $env:SCOOP = Join-Path $TestDrive 'scoop'
    $env:XDG_CONFIG_HOME = Join-Path $TestDrive 'config'
    $env:SCOOP_CACHE = Join-Path $TestDrive 'cache'
    $env:SCOOP_GLOBAL = Join-Path $TestDrive 'global'
    $null = New-Item (Join-Path $env:SCOOP 'shims') -ItemType Directory -Force
    # Scoop resolves its bundled shim.exe from apps/scoop/current.
    $core = New-Item (Join-Path $env:SCOOP 'apps/scoop/current') -ItemType Directory -Force
    Copy-Item (Join-Path $env:SCOOP_HOME '*') -Destination $core.FullName -Recurse
    $scoopCommand = Join-Path $core.FullName 'bin/scoop.ps1'
    $configDir = New-Item (Join-Path $env:XDG_CONFIG_HOME 'scoop') -ItemType Directory -Force
    '{"aria2-enabled":false,"use_external_7zip":false,"use_isolated_path":true}' | Set-Content (Join-Path $configDir 'config.json')
}
AfterAll {
    $env:SCOOP = $oldScoop
    $env:XDG_CONFIG_HOME = $oldConfig
    $env:SCOOP_CACHE = $oldCache
    $env:SCOOP_GLOBAL = $oldGlobal
}

Describe 'Windows install: <Name> (<Arch>)' -ForEach @(
    @{ Name = 'go-nico-list'; Arch = '64bit' }
    @{ Name = 'go-nico-list'; Arch = '32bit' }
    @{ Name = 'zig-nico-list'; Arch = '64bit' }
) {
    It 'verifies the release hash, installs, runs --help through the shim, and uninstalls' {
        $path = (Resolve-Path (Join-Path $PSScriptRoot "../../bucket/$Name.json")).Path
        $manifest = Get-Content $path -Raw | ConvertFrom-Json
        # Never broaden these tests to arbitrary packages or manifest install hooks.
        $allowedKeys = @('version', 'description', 'homepage', 'license', 'architecture', 'bin', 'extract_dir', 'checkver', 'autoupdate')
        foreach ($key in $manifest.PSObject.Properties.Name) { $key | Should -BeIn $allowedKeys }
        foreach ($variant in $manifest.architecture.PSObject.Properties.Value) {
            foreach ($key in $variant.PSObject.Properties.Name) { $key | Should -BeIn @('url', 'hash') }
            $variant.url | Should -Match (('^https://github\.com/sh4869221b/{0}/releases/download/v[^/]+/[^/]+\.zip$' -f [regex]::Escape($Name)))
        }
        $manifest.bin | Should -Be "$Name.exe"
        try {
            $output = & $shell -NoProfile -File $scoopCommand install $path --arch $Arch --no-update-scoop --independent 2>&1
            $output | ForEach-Object { Write-Host $_ }
            $LASTEXITCODE | Should -Be 0
            $installed = Join-Path $env:SCOOP "apps/$Name/current"
            $exe = Join-Path $installed "$Name.exe"
            Test-Path $exe | Should -BeTrue
            $bytes = [System.IO.File]::ReadAllBytes($exe)
            $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
            $expectedMachine = if ($Arch -eq '32bit') { 0x014c } else { 0x8664 }
            [BitConverter]::ToUInt16($bytes, $peOffset + 4) | Should -Be $expectedMachine
            $record = Get-Content (Join-Path $installed 'install.json') -Raw | ConvertFrom-Json
            $record.architecture | Should -Be $Arch
            $installedManifest = Get-Content (Join-Path $installed 'manifest.json') -Raw | ConvertFrom-Json
            $installedManifest.version | Should -Be $manifest.version
            $shim = Join-Path $env:SCOOP "shims/$Name.exe"
            Test-Path $shim | Should -BeTrue
            $help = & $shim --help 2>&1
            $LASTEXITCODE | Should -Be 0
            ($help | Out-String) | Should -Match '(?i)usage'
        } finally {
            if (Test-Path (Join-Path $env:SCOOP "apps/$Name")) {
                $output = & $shell -NoProfile -File $scoopCommand uninstall $Name 2>&1
                $output | ForEach-Object { Write-Host $_ }
                $LASTEXITCODE | Should -Be 0
            }
        }
        Test-Path (Join-Path $env:SCOOP "apps/$Name") | Should -BeFalse
        @(Get-ChildItem (Join-Path $env:SCOOP 'shims') -Filter "$Name.*").Count | Should -Be 0
    }
}

Describe 'Go ARM64 release archive' {
    It 'has the expected hash and ARM64 executable without executing it on x64' {
        $manifest = Get-Content (Join-Path $PSScriptRoot '../../bucket/go-nico-list.json') -Raw | ConvertFrom-Json
        $variant = $manifest.architecture.arm64
        $variant.url | Should -Match '^https://github\.com/sh4869221b/go-nico-list/releases/download/v[^/]+/go-nico-list_Windows_arm64\.zip$'
        $zip = Join-Path $TestDrive 'go-arm64.zip'
        Invoke-WebRequest -Uri $variant.url -OutFile $zip
        (Get-FileHash $zip -Algorithm SHA256).Hash | Should -Be $variant.hash
        $expanded = Join-Path $TestDrive 'arm64'
        Expand-Archive $zip $expanded
        $exe = Join-Path $expanded 'go-nico-list.exe'
        Test-Path $exe | Should -BeTrue
        $bytes = [System.IO.File]::ReadAllBytes($exe)
        $peOffset = [BitConverter]::ToInt32($bytes, 0x3c)
        [BitConverter]::ToUInt16($bytes, $peOffset + 4) | Should -Be 0xaa64
    }
}
