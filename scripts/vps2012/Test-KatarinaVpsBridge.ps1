param([string]$RepoRoot = "")
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path } else { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }
function Resolve-Git {
  $cmd = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = @((Join-Path $env:ProgramFiles "Git\cmd\git.exe"),(Join-Path $env:LOCALAPPDATA "Programs\Git\cmd\git.exe"))
  $pf86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
  if ($pf86) { $candidates += (Join-Path $pf86 "Git\cmd\git.exe") }
  foreach ($candidate in $candidates) { if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate } }
  return $null
}
function Run-Git { param([string]$Git,[string[]]$Args,[string]$WorkingDirectory) $output = & $Git -C $WorkingDirectory @Args 2>&1; return [pscustomobject]@{Code=$LASTEXITCODE;Text=($output -join [Environment]::NewLine)} }
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ".git"))) { throw "This must be a Git clone, not a ZIP copy." }
$git = Resolve-Git
if (-not $git) { throw "git.exe not found. Install Git for Windows first." }
$origin = Run-Git $git @("remote","get-url","origin") $RepoRoot
if ($origin.Code -ne 0) { throw "origin remote is missing: $($origin.Text)" }
$fetch = Run-Git $git @("fetch","origin","vps-reports:refs/remotes/origin/vps-reports") $RepoRoot
if ($fetch.Code -ne 0) { throw "Cannot fetch vps-reports: $($fetch.Text)" }
$sourceHead = (Run-Git $git @("rev-parse","HEAD") $RepoRoot).Text.Trim()
$sourceBranch = (Run-Git $git @("rev-parse","--abbrev-ref","HEAD") $RepoRoot).Text.Trim()
$runId = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss")
$temp = Join-Path $env:TEMP ("KatarinaVpsProbe-" + [Guid]::NewGuid().ToString("N"))
try {
  $wt = Run-Git $git @("worktree","add","--detach",$temp,"origin/vps-reports") $RepoRoot
  if ($wt.Code -ne 0) { throw "Unable to create report worktree: $($wt.Text)" }
  $dest = Join-Path $temp "vps_bridge\reports"
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  $report = [ordered]@{schema_version=1;proof_type="KATARINA_VPS_CONNECTION";run_id=$runId;generated_utc=[DateTime]::UtcNow.ToString("o");computer_name=$env:COMPUTERNAME;os=[Environment]::OSVersion.VersionString;powershell_version=$PSVersionTable.PSVersion.ToString();source_head=$sourceHead;source_branch=$sourceBranch;control_branch="vps-control";report_branch="vps-reports";live_risk_ready=$false;live_execution_enabled=$false;result="PASS_VPS_GITHUB_HANDSHAKE"}
  ($report | ConvertTo-Json -Depth 6) | Out-File -LiteralPath (Join-Path $dest "connection.json") -Encoding utf8
  $add = Run-Git $git @("add","vps_bridge/reports/connection.json") $temp
  if ($add.Code -ne 0) { throw "git add failed: $($add.Text)" }
  $commit = & $git -C $temp -c user.name="KATARINA VPS" -c user.email="katarina-vps@local.invalid" commit -m ("vps-handshake: " + $runId) 2>&1
  if ($LASTEXITCODE -ne 0) { throw "git commit failed: $($commit -join [Environment]::NewLine)" }
  $push = & $git -C $temp push origin HEAD:refs/heads/vps-reports 2>&1
  if ($LASTEXITCODE -ne 0) { throw "git push failed: $($push -join [Environment]::NewLine)" }
  Write-Host "PASS_VPS_GITHUB_HANDSHAKE" -ForegroundColor Green
  Write-Host "VPS -> GitHub vps-reports berhasil."
  Write-Host "Sekarang kembali ke ChatGPT dan bilang: cek koneksi VPS."
} finally {
  try { & $git -C $RepoRoot worktree remove --force $temp 2>$null | Out-Null } catch {}
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}
