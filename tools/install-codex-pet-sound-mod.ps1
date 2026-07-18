param(
    [string]$CodexAppDir = '',
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [string]$PetDir = '',
    [string]$TargetRoot = '',
    [string]$SoundSubdir = 'sounds',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not $TargetRoot) {
    $TargetRoot = Join-Path $CodexHome 'pet-sound-mod'
}
$marker = 'CODEX_PET_SOUND_LISTENER_V1'
$targetApp = Join-Path $TargetRoot 'codex-overlay\app'
$targetAsar = Join-Path $targetApp 'resources\app.asar'
$backupDir = Join-Path $TargetRoot 'backups'
$logsDir = Join-Path $TargetRoot 'logs'
$eventLogPath = Join-Path $logsDir 'pet-events.log'
$bridgeLogPath = Join-Path $logsDir 'sound-bridge.log'
$launcher = Join-Path $TargetRoot 'Start-Codex-Pet-Sound.ps1'
$launcherCmd = Join-Path $TargetRoot 'Start-Codex-Pet-Sound.cmd'
$updater = Join-Path $TargetRoot 'Update-Codex-Pet-Sound.ps1'
$updaterCmd = Join-Path $TargetRoot 'Update-Codex-Pet-Sound.cmd'
$bridgeSource = Join-Path $PSScriptRoot 'codex-pet-sound-bridge.ps1'
$bridgeTarget = Join-Path $TargetRoot 'tools\codex-pet-sound-bridge.ps1'
$installerSource = $PSCommandPath
$installerTarget = Join-Path $TargetRoot 'tools\install-codex-pet-sound-mod.ps1'
$configPath = Join-Path $TargetRoot 'config.json'

function Stop-WithMessage {
    param([string]$Message)
    Write-Host $Message
    exit 1
}

function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/')
    $targetFull = [System.IO.Path]::GetFullPath($TargetPath)
    if (-not $targetFull.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is not under base path: $TargetPath"
    }
    return $targetFull.Substring($baseFull.Length).TrimStart('\', '/')
}

function Resolve-CodexAppDir {
    param([string]$RequestedPath)

    if ($RequestedPath.Trim().Length -gt 0) {
        $candidate = [System.IO.Path]::GetFullPath($RequestedPath)
        if (Test-Path -LiteralPath (Join-Path $candidate 'resources\app.asar')) {
            return $candidate
        }
        Stop-WithMessage "Requested Codex app directory does not contain resources\app.asar: $candidate"
    }

    $packages = @(Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue)
    foreach ($package in $packages) {
        $candidate = Join-Path $package.InstallLocation 'app'
        if (Test-Path -LiteralPath (Join-Path $candidate 'resources\app.asar')) {
            return $candidate
        }
    }

    $windowsApps = Join-Path $env:ProgramFiles 'WindowsApps'
    $candidates = @(Get-ChildItem -LiteralPath $windowsApps -Directory -Filter 'OpenAI.Codex_*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { Join-Path $_.FullName 'app' })
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'resources\app.asar')) {
            return $candidate
        }
    }

    Stop-WithMessage "Could not locate installed Codex app. Pass -CodexAppDir explicitly."
}

function Copy-FileFallback {
    param(
        [string]$Source,
        [string]$Destination
    )

    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    try {
        New-Item -ItemType HardLink -Path $Destination -Target $Source -Force -ErrorAction Stop | Out-Null
        $script:fileLinkCount += 1
    } catch {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        $script:fileCopyCount += 1
    }
}

function Add-DirectoryReference {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (Test-Path -LiteralPath $Destination) {
        return
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    try {
        New-Item -ItemType Junction -Path $Destination -Target $Source -Force -ErrorAction Stop | Out-Null
        $script:junctionCount += 1
    } catch {
        Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
        $script:directoryCopyCount += 1
    }
}

$CodexAppDir = Resolve-CodexAppDir -RequestedPath $CodexAppDir
$sourceAsar = Join-Path $CodexAppDir 'resources\app.asar'

if (-not (Test-Path -LiteralPath $CodexAppDir)) {
    Stop-WithMessage "Codex app directory not found: $CodexAppDir"
}
if (-not (Test-Path -LiteralPath $sourceAsar)) {
    Stop-WithMessage "Codex app.asar not found: $sourceAsar"
}
if (-not (Test-Path -LiteralPath $CodexHome)) {
    Stop-WithMessage "Codex home directory not found: $CodexHome"
}
if ($PetDir -and -not (Test-Path -LiteralPath $PetDir)) {
    Stop-WithMessage "Pet directory not found: $PetDir"
}
if ($PetDir -and -not (Test-Path -LiteralPath (Join-Path $PetDir $SoundSubdir))) {
    New-Item -ItemType Directory -Path (Join-Path $PetDir $SoundSubdir) -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $bridgeSource)) {
    Stop-WithMessage "Bridge script not found: $bridgeSource"
}

$npx = Get-Command npx.cmd -ErrorAction SilentlyContinue
if (-not $npx) {
    Stop-WithMessage "npx.cmd was not found. Install Node.js/npm or run from a shell where npx.cmd is available."
}

