#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
# A missing ref is a documented Git result, even when the caller opts in to native errors.
$PSNativeCommandUseErrorActionPreference = $false

# A successful push records "update by push" in the local remote-tracking
# reflog. Fetching a concurrent writer's commit does not create that entry.
# Both publishing paths of the pinned action leave HEAD at the submitted tip.
$publishedRef = git symbolic-ref --quiet HEAD
if ($LASTEXITCODE -ne 0 -or $publishedRef -cnotmatch '^refs/heads/(?<branch>.+)$') {
    throw 'The maintenance checkout is not on a branch.'
}
$branch = $Matches.branch
$revision = git rev-parse --verify HEAD
if ($LASTEXITCODE -ne 0 -or $revision -cnotmatch '^[0-9a-f]{40}$') { throw 'Cannot resolve the maintenance checkout commit.' }

$trackingRef = "refs/remotes/origin/$branch"
git show-ref --verify --quiet $trackingRef
if ($LASTEXITCODE -eq 1) { exit 0 }
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the remote-tracking ref.' }
$lastUpdate = git reflog show -1 '--format=%H %gs' $trackingRef
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the remote-tracking reflog.' }

if ($lastUpdate -ceq "$revision update by push") {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "revision=$revision", "published_ref=$publishedRef"
}
