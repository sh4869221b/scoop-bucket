BeforeDiscovery { $skipWindowsHooks = $env:OS -ne 'Windows_NT' }

BeforeAll {
    function Read-BucketManifest([string]$Name) {
        Get-Content -LiteralPath (Join-Path $PSScriptRoot "../../bucket/$Name.json") -Raw | ConvertFrom-Json
    }
}

Describe 'commeon transport' {
    It 'uses the official HTTPS page for version discovery and HTTPS for both download paths' {
        $manifest = Read-BucketManifest 'commeon'
        $manifest.homepage | Should -Be 'https://air.fem.jp/commeon/'
        $manifest.checkver | Should -BeOfType [string]
        $manifest.url | Should -Be 'https://air.fem.jp/commeon/commeon.zip'
        $manifest.autoupdate.url | Should -Be $manifest.url
    }
}

Describe 'Architecture selection for <Name>' -ForEach @(
    @{ Name = 'Niconicome'; Expected = '64bit' }
    @{ Name = 'compactgui'; Expected = '64bit' }
    @{ Name = 'virtualbox'; Expected = '64bit,arm64' }
    @{ Name = 'psc-package'; Expected = '64bit' }
    @{ Name = 'min'; Expected = '64bit,arm64' }
    @{ Name = 'wasm-pack'; Expected = '64bit,arm64' }
    @{ Name = 'ppsspp-dev'; Expected = '32bit,64bit,arm64' }
    @{ Name = 'yt-dlp'; Expected = '32bit,64bit,arm64' }
    @{ Name = 'TablacusExplorer'; Expected = '32bit,64bit' }
) {
    It 'selects the supported downloads using the pinned Scoop resolver' {
        . (Join-Path $env:SCOOP_HOME 'lib/manifest.ps1')
        . (Join-Path $env:SCOOP_HOME 'lib/json.ps1')
        $manifest = Read-BucketManifest $Name
        # These are explicit package variants. Scoop handles x64 emulation separately.
        $actual = foreach ($arch in '32bit', '64bit', 'arm64') {
            if ($arch -eq 'arm64' -and !$manifest.architecture.arm64) { continue }
            Get-SupportedArchitecture $manifest $arch
        }
        $actual -join ',' | Should -Be $Expected
    }
}