if ((Test-Path -LiteralPath $targetApp) -and -not $Force) {
    Stop-WithMessage "Target already exists: $targetApp. Re-run with -Force after official Codex updates or when refreshing this mod."
}

New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $bridgeTarget) -Force | Out-Null
if ([System.IO.Path]::GetFullPath($bridgeSource) -ine [System.IO.Path]::GetFullPath($bridgeTarget)) {
    Copy-Item -LiteralPath $bridgeSource -Destination $bridgeTarget -Force
}
if ([System.IO.Path]::GetFullPath($installerSource) -ine [System.IO.Path]::GetFullPath($installerTarget)) {
    Copy-Item -LiteralPath $installerSource -Destination $installerTarget -Force
}

if (Test-Path -LiteralPath $targetApp) {
    $archiveName = "app.previous.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $archivePath = Join-Path (Split-Path -Parent $targetApp) $archiveName
    Move-Item -LiteralPath $targetApp -Destination $archivePath
    Write-Host "Moved previous overlay app to: $archivePath"
}

Write-Host "Creating Codex mod overlay..."
New-Item -ItemType Directory -Path $targetApp -Force | Out-Null
$fileLinkCount = 0
$fileCopyCount = 0
$junctionCount = 0
$directoryCopyCount = 0

Get-ChildItem -LiteralPath $CodexAppDir -File -Force | ForEach-Object {
    Copy-FileFallback -Source $_.FullName -Destination (Join-Path $targetApp $_.Name)
}

Get-ChildItem -LiteralPath $CodexAppDir -Directory -Force | Where-Object { $_.Name -ne 'resources' } | ForEach-Object {
    Add-DirectoryReference -Source $_.FullName -Destination (Join-Path $targetApp $_.Name)
}

$sourceResources = Join-Path $CodexAppDir 'resources'
$targetResources = Join-Path $targetApp 'resources'
New-Item -ItemType Directory -Path $targetResources -Force | Out-Null
Get-ChildItem -LiteralPath $sourceResources -File -Force | ForEach-Object {
    Copy-FileFallback -Source $_.FullName -Destination (Join-Path $targetResources $_.Name)
}
Get-ChildItem -LiteralPath $sourceResources -Directory -Force | ForEach-Object {
    Add-DirectoryReference -Source $_.FullName -Destination (Join-Path $targetResources $_.Name)
}
Write-Host "Overlay references: junctions=$junctionCount copiedDirs=$directoryCopyCount hardlinkedFiles=$fileLinkCount copiedFiles=$fileCopyCount"

$tempRoot = Join-Path $env:TEMP ("codex-pet-sound-asar-patch-" + [guid]::NewGuid().ToString('N'))
$extractDir = Join-Path $tempRoot 'extract'
$newAsar = Join-Path $tempRoot 'app.asar'
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

