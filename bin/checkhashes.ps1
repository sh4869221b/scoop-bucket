#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Convert-Path (scoop prefix scoop) }
$script = Join-Path $env:SCOOP_HOME 'bin/checkhashes.ps1'
$dir = Join-Path $PSScriptRoot '../bucket'
& $script -Dir $dir @Args