Describe 'Verified release assets' {
    It 'uses the Min ZIP layout and official Windows asset names' {
        $manifest = Read-BucketManifest 'min'
        $manifest.extract_dir | Should -Be "Min-v$($manifest.version)"
        $manifest.autoupdate.extract_dir.Replace('$version', $manifest.version) | Should -Be $manifest.extract_dir
        foreach ($arch in '64bit', 'arm64') {
            $manifest.autoupdate.architecture.$arch.url.Replace('$version', $manifest.version) | Should -Be $manifest.architecture.$arch.url
        }
        $manifest.architecture.'64bit'.url | Should -Match '/Min-v[\d.]+-windows\.zip$'
        $manifest.architecture.arm64.url | Should -Match '/Min-v[\d.]+-windows-arm64\.zip$'
    }

    It 'selects CompactGUI final releases even when GitHub lists a beta as latest' {
        . (Join-Path $env:SCOOP_HOME 'lib/json.ps1')
        $manifest = Read-BucketManifest 'compactgui'
        $manifest.checkver.github | Should -BeLike 'https://api.github.com/repos/IridiumIO/CompactGUI/releases?*'
        $candidates = '[{"tag_name":"v4.0.0-beta.12","prerelease":false},{"tag_name":"v3.9.0","prerelease":true},{"tag_name":"v3.8.0","prerelease":false}]'
        $versions = json_path $candidates $manifest.checkver.jsonpath
        $match = [regex]::Match($versions, $manifest.checkver.regex)
        $match.Groups[1].Value | Should -Be '3.8.0'
        $single = json_path '[{"tag_name":"v3.8.0","prerelease":false}]' $manifest.checkver.jsonpath
        [regex]::Match($single, $manifest.checkver.regex).Groups[1].Value | Should -Be '3.8.0'
        $manifest.autoupdate.architecture.'64bit'.url.Replace('$version', $manifest.version) | Should -Be $manifest.architecture.'64bit'.url
    }

    It 'uses the Tablacus release asset stem and picks the correct shortcut for the shared ZIP' {
        . (Join-Path $env:SCOOP_HOME 'lib/json.ps1')
        . (Join-Path $env:SCOOP_HOME 'lib/manifest.ps1')
        $manifest = Read-BucketManifest 'TablacusExplorer'
        $manifest.checkver.github | Should -Be 'https://api.github.com/repos/tablacus/TablacusExplorer/releases/latest'
        $zip = 'https://github.com/tablacus/TablacusExplorer/releases/download/26.9.20/te260920.zip'
        $release = '{"assets":[{"browser_download_url":"' + $zip + '"}]}'
        $match = [regex]::Match((json_path $release $manifest.checkver.jsonpath), $manifest.checkver.regex)
        $match.Groups['version'].Value | Should -Be '26.9.20'
        $match.Groups['file'].Value | Should -Be '260920'
        $manifest.autoupdate.url.Replace('$version', $match.Groups['version'].Value).Replace('$matchFile', $match.Groups['file'].Value) | Should -Be $zip
        (arch_specific 'shortcuts' $manifest '32bit')[0] | Should -Be 'TE32.exe'
        (arch_specific 'shortcuts' $manifest '64bit')[0] | Should -Be 'TE64.exe'
    }

    It 'detects a GanttProject ZIP even where the release tag differs from the asset version' {
        . (Join-Path $env:SCOOP_HOME 'lib/json.ps1')
        $manifest = Read-BucketManifest 'ganttproject'
        $manifest.checkver.github | Should -Be 'https://api.github.com/repos/bardsoftware/ganttproject/releases/latest'
        $zip = 'https://github.com/bardsoftware/ganttproject/releases/download/ganttproject-3.2.3200/ganttproject-3.2.3230.zip'
        $release = '{"assets":[{"browser_download_url":"' + $zip + '"}]}'
        $match = [regex]::Match((json_path $release $manifest.checkver.jsonpath), $manifest.checkver.regex)
        $match.Groups['version'].Value | Should -Be '3.2.3230'
        $manifest.autoupdate.url.Replace('$matchTag', $match.Groups['tag'].Value).Replace('$version', $match.Groups['version'].Value) | Should -Be $zip
        $manifest.url | Should -BeOfType [string]
        $manifest.extract_dir | Should -BeNullOrEmpty
        $manifest.shortcuts[0][0] | Should -Be 'ganttproject.bat'
    }

    It 'requires both PPSSPP ZIPs for the same build and reconstructs its matching downloads' {
        $manifest = Read-BucketManifest 'ppsspp-dev'
        $manifest.checkver.url | Should -Be 'https://builds.ppsspp.org/meta/history-20.json'
        $selector = [scriptblock]::Create($manifest.checkver.script -join "`n")
        $page = @'
[
  {"description":"v1.20.4-4977-gabcd","builds":{"Windows":["ppsspp_win_v1.20.4-4977-gabcd.zip"]}},
  {"description":"v1.20.4-4976-gabcd","builds":{"WindowsARM64":["PPSSPPWindowsARM64_v1.20.4-4976-gabcd.zip"]}},
  {"description":"v1.20.4-4975-gabcd","builds":{"Windows":["ppsspp_win_v1.20.4-4975-gabcd.zip"],"WindowsARM64":["PPSSPPWindowsARM64_v1.20.4-4976-gabcd.zip"]}},
  {"description":"v1.20.4-4974-g154d52379a3f","builds":{"Windows":["ppsspp_win_v1.20.4-4974-g154d52379a3f.zip"],"WindowsARM64":["PPSSPPWindowsARM64_v1.20.4-4974-g154d52379a3f.zip"]}}
]
'@
        $match = [regex]::Match((& $selector), $manifest.checkver.regex)
        $match.Groups['version'].Value | Should -Be '1.20.4-4974'
        $match.Groups['build'].Value | Should -Be 'g154d52379a3f'
        $expected = @{
            '32bit' = 'ppsspp_win_v1.20.4-4974-g154d52379a3f.zip'
            '64bit' = 'ppsspp_win_v1.20.4-4974-g154d52379a3f.zip'
            arm64 = 'PPSSPPWindowsARM64_v1.20.4-4974-g154d52379a3f.zip'
        }
        foreach ($arch in $expected.Keys) {
            $download = $manifest.autoupdate.architecture.$arch.url.Replace('$version', $match.Groups['version'].Value).Replace('$matchBuild', $match.Groups['build'].Value)
            $download | Should -Be "https://builds.ppsspp.org/builds/v1.20.4-4974-g154d52379a3f/$($expected[$arch])"
        }
        $manifest.architecture.'32bit'.bin[0][0] | Should -Be 'PPSSPPWindows.exe'
        $manifest.architecture.'64bit'.bin[0][0] | Should -Be 'PPSSPPWindows64.exe'
        $manifest.architecture.arm64.bin[0][0] | Should -Be 'PPSSPPWindowsARM64.exe'
        $manifest.extract_dir | Should -BeNullOrEmpty
        $manifest.persist | Should -Be 'memstick'
        $page = (ConvertFrom-Json $page | Select-Object -First 3) | ConvertTo-Json -Depth 6
        (& $selector) | Should -BeNullOrEmpty
    }

    It 'uses Scoop SHA-256 discovery and downloads for psc-package' {
        $manifest = Read-BucketManifest 'psc-package'
        $manifest.architecture.'64bit'.hash | Should -Match '^[0-9a-f]{64}$'
        $manifest.autoupdate.hash | Should -BeNullOrEmpty
        $manifest.autoupdate.architecture.'64bit'.url.Replace('$version', $manifest.version) | Should -Be $manifest.architecture.'64bit'.url
    }

    It 'installs the wasm-pack CLI from the matching archives' {
        $manifest = Read-BucketManifest 'wasm-pack'
        $manifest.bin | Should -Be 'wasm-pack.exe'
        foreach ($arch in '64bit', 'arm64') {
            $release = $manifest.architecture.$arch
            $update = $manifest.autoupdate.architecture.$arch
            $release.url | Should -BeLike "*/$($release.extract_dir).tar.gz"
            $update.url.Replace('$version', $manifest.version) | Should -Be $release.url
            $update.extract_dir.Replace('$version', $manifest.version) | Should -Be $release.extract_dir
        }
    }

    It 'retains the yt-dlp shim name on all three official build variants' {
        $manifest = Read-BucketManifest 'yt-dlp'
        $manifest.bin | Should -Be 'yt-dlp.exe'
        $manifest.architecture.'64bit'.url | Should -Match '/yt-dlp\.exe$'
        $manifest.architecture.'32bit'.url | Should -Match '/yt-dlp_x86\.exe#/yt-dlp\.exe$'
        $manifest.architecture.arm64.url | Should -Match '/yt-dlp_arm64\.exe#/yt-dlp\.exe$'
        foreach ($arch in '32bit', '64bit', 'arm64') {
            $manifest.autoupdate.architecture.$arch.url.Replace('$version', $manifest.version) | Should -Be $manifest.architecture.$arch.url
        }
    }
}

