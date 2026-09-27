param(
  [string]$Racket = $(if ($env:RACKET) { $env:RACKET } else { 'racket' }),
  [string]$Python = $(if ($env:PYTHON) { $env:PYTHON } else { 'python' }),
  [ValidateSet('required','optional','off')][string]$GpuMode = 'required'
)
$ErrorActionPreference = 'Stop'
$env:RACKET = $Racket
$env:GPU_MODE = $GpuMode
$env:PYTHONDONTWRITEBYTECODE = '1'
& $Python (Join-Path $PSScriptRoot 'validate-gpu.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
