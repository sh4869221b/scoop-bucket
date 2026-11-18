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
    @{ Name = 'virtualbox'; Expected = '64bit' }
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

    It 'finds a PPSSPP build with a Windows ZIP and reconstructs its matching downloads' {
        $manifest = Read-BucketManifest 'ppsspp-dev'
        $manifest.checkver.url | Should -Be 'https://builds.ppsspp.org/meta/history-20.json'
        $builds = '[{"description":"v1.20.4-4975-g9abcde1234ff","builds":{"Windows":[]}},{"description":"v1.20.4-4974-g154d52379a3f","builds":{"Windows":["ppsspp_win_v1.20.4-4974-g154d52379a3f.zip"]}}]'
        $match = [regex]::Match($builds, $manifest.checkver.regex)
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
}

Describe 'VirtualBox installer and removal' {
    BeforeAll {
        $manifest = Read-BucketManifest 'virtualbox'
        $install = [scriptblock]::Create($manifest.installer.script -join "`n")
        $uninstall = [scriptblock]::Create($manifest.uninstaller.script -join "`n")
        function abort($message) { throw $message }
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $dir = Join-Path $root 'folder [with spaces]; and ampersand &'
        $null = [IO.Directory]::CreateDirectory($dir)
        $installedExe = Join-Path $dir 'VirtualBox.exe'
    }

    It 'passes the installer path directly and quotes the Oracle MSI argument' {
        [IO.File]::WriteAllText($installedExe, 'test fixture')
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        & $install
        $expectedSetup = Join-Path $dir 'VBoxSetup.exe'
        $expectedArgs = '--msiparams "INSTALLDIR=""{0}"" VBOX_START=0 REBOOT=ReallySuppress" --silent' -f $dir
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq $expectedSetup -and ($ArgumentList -join ' ') -eq $expectedArgs -and $Verb -eq 'RunAs' -and $Wait
        }
    }

    It 'reports a failed installer or a missing installed application' {
        Mock Start-Process { [pscustomobject]@{ ExitCode = 1603 } }
        { & $install } | Should -Throw '*exit code 1603*'
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        { & $install } | Should -Throw '*was not installed into the Scoop directory*'
    }

    It 'blocks Scoop cleanup until the user removes the installed application' {
        Mock Start-Process { throw 'Unexpected uninstall process' }
        [IO.File]::WriteAllText($installedExe, 'test fixture')
        { & $uninstall } | Should -Throw '*Windows Installed apps*'
        Remove-Item -LiteralPath $installedExe
        { & $uninstall } | Should -Not -Throw
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}