Describe 'Niconicome persistence' {
    BeforeAll {
        $manifest = Read-BucketManifest 'Niconicome'
        $preInstall = [scriptblock]::Create($manifest.pre_install -join "`n")
        $preUninstall = [scriptblock]::Create($manifest.pre_uninstall -join "`n")
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $dir = Join-Path $root 'app [test space]'
        $persist_dir = Join-Path $root 'persist [test space]'
        $null = [IO.Directory]::CreateDirectory($dir)
        $null = [IO.Directory]::CreateDirectory($persist_dir)
        $db = Join-Path $dir 'niconicome.db'
        $savedDb = Join-Path $persist_dir 'niconicome.db'
        Mock Start-Process { throw 'Unexpected GUI launch' }
        Mock Stop-Process { throw 'Unexpected process stop' }
    }

    It 'creates only an empty database file for Scoop to hard-link on first install' {
        & $preInstall
        (Get-Item -LiteralPath $db).Length | Should -Be 0
        Test-Path -LiteralPath $db -PathType Leaf | Should -BeTrue
        $manifest.persist | Should -Contain 'niconicome.db'
        Should -Invoke Start-Process -Times 0 -Exactly
        Should -Invoke Stop-Process -Times 0 -Exactly
    }

    It 'preserves an existing persisted database and rejects a directory in its place' {
        [IO.File]::WriteAllText($savedDb, 'database contents')
        & $preInstall
        Test-Path -LiteralPath $db | Should -BeFalse
        [IO.File]::ReadAllText($savedDb) | Should -Be 'database contents'
        Remove-Item -LiteralPath $savedDb
        $null = [IO.Directory]::CreateDirectory($savedDb)
        { & $preInstall } | Should -Throw '*is a directory*'
        Test-Path -LiteralPath $savedDb -PathType Container | Should -BeTrue
    }

    It 'stops cleanup when a restored database diverges or a journal remains' {
        [IO.File]::WriteAllText($db, 'initial database')
        [IO.File]::WriteAllText($savedDb, 'initial database')
        { & $preUninstall } | Should -Not -Throw
        $journal = Join-Path $dir 'niconicome-log.db'
        [IO.File]::WriteAllText($journal, 'pending data')
        { & $preUninstall } | Should -Throw '*pending database journal*'
        Remove-Item -LiteralPath $journal
        [IO.File]::WriteAllText($db, 'restored database')
        { & $preUninstall } | Should -Throw '*differs from Scoop persist*'
        [IO.File]::ReadAllText($db) | Should -Be 'restored database'
        [IO.File]::ReadAllText($savedDb) | Should -Be 'initial database'
    }

    It 'keeps prerelease migration opt-in' {
        $manifest.checkver | Should -BeNullOrEmpty
        $manifest.autoupdate | Should -BeNullOrEmpty
    }

    It 'persists downloads and backups and documents migration from the saved manifest' {
        $manifest.persist | Should -Contain 'downloaded'
        $manifest.persist | Should -Contain 'backups'
        $manifest.notes -join ' ' | Should -Match 'outside Scoop'
        $manifest.notes -join ' ' | Should -Match 'existing installed manifest'
    }

    It 'keeps downloads and backups after Scoop unlinks and removes the app directory' -Skip:$skipWindowsHooks {
        . (Join-Path $env:SCOOP_HOME 'lib/core.ps1')
        . (Join-Path $env:SCOOP_HOME 'lib/install.ps1')
        $dir = Join-Path $root 'app'
        $persist_dir = Join-Path $root 'persist'
        $null = [IO.Directory]::CreateDirectory($dir)
        & $preInstall

        $folders = 'downloaded', 'backups'
        foreach ($name in $folders) {
            $source = Join-Path $dir $name
            $null = [IO.Directory]::CreateDirectory($source)
            [IO.File]::WriteAllText((Join-Path $source 'fixture.txt'), $name)
        }
        persist_data $manifest $dir $persist_dir
        foreach ($name in $folders) {
            (Get-Item -LiteralPath (Join-Path $dir $name)).LinkType | Should -Be 'Junction'
        }

        unlink_persist_data $manifest $dir
        foreach ($name in $folders) {
            Test-Path -LiteralPath (Join-Path $dir $name) | Should -BeFalse
        }
        Remove-Item -LiteralPath $dir -Recurse
        foreach ($name in $folders) {
            Get-Content -LiteralPath (Join-Path $persist_dir "$name/fixture.txt") | Should -Be $name
        }
    }
}

