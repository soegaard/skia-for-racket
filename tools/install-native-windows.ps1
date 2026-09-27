# Explicit Windows x64 installer; no administrator, dotnet, or native build.
param(
  [string]$Racket = $(if ($env:RACKET) { $env:RACKET } else { 'racket' }),
  [string]$Python = $(if ($env:PYTHON) { $env:PYTHON } else { 'python' }),
  [ValidateSet('both','skia','harfbuzz')][string]$Library = 'both',
  [string]$SkiaArchive = '',
  [string]$HarfBuzzArchive = ''
)
$ErrorActionPreference = 'Stop'
$arguments = @((Join-Path $PSScriptRoot 'install-native-windows.py'), '--racket', $Racket, '--library', $Library)
if ($SkiaArchive) { $arguments += @('--skia-archive', $SkiaArchive) }
if ($HarfBuzzArchive) { $arguments += @('--harfbuzz-archive', $HarfBuzzArchive) }
& $Python @arguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
