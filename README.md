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
suites fail the job. NUnit XML reports are uploaded for 14 days. Dependency setup verifies the official
PowerShell Gallery, installs the exact Pester version and retries transient
download failures.

Run the same tests locally from either supported PowerShell edition:

```powershell
./bin/install-test-dependencies.ps1
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

After static tests pass for a default-branch revision, a single disposable GitHub-hosted
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
Pushes made with the Actions `GITHUB_TOKEN` skip the usual push workflow.
Excavator and the issue handler take the submitted SHA from Git's local
`update by push` record, including a successfully published hash-fix PR branch.
Tests check out that SHA with read-only access. A separate job sets the
`Tests / maintenance` commit status on the submitted SHA and links the run.
Maintenance and ordinary push runs use independent concurrency groups.
Tests never run `checkver -Update` or rewrite manifests.

### Package maintenance

- VirtualBox installs to Oracle's protected Program Files location. Oracle provides
  the Start menu entry and Scoop provides the native `VBoxManage.exe` shim. Before a
  Scoop update or uninstall, close VirtualBox, back up or shut down your VMs as
  appropriate, and remove the Oracle VirtualBox installation that Scoop recorded through
  Windows Installed apps. Do this first for older bucket installs too.
  Oracle classifies Windows 11 ARM64 host support as experimental.

#### Moving data from an older Niconicome install

Scoop uses the saved manifest for update and uninstall hooks. Uninstall and
cleanup can remove old version directories that still hold the only copy of
your data. Complete this backup before updating, uninstalling, or running
`scoop cleanup`.

1. Close Niconicome normally. Use `scoop prefix Niconicome` to locate your Scoop
   root and inspect **every** directory under `apps/Niconicome`, including
   older versions and renamed directories such as `_0.11.0.old` and
   `_0.11.0.old.1`. To include hidden directories, run
   `Get-ChildItem -LiteralPath '<Scoop root>\apps\Niconicome' -Directory -Force`.
   If `current` is a junction, check its target and include that target if it
   isn't already in the list. Check both Scoop roots if you have local and global
   installs.
2. In a new backup location outside Scoop, make a separate folder for each source
   directory. Copy `downloaded`, `backups`, `chrome`, `niconicome.db`, and
   `niconicome-log.db` wherever they exist, including saved `.original` copies.
   Back up `persist/Niconicome` and any custom download locations separately.
   Keep each database beside its own journal. Verify the copied files are
   readable and compare file counts and sizes with every source before proceeding.
3. Install or reinstall with the updated manifest. Before opening Niconicome,
   restore missing files to the new persisted `downloaded`, `backups`, and
   `chrome` folders. Keep conflicting copies separate until you can choose the
   correct one. If the databases differ or a journal is present, resolve which
   database and journal pair to restore before launching. Keep the independent
   backup until you've checked the library, downloads, backups and custom styles.

Niconicome remains at 0.11.0 while prerelease migration is unverified.

### Comment verification security

`/verify` on a pull request checks JSON syntax for changed manifests at the
reported head commit. Results appear in the **Commented Pull Request** Actions
run, not as comments or labels. This read-only workflow fetches manifests as data;
it never checks out PR code or runs manifest `checkver`/installation scripts.
Use the **Tests** workflow for full schema and unit validation. Authorized
maintainers can rerun those checks through GitHub's Actions UI. A push during
comment verification fails the check and requires a new `/verify` comment.

Some older GUI manifests have empty optional `bin` values, and two legacy
manifests have empty license strings accepted by Scoop's current schema. The
suite preserves those existing manifests; the Nico manifests require MIT
license metadata, nonempty descriptions and their exact supported architectures.

## Upstream references

- [Scoop BucketTemplate](https://github.com/ScoopInstaller/BucketTemplate)
- [Scoop v0.6.0](https://github.com/ScoopInstaller/Scoop/releases/tag/v0.6.0)
- [Pester 6.2.0](https://github.com/pester/Pester/releases/tag/6.2.0)
- [Scoop GitHub Actions v3.0.0](https://github.com/ScoopInstaller/GithubActions/releases/tag/v3.0.0)