Describe 'Windows Installer inventory API' -Skip:$skipWindowsHooks {
    It 'returns a readable empty related-product list for an unused upgrade code' {
        $installer = New-Object -ComObject WindowsInstaller.Installer -ErrorAction Stop
        $upgradeCode = [guid]::NewGuid().ToString('B')
        $products = $installer.RelatedProducts($upgradeCode)
        $products.Count | Should -Be 0
    }
}

Describe 'VirtualBox installer and removal' -Skip:$skipWindowsHooks {
    BeforeAll {
        $manifest = Read-BucketManifest 'virtualbox'
        $version = $manifest.version
        $install = [scriptblock]::Create($manifest.installer.script -join "`n")
        $uninstall = [scriptblock]::Create($manifest.uninstaller.script -join "`n")
        function abort($message) { throw $message }

        function New-MsiInventory([int]$Before, [int]$After, [string]$RegisteredVersion) {
            $probe = [pscustomobject]@{ Before = $Before; After = $After; RegisteredVersion = $RegisteredVersion; Calls = 0 }
            $probe | Add-Member ScriptMethod RelatedProducts {
                param($UpgradeCode)
                if ($UpgradeCode -ne '{C4BAD770-BFE8-4D2C-A592-693028A7215B}') { throw 'Unexpected MSI family' }
                $this.Calls++
                $count = if ($this.Calls -eq 1) { $this.Before } else { $this.After }
                $products = [pscustomobject]@{ Count = $count }
                $products | Add-Member ScriptMethod Item { '{D726D65F-25B7-436D-85D5-41310BA0E8EA}' }
                $products
            }
            $probe | Add-Member ScriptMethod ProductInfo { $this.RegisteredVersion }
            $probe
        }
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $dir = Join-Path $root 'folder [with spaces]; and ampersand &'
        $null = [IO.Directory]::CreateDirectory($dir)
        Mock New-Object { $msiInventory } -ParameterFilter { $ComObject -eq 'WindowsInstaller.Installer' }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
    }

    It 'installs to the protected default path and creates a CLI shim in Scoop' {
        $msiInventory = New-MsiInventory 0 1 $version
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -like '*\Oracle\VirtualBox\VBoxManage.exe' }
        & $install
        $expectedSetup = Join-Path $dir 'VBoxSetup.exe'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq $expectedSetup -and $Verb -eq 'RunAs' -and $Wait -and
            ($ArgumentList -join ' ') -eq '--msiparams "VBOX_START=0 VBOX_INSTALLSTARTMENUENTRIES=1 REBOOT=ReallySuppress" --silent'
        }
        $manifest.bin | Should -Be 'VBoxManage.ps1'
        Test-Path -LiteralPath (Join-Path $dir $manifest.bin) -PathType Leaf | Should -BeTrue
        $target = Get-Content -LiteralPath (Join-Path $dir 'vbox-manage-path.txt')
        $target | Should -Match '\\Oracle\\VirtualBox\\VBoxManage\.exe$'
        $target.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase) | Should -BeFalse
    }

    It 'leaves pre-existing Oracle installs alone and checks failure and MSI registration' {
        $msiInventory = New-MsiInventory 1 1 $version
        { & $install } | Should -Throw '*existing Oracle VirtualBox installation*'
        Should -Invoke Start-Process -Times 0 -Exactly

        $msiInventory = New-MsiInventory 0 0 $version
        { & $install } | Should -Throw '*Expected Oracle VirtualBox MSI registration*'

        $msiInventory = New-MsiInventory 0 1 $version
        Mock Start-Process { [pscustomobject]@{ ExitCode = 1603 } }
        { & $install } | Should -Throw '*exit code 1603*'
        Test-Path -LiteralPath (Join-Path $dir $manifest.bin) | Should -BeFalse
    }

    It 'blocks Scoop removal based on registration even when the executable is missing' {
        $msiInventory = New-MsiInventory 1 1 $version
        { & $uninstall } | Should -Throw '*Windows Installed apps*'
        $msiInventory = New-MsiInventory 0 0 $version
        { & $uninstall } | Should -Not -Throw
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'propagates an MSI inventory error before changing Scoop state' {
        Mock New-Object { throw 'MSI inventory unavailable' } -ParameterFilter { $ComObject -eq 'WindowsInstaller.Installer' }
        { & $install } | Should -Throw '*inventory unavailable*'
        { & $uninstall } | Should -Throw '*inventory unavailable*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}
