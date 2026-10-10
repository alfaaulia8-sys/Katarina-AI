param(
    [Parameter(Mandatory=$true)][string]$MetaEditorPath,
    [Parameter(Mandatory=$true)][string]$DependencyInclude,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
if ($TimeoutSeconds -lt 10 -or $TimeoutSeconds -gt 600) { throw 'Invalid compile timeout' }
$MetaEditorPath = (Resolve-Path -LiteralPath $MetaEditorPath).Path
$DependencyInclude = (Resolve-Path -LiteralPath $DependencyInclude).Path
if ([IO.Path]::GetFileName($MetaEditorPath) -ine 'metaeditor64.exe') { throw 'Expected MetaEditor64.exe' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$run = Join-Path $OutputRoot ([Guid]::NewGuid().ToString('N'))
$mql = Join-Path $run 'MQL5'
New-Item -ItemType Directory -Path "$mql\Include", "$mql\Experts", "$mql\Scripts", "$run\logs" -Force | Out-Null
# Compile in a fresh tree: existing terminal programs and accounts are untouched.
Copy-Item "$repo\mt5\Include\Katarina" "$mql\Include\Katarina" -Recurse
foreach ($name in @('Zmq', 'Mql', 'Arrays')) {
    $source = Join-Path $DependencyInclude $name
    if (!(Test-Path -LiteralPath $source -PathType Container)) { throw "Missing include dependency: $name" }
    Copy-Item -LiteralPath $source -Destination "$mql\Include\$name" -Recurse
}
$targets = @()
foreach ($mapping in @(@('Experts','Experts'), @('Tests','Scripts'))) {
    foreach ($source in @(Get-ChildItem "$repo\mt5\$($mapping[0])" -Filter '*.mq5' -File | Sort-Object Name)) {
        $destination = Join-Path "$mql\$($mapping[1])" $source.Name
        Copy-Item -LiteralPath $source.FullName -Destination $destination
        $targets += [pscustomobject]@{source=$source.FullName; staged=$destination; name=$source.BaseName}
    }
}
if ($targets.Count -eq 0) { throw 'No compile targets' }
$results = @()
foreach ($target in $targets) {
    $log = Join-Path "$run\logs" ($target.name + '.log')
    $artifact = [IO.Path]::ChangeExtension($target.staged, '.ex5')
    $started = [DateTime]::UtcNow
    $arguments = @('/compile:"' + $target.staged + '"', '/inc:"' + $mql + '"', '/log:"' + $log + '"')
    $process = Start-Process -FilePath $MetaEditorPath -ArgumentList $arguments -PassThru
    $timeout = !$process.WaitForExit($TimeoutSeconds * 1000)
    if ($timeout) { Stop-Process -Id $process.Id -ErrorAction SilentlyContinue }
    $errors = $null; $warnings = $null; $hash = $null
    if (Test-Path -LiteralPath $log) {
        $raw = [IO.File]::ReadAllBytes($log)
        $text = [Text.Encoding]::Unicode.GetString($raw)
        if ($text -notmatch 'Result:') { $text = [Text.Encoding]::UTF8.GetString($raw) }
        $summaries = [regex]::Matches($text, 'Result:\s*(\d+) errors?,\s*(\d+) warnings?')
        if ($summaries.Count -gt 0) {
            $summary = $summaries[$summaries.Count - 1]
            $errors = [int]$summary.Groups[1].Value; $warnings = [int]$summary.Groups[2].Value
        }
    }
    $fresh = $false
    if (Test-Path -LiteralPath $artifact) {
        $file = Get-Item -LiteralPath $artifact
        $fresh = $file.Length -gt 0 -and $file.LastWriteTimeUtc -ge $started.AddSeconds(-2)
        $hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
    }
    $passed = !$timeout -and $null -ne $errors -and $errors -eq 0 -and $warnings -eq 0 -and $fresh
    $results += [ordered]@{target=$target.name; passed=$passed; errors=$errors; warnings=$warnings; timed_out=$timeout; source_sha256=(Get-FileHash $target.source -Algorithm SHA256).Hash; artifact_sha256=$hash}
    Write-Host "$($target.name): passed=$passed errors=$errors warnings=$warnings"
}
$manifest = @(Get-ChildItem "$mql\Include" -Recurse -File | Sort-Object FullName | ForEach-Object {
    [ordered]@{path=$_.FullName.Substring($mql.Length+1).Replace('\','/'); sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}
})
$passed = @($results | Where-Object { !$_.passed }).Count -eq 0
$evidence = [ordered]@{
    schema_version=1; generated_utc=[DateTime]::UtcNow.ToString('o')
    result=$(if($passed){'PASS_MQL5_BUILD'}else{'FAIL_MQL5_BUILD'})
    metaeditor_version=(Get-Item $MetaEditorPath).VersionInfo.FileVersion
    targets=$results; include_manifest=$manifest
    runtime_verified=$false; strategy_validated=$false; live_execution_enabled=$false
}
$evidence | ConvertTo-Json -Depth 7 | Set-Content "$run\build-evidence.json" -Encoding UTF8
Write-Host "Evidence: $run\build-evidence.json"
if (!$passed) { exit 2 }
