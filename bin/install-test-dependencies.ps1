#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$version = '6.2.0'
if (Get-Module Pester -ListAvailable | Where-Object { $_.Version -eq [version]$version }) {
    Write-Host "Pester $version is already installed."
    return
}

# Hosted Windows images do not always register PSGallery in both editions.
$repository = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
if (!$repository) {
    Register-PSRepository -Default -ErrorAction Stop
    $repository = Get-PSRepository -Name PSGallery -ErrorAction Stop
}
if ($repository.SourceLocation.TrimEnd('/') -ne 'https://www.powershellgallery.com/api/v2') {
    throw 'PSGallery does not point to the official PowerShell Gallery.'
}

for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        Install-Module Pester -RequiredVersion $version -Repository PSGallery -Scope CurrentUser -Force -SkipPublisherCheck -ErrorAction Stop
        Import-Module Pester -RequiredVersion $version -ErrorAction Stop
        break
    } catch {
        if ($attempt -eq 3) { throw }
        Write-Warning "Pester installation attempt $attempt failed; retrying: $_"
        Start-Sleep -Seconds (5 * $attempt)
    }
}