try {
    & $npx.Source --yes '@electron/asar' extract $targetAsar $extractDir
    if ($LASTEXITCODE -ne 0) { throw "asar extract failed with exit code $LASTEXITCODE" }

    $mainCandidates = Get-ChildItem -LiteralPath (Join-Path $extractDir '.vite\build') -Filter 'main-*.js' -File |
        Where-Object {
            (Get-Content -LiteralPath $_.FullName -Raw).Contains('async handleMessage(e,t){if(PN(t))')
        }
    if ($mainCandidates.Count -ne 1) {
        throw "Expected exactly one patchable main-*.js file, found $($mainCandidates.Count). This Codex version may need installer updates."
    }
    $main = $mainCandidates[0].FullName

    $mainText = Get-Content -LiteralPath $main -Raw
    if (-not $mainText.Contains($marker)) {
        $insertBefore = 'var $X=r.a(`electron-message-handler`)'
        $listenerTemplate = @'
var __CODEX_PET_MARKER__=(()=>{let e=0,n=null,r=`__CODEX_PET_EVENT_LOG__`;function i(i){try{let a=i?.type;if(a!==`avatar-overlay-drag-start`&&a!==`avatar-overlay-drag-release`&&!(a===`avatar-overlay-pointer-interaction-changed`&&i?.isInteractive===!0)&&a!==`avatar-overlay-mascot-resize-start`&&!(a===`local-thread-activity-changed`&&i?.hasInProgressLocalConversation===!0))return;let o=Date.now();if(o-e<700)return;e=o;try{(n??=require(`fs`)).appendFile(r,`${new Date().toISOString()} play trigger type=${a}\n`,()=>{})}catch{}}catch{}}return{play:i}})();
'@
        $eventLogJs = ($eventLogPath -replace '\\', '\\') -replace "'", "\'"
        $listener = $listenerTemplate.
            Replace('__CODEX_PET_MARKER__', $marker).
            Replace('__CODEX_PET_EVENT_LOG__', $eventLogJs)
        if (-not $mainText.Contains($insertBefore)) {
            throw "Patch anchor not found in $main"
        }
        $mainText = $mainText.Replace($insertBefore, $listener + $insertBefore)

        $target = 'async handleMessage(e,t){if(PN(t)){await IN(this.avatarOverlayManager,e,t,t=>{this.windowManager.sendMessageToWebContents(e,t)});return}switch(t.type)'
        $replacement = 'async handleMessage(e,t){CODEX_PET_SOUND_LISTENER_V1.play(t);if(PN(t)){await IN(this.avatarOverlayManager,e,t,t=>{this.windowManager.sendMessageToWebContents(e,t)});return}switch(t.type)'
        if (-not $mainText.Contains($target)) {
            throw "Patch target not found in $main"
        }
        $mainText = $mainText.Replace($target, $replacement)
        Set-Content -LiteralPath $main -Value $mainText -NoNewline -Encoding UTF8
    }

    $backup = Join-Path $backupDir "app.asar.original.$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
    Copy-Item -LiteralPath $targetAsar -Destination $backup -Force

    & $npx.Source --yes '@electron/asar' pack $extractDir $newAsar
    if ($LASTEXITCODE -ne 0) { throw "asar pack failed with exit code $LASTEXITCODE" }

    Copy-Item -LiteralPath $newAsar -Destination $targetAsar -Force
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$config = [ordered]@{
    codexAppDir = $CodexAppDir
    codexHome = $CodexHome
    targetRoot = $TargetRoot
    petDir = $PetDir
    soundSubdir = $SoundSubdir
    eventLogPath = $eventLogPath
    bridgeLogPath = $bridgeLogPath
}
$config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath -Encoding UTF8

$exe = Join-Path $targetApp 'ChatGPT.exe'
$launcherText = @"
`$ErrorActionPreference = 'Stop'
`$other = Get-Process -ErrorAction SilentlyContinue | Where-Object {
    `$_.ProcessName -eq 'ChatGPT' -and `$_.Path -notlike '$($targetApp.Replace("'","''"))*'
}
if (`$other) {
    `$ids = (`$other | Select-Object -ExpandProperty Id) -join ', '
    Write-Host "Another Codex instance is still running. Close it before starting this modded copy. PIDs: `$ids"
    exit 1
}
`$bridge = '$($bridgeTarget.Replace("'","''"))'
`$codexHome = '$($CodexHome.Replace("'","''"))'
`$petDir = '$($PetDir.Replace("'","''"))'
`$eventLogPath = '$($eventLogPath.Replace("'","''"))'
`$bridgeLogPath = '$($bridgeLogPath.Replace("'","''"))'
`$bridgeRunning = Get-CimInstance Win32_Process | Where-Object {
    `$_.CommandLine -like "*`$bridge*" -and `$_.CommandLine -like "*`$eventLogPath*" -and `$_.CommandLine -notlike '*Get-CimInstance*'
}
if (-not `$bridgeRunning) {
    `$args = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        `$bridge,
        '-CodexHome',
        `$codexHome,
        '-EventLogPath',
        `$eventLogPath,
        '-BridgeLogPath',
        `$bridgeLogPath,
        '-SoundSubdir',
        '$($SoundSubdir.Replace("'","''"))'
    )
    if (`$petDir.Trim().Length -gt 0) {
        `$args += @('-PetDir', `$petDir)
    }
    Start-Process -FilePath powershell.exe -ArgumentList `$args -WindowStyle Hidden
}
Start-Process -FilePath '$($exe.Replace("'","''"))' -WorkingDirectory '$($targetApp.Replace("'","''"))'
"@
Set-Content -LiteralPath $launcher -Value $launcherText -Encoding UTF8

$launcherCmdText = @"
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0Start-Codex-Pet-Sound.ps1"
"@
Set-Content -LiteralPath $launcherCmd -Value $launcherCmdText -Encoding ASCII

$updaterText = @"
`$ErrorActionPreference = 'Stop'
Write-Host "Close official or modded Codex before updating this mod."
powershell -ExecutionPolicy Bypass -File '$($installerTarget.Replace("'","''"))' ``
  -CodexHome '$($CodexHome.Replace("'","''"))' ``
  -TargetRoot '$($TargetRoot.Replace("'","''"))' ``
  -SoundSubdir '$($SoundSubdir.Replace("'","''"))' ``
  -Force
"@
if ($PetDir.Trim().Length -gt 0) {
    $updaterText = $updaterText + "`r`n# This install is pinned to one pet directory.`r`n"
    $updaterText = $updaterText -replace '\s+-Force\s*$', "  -PetDir '$($PetDir.Replace("'","''"))' ```r`n  -Force"
}
Set-Content -LiteralPath $updater -Value $updaterText -Encoding UTF8

$updaterCmdText = @"
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0Update-Codex-Pet-Sound.ps1"
pause
"@
Set-Content -LiteralPath $updaterCmd -Value $updaterCmdText -Encoding ASCII

Write-Host "Created Codex pet sound mod:"
Write-Host "  $TargetRoot"
Write-Host "Launcher:"
Write-Host "  $launcher"
Write-Host "Updater:"
Write-Host "  $updater"
Write-Host ""
Write-Host "After official Codex updates, close Codex and re-run this installer with -Force."
