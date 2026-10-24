# Run this from repository root AFTER setup. The Godot executable must be on PATH,
# or pass its full path as: .\run_demo.ps1 -GodotExe 'C:\path\to\Godot.exe'
param([string]$GodotExe = 'godot')
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path $python)) {
    throw 'Missing .venv. Follow README.md setup instructions first.'
}
if (-not (Test-Path (Join-Path $PSScriptRoot 'backend\models\hand_landmarker.task'))) {
    throw 'Missing MediaPipe model. Run: python -m backend.download_model'
}
$tracker = $null
try {
    $tracker = Start-Process -FilePath $python -ArgumentList '-m', 'backend.tracker' -WorkingDirectory $PSScriptRoot -PassThru
    & $GodotExe --path (Join-Path $PSScriptRoot 'frontend') 2>$null
} finally {
    if ($null -ne $tracker -and -not $tracker.HasExited) {
        Stop-Process -Id $tracker.Id -ErrorAction SilentlyContinue
    }
}
