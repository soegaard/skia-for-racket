# Explicit Windows x64 installer; no administrator, dotnet, or native build.
param(
  [string]$Racket = $(if ($env:RACKET) { $env:RACKET } else { 'racket' }),
  [string]$Python = $(if ($env:PYTHON) { $env:PYTHON } else { 'python' }),
  [ValidateSet('both','skia','harfbuzz')][string]$Library = 'both',
  [string]$Root = '',
  [ValidateSet('user','installation')][string]$Scope = 'user',
  [switch]$Remove,
  [string]$FromDirectory = '',
  [string]$SkiaArchive = '',
  [string]$HarfBuzzArchive = ''
)
$ErrorActionPreference = 'Stop'
$arguments = @((Join-Path $PSScriptRoot 'install-native-windows.py'), '--racket', $Racket, '--library', $Library)
if ($Root) { $arguments += @('--root', $Root) }
if ($Scope -ne 'user') { $arguments += @('--scope', $Scope) }
if ($Remove) { $arguments += '--remove' }
if ($FromDirectory) { $arguments += @('--from-directory', $FromDirectory) }
if ($SkiaArchive) { $arguments += @('--skia-archive', $SkiaArchive) }
if ($HarfBuzzArchive) { $arguments += @('--harfbuzz-archive', $HarfBuzzArchive) }
& $Python @arguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
