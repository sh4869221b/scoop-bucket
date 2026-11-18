#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_REF -cnotmatch '^refs/heads/(?<branch>.+)$') {
    throw 'Bucket maintenance requires a branch ref.'
}
$branch = [uri]::EscapeDataString($Matches.branch)
$revision = gh api "repos/$env:GITHUB_REPOSITORY/git/ref/heads/$branch" --jq '.object.sha'
if ($LASTEXITCODE -ne 0 -or $revision -isnot [string] -or $revision -cnotmatch '^[0-9a-f]{40}$') {
    throw 'Cannot resolve the published branch head.'
}
if ($revision -ne $env:GITHUB_SHA) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "revision=$revision"
}
