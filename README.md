# scoop-bucket

Personal [Scoop](https://scoop.sh/) bucket.

```powershell
scoop bucket add sh4869221b https://github.com/sh4869221b/scoop-bucket
scoop install sh4869221b/go-nico-list
scoop install sh4869221b/zig-nico-list
```

## Tests

CI tests **every manifest**, on Windows PowerShell 5.1 and the PowerShell 7 version
provided by `windows-latest`, with Pester **6.2.0**. It checks the official Scoop
schema, required metadata, URL/hash pairs, executable paths, architecture and
update definitions, the Nico CLI contracts, PowerShell syntax, and argument
forwarding. Empty discovery, failed discovery, failed tests, and all-skipped
suites fail the job. NUnit XML reports are uploaded for 14 days.

Run the same tests locally from either supported PowerShell edition:

```powershell
Install-Module Pester -RequiredVersion 6.2.0 -Scope CurrentUser -Repository PSGallery -Force -SkipPublisherCheck
git clone https://github.com/ScoopInstaller/Scoop.git ../scoop-core
git -C ../scoop-core checkout e6aa3b366bdee8ed138c1e0f7b85192ebdd35d0f
$env:SCOOP_HOME = (Resolve-Path ../scoop-core).Path
./bin/test.ps1
```

CI pins Scoop **v0.6.0** (including its schema and validator) for reproducibility.
Update that commit in both CI jobs together when adopting a newer Scoop release.
GitHub Actions use full commit pins with release versions recorded beside them.
The upstream Scoop initializer is intentionally not used: it installs Pester 5
and dependencies this suite does not need. Unlike the upstream changed-file-only
bucket importer, these tests validate all manifests on every run.

### Windows installation smoke tests

After static tests pass on a default-branch push or manual run, a single disposable GitHub-hosted
Windows job installs and uninstalls **Go x64, Go x86, and Zig x64**, checks Scoop's
installed version/architecture records and executable PE machine types, and runs each installed shim with
`--help`. Scoop verifies the SHA-256 hashes while downloading. Go ARM64 is
downloaded and checked for its hash, archive layout and PE architecture; it is
**not executed** on the x64 runner. No Niconico login or API requests are needed.

Only these two owner-hosted GitHub release sources are permitted by the smoke
suite. Install hooks, dependencies and persistence are rejected. These tests do
not install the other bucket packages and do not execute release binaries for
pull requests. They do not use secrets or a write token. Release downloads are
network-dependent and their failures fail CI rather than being silently skipped.

Run these via the Tests workflow on the default branch. The smoke suite rejects
local and self-hosted runners: Scoop can modify the user PATH while creating
shims, so installation checks must stay on disposable GitHub-hosted Windows.
Scoop root, config, cache and global paths are all isolated in the test directory.

### Maintenance scripts

`bin/checkver.ps1`, `checkurls.ps1`, `checkhashes.ps1`, `formatjson.ps1`,
`missing-checkver.ps1` and `auto-pr.ps1` delegate to the installed Scoop (or
`SCOOP_HOME`) with argument splatting, without evaluating argument strings.
The existing Excavator schedule and issue/PR handlers are preserved. Tests never
run `checkver -Update` or rewrite manifests.

Some older GUI manifests have empty optional `bin` values, and two legacy
manifests have empty license strings accepted by Scoop's current schema. The
suite preserves those existing manifests; the Nico manifests require MIT
license metadata, nonempty descriptions and their exact supported architectures.

## Upstream references

- [Scoop BucketTemplate](https://github.com/ScoopInstaller/BucketTemplate)
- [Scoop v0.6.0](https://github.com/ScoopInstaller/Scoop/releases/tag/v0.6.0)
- [Pester 6.2.0](https://github.com/pester/Pester/releases/tag/6.2.0)
- [Scoop GitHub Actions v3.0.0](https://github.com/ScoopInstaller/GithubActions/releases/tag/v3.0.0)
