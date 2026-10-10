param(
  [string]$Root = "C:\\KatarinaVPSControl",
  [string]$KatarinaRoot = "C:\\KatarinaGitBridge",
  [switch]$Once
)
$ErrorActionPreference = "Continue"
$Repo = Join-Path $Root "repo"
$State = Join-Path $Root "state"
$Log = Join-Path $Root "agent.log"
# Only the VPS knows its local Windows Git-auth profile. Never put credentials in Git.
$GitProfilePath = Join-Path $State "git-profile.path"
if(Test-Path $GitProfilePath){
  $gp = (Get-Content $GitProfilePath -Raw).Trim()
  if($gp -match "^[A-Za-z]:\\[^\r\n]*$" -and (Test-Path $gp)){
    $env:USERPROFILE = $gp
    $env:HOMEDRIVE = $gp.Substring(0,2)
    $env:HOMEPATH = $gp.Substring(2)
  }
}
New-Item -ItemType Directory -Force -Path $State | Out-Null

function Log($m) { Add-Content -Encoding UTF8 $Log ((Get-Date).ToUniversalTime().ToString("o")+" "+$m) }
function Write-JsonFile($Path,$Object) { $Object | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $Path }
function Get-SafeStatus {
  $os=Get-WmiObject Win32_OperatingSystem; $disk=Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
  @{timestamp_utc=(Get-Date).ToUniversalTime().ToString("o");computer=$env:COMPUTERNAME;os=$os.Caption;
    free_memory_mb=[math]::Round($os.FreePhysicalMemory/1024,0);disk_c_free_gb=[math]::Round($disk.FreeSpace/1GB,2);
    agent_version="0.3.2";target="vps";connection_id="katarina-unified";pid=$PID}
}
function Invoke-Job($Job) {
  switch ($Job.action) {
    "status" { @{ok=$true;action="status";data=(Get-SafeStatus)} }
    "katarina_git_status" {
      if(!(Test-Path $KatarinaRoot)){return @{ok=$false;error="Katarina workspace not found"}}
      $o=& git -C $KatarinaRoot status --short --branch 2>&1
      @{ok=($LASTEXITCODE-eq 0);action="katarina_git_status";output=($o-join "`n")}
    }
    "katarina_fetch" {
      if(!(Test-Path $KatarinaRoot)){return @{ok=$false;error="Katarina workspace not found"}}
      $o=& git -C $KatarinaRoot fetch origin 2>&1
      @{ok=($LASTEXITCODE-eq 0);action="katarina_fetch";output=($o-join "`n")}
    }
    default { @{ok=$false;error=("Unsupported action: "+$Job.action)} }
  }
}
function Cycle {
  Set-Location $Repo
  & git pull --ff-only origin main 2>&1 | Out-Null
  $statusPath = Join-Path $Repo "status\vps.json"
  if(!(Test-Path $statusPath) -or ((Get-Date).ToUniversalTime()-(Get-Item $statusPath).LastWriteTimeUtc).TotalSeconds -ge 3600){
    Write-JsonFile $statusPath (Get-SafeStatus)
  }
  $shared = Get-Content (Join-Path $Repo "connection.json") -Raw | ConvertFrom-Json; if($shared.connection_id -ne "katarina-unified"){throw "Invalid unified connection config"}
  Get-ChildItem (Join-Path $Repo "jobs") -Filter "*.json" -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
    $f=$_; $done=Join-Path $State ($f.BaseName+".done"); if(Test-Path $done){return}
    try{$job=Get-Content $f.FullName -Raw|ConvertFrom-Json;if(($null -ne $job.target) -and ($job.target -ne "vps")){return};$result=Invoke-Job $job;$result.target="vps";$result.job_id=$f.BaseName;$result.timestamp_utc=(Get-Date).ToUniversalTime().ToString("o")}
    catch{$result=@{ok=$false;job_id=$f.BaseName;timestamp_utc=(Get-Date).ToUniversalTime().ToString("o");error=$_.Exception.Message}}
    Write-JsonFile (Join-Path $Repo ("results\"+$f.BaseName+".json")) $result
    New-Item -ItemType File -Force $done|Out-Null
  }
  & git add status results
  if(& git status --porcelain -- status results){
    & git commit -m ("agent: results "+(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")) 2>&1|Out-Null
    & git pull --rebase origin main 2>&1|Out-Null
    if($LASTEXITCODE -ne 0){Log "git pull/rebase failed";return}
    & git push origin main 2>&1|Out-Null
    if($LASTEXITCODE -ne 0){Log "git push failed (check local auth profile)"}
  }
}
Log "agent start v0.3.2 pid=$PID"
do { try { Cycle } catch { Log ("cycle error: "+$_.Exception.Message) }; if(!$Once){Start-Sleep -Seconds 180} } while(!$Once)
Log "agent exit"
