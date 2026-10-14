BeforeDiscovery {
    $manifestFiles = @(Get-ChildItem (Join-Path $PSScriptRoot '../../bucket') -Filter '*.json' -File | Sort-Object Name)
    if ($manifestFiles.Count -eq 0) { throw 'The bucket must contain manifests.' }
    $cases = @($manifestFiles | ForEach-Object { @{ Name = $_.BaseName; Path = $_.FullName } })
}

Describe 'Manifest <Name>' -ForEach $cases {
    BeforeAll {
        $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
        if (!$env:SCOOP_HOME) { throw 'Set SCOOP_HOME to a Scoop checkout before running tests.' }
        $schema = Join-Path $env:SCOOP_HOME 'schema.json'
        $validatorDll = Join-Path $env:SCOOP_HOME 'supporting/validator/bin/Scoop.Validator.dll'
        if (!(Test-Path $schema) -or !(Test-Path $validatorDll)) { throw 'Scoop schema or validator is missing.' }
        Add-Type -Path $validatorDll
        $validator = New-Object Scoop.Validator($schema, $true)
        $variants = @($manifest)
        if ($manifest.architecture) { $variants = @($manifest.architecture.PSObject.Properties.Value) }
    }

    It 'validates against the official Scoop JSON schema' {
        $valid = $validator.Validate($Path)
        if (!$valid) { throw $validator.ErrorsAsString }
        $validator.Errors.Count | Should -Be 0
    }

    It 'has required metadata and a valid homepage' {
        $manifest.version | Should -Not -BeNullOrEmpty
        $manifest.homepage | Should -Match '^https?://[^/\s]+'
        @($manifest.PSObject.Properties.Name) | Should -Contain 'license'
    }

    It 'pairs every architecture download with a SHA-256 hash' {
        foreach ($variant in $variants) {
            $urls = @($variant.url)
            $hashes = @($variant.hash)
            $urls.Count | Should -BeGreaterThan 0
            $hashes.Count | Should -Be $urls.Count
            foreach ($url in $urls) { $url | Should -Match '^https?://[^/\s]+' }
            foreach ($hash in $hashes) { $hash | Should -Match '^(sha256:)?[a-fA-F0-9]{64}$' }
        }
    }

    It 'uses relative executable paths for declared shims' {
        foreach ($variant in @($manifest) + $variants) {
            foreach ($bin in @($variant.bin)) {
                if (!$bin) { continue } # Existing GUI manifests use an empty bin.
                $target = if ($bin -is [array]) { $bin[0] } else { $bin }
                $target | Should -Not -Match '^(?:[a-zA-Z]:|[/\\])|(?:^|[/\\])\.\.(?:[/\\]|$)'
                $target | Should -Not -BeNullOrEmpty
            }
        }
    }

    It 'keeps checkver and autoupdate definitions consistent' {
        if ($manifest.autoupdate) {
            $manifest.checkver | Should -Not -BeNullOrEmpty
            if ($manifest.autoupdate.architecture) {
                $actual = @($manifest.architecture.PSObject.Properties.Name | Sort-Object) -join ','
                $updated = @($manifest.autoupdate.architecture.PSObject.Properties.Name | Sort-Object) -join ','
                $updated | Should -Be $actual
                foreach ($variant in $manifest.autoupdate.architecture.PSObject.Properties.Value) {
                    @($variant.url).Count | Should -BeGreaterThan 0
                    foreach ($url in @($variant.url)) { $url | Should -Match '^https?://' }
                }
            } else {
                @($manifest.autoupdate.url).Count | Should -BeGreaterThan 0
                foreach ($url in @($manifest.autoupdate.url)) { $url | Should -Match '^https?://' }
            }
        }
        if ($manifest.checkver -eq 'github') { $manifest.homepage | Should -Match '^https://github.com/[^/]+/[^/]+' }
        if ($manifest.checkver.regex) { { [regex]::new($manifest.checkver.regex) } | Should -Not -Throw }
    }
}

Describe 'Nico CLI contract <Name>' -ForEach @(
    @{ Name = 'go-nico-list'; Architectures = '32bit,64bit,arm64'; ChecksumFile = 'go-nico-list_$version_checksums.txt' }
    @{ Name = 'zig-nico-list'; Architectures = '64bit'; ChecksumFile = 'SHA256SUMS' }
) {
    BeforeAll {
        $manifest = Get-Content (Join-Path $PSScriptRoot "../../bucket/$Name.json") -Raw | ConvertFrom-Json
        $releaseRoot = "https://github.com/sh4869221b/$Name/releases/download/v"
    }
    It 'declares the supported architectures, CLI and upstream repository' {
        (@($manifest.architecture.PSObject.Properties.Name | Sort-Object) -join ',') | Should -Be $Architectures
        $manifest.bin | Should -Be "$Name.exe"
        $manifest.homepage | Should -Be "https://github.com/sh4869221b/$Name"
        $manifest.license | Should -Be 'MIT'
        $manifest.description | Should -Not -BeNullOrEmpty
        $manifest.checkver | Should -Be 'github'
    }
    It 'reconstructs current release URLs and extract directory without running checkver' {
        foreach ($arch in $manifest.architecture.PSObject.Properties.Name) {
            $url = $manifest.architecture.$arch.url
            $url | Should -BeLike "$releaseRoot*"
            $manifest.autoupdate.architecture.$arch.url.Replace('$version', $manifest.version) | Should -Be $url
        }
        if ($manifest.extract_dir) {
            $manifest.autoupdate.extract_dir.Replace('$version', $manifest.version) | Should -Be $manifest.extract_dir
        }
        $manifest.autoupdate.hash.url | Should -Be ($releaseRoot + '$version/' + $ChecksumFile)
    }
    It 'has no installer hooks, dependencies or persistence that expand smoke-test scope' {
        foreach ($property in @('pre_install', 'post_install', 'installer', 'uninstaller', 'pre_uninstall', 'post_uninstall', 'depends', 'persist')) {
            $manifest.$property | Should -BeNullOrEmpty
        }
    }
}
