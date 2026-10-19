# Deploy the current main branch to Gigalixir.
#
#   powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1
#
# Pushes to the gigalixir remote (it builds and rolls out the release), streams
# the remote build log, keeps a copy in tmp\agent-logs\deploy.log and waits for
# the new release to report healthy.
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'main') { throw "Deploy from main (currently on '$branch')." }
if (git status --porcelain) { throw 'Working tree is dirty - commit or stash first.' }

New-Item -ItemType Directory -Force tmp\agent-logs | Out-Null
$log = Join-Path $root 'tmp\agent-logs\deploy.log'
$sha = (git rev-parse --short HEAD).Trim()

Write-Host "Deploying $sha to Gigalixir (log: $log)..."
# cmd merges git's stderr (the remote build log) before PowerShell sees it, so
# the stream is plain text; PowerShell alone wraps stderr into error records.
cmd /c "git push gigalixir main 2>&1" | Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) { throw "git push gigalixir failed - see $log" }

$gigalixir = Join-Path $env:LOCALAPPDATA 'Programs\gigalixir\gigalixir.exe'
if (-not (Test-Path $gigalixir)) { $gigalixir = 'gigalixir' }

Write-Host 'Waiting for the release to become healthy...'
Start-Sleep -Seconds 45
& $gigalixir ps -a psc

$url = 'https://psc.gigalixirapp.com/users/log-in'
$response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
Write-Host "$url -> $($response.StatusCode)"
