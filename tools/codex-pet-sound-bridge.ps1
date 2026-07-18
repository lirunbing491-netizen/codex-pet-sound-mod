param(
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [string]$PetDir = '',
    [string]$EventLogPath = '',
    [string]$BridgeLogPath = '',
    [string]$SoundSubdir = 'sounds',
    [int]$PollMs = 50,
    [int]$CooldownMs = 700
)

$ErrorActionPreference = 'Stop'

$modRoot = Join-Path $CodexHome 'pet-sound-mod'
$logsDir = Join-Path $modRoot 'logs'
if (-not $EventLogPath) { $EventLogPath = Join-Path $logsDir 'pet-events.log' }
if (-not $BridgeLogPath) { $BridgeLogPath = Join-Path $logsDir 'sound-bridge.log' }

New-Item -ItemType Directory -Path (Split-Path -Parent $BridgeLogPath) -Force | Out-Null

function Write-BridgeLog {
    param([string]$Message)
    try {
        Add-Content -LiteralPath $BridgeLogPath -Value ("{0:yyyy-MM-dd HH:mm:ss.fff} {1}" -f (Get-Date), $Message)
    } catch {}
}

if (-not ('CodexPetBridgeWinmmSound' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CodexPetBridgeWinmmSound {
    [DllImport("winmm.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool PlaySound(string pszSound, IntPtr hmod, uint fdwSound);
}
'@
}

function Get-SelectedCustomPetDir {
    if ($PetDir.Trim().Length -gt 0) {
        return $PetDir
    }

    $configPath = Join-Path $CodexHome 'config.toml'
    if (-not (Test-Path -LiteralPath $configPath)) {
        Write-BridgeLog "config-missing path=$configPath"
        return $null
    }

    $configText = Get-Content -LiteralPath $configPath -Raw
    $match = [regex]::Match($configText, '(?m)^\s*selected-avatar-id\s*=\s*"custom:([^"]+)"\s*$')
    if (-not $match.Success) {
        Write-BridgeLog "selected-pet-none-or-bundled"
        return $null
    }

    $petId = $match.Groups[1].Value
    if ($petId -match '[\\/]' -or $petId -match '^\.+$') {
        Write-BridgeLog "selected-pet-invalid id=$petId"
        return $null
    }

    return Join-Path (Join-Path $CodexHome 'pets') $petId
}

function Invoke-PetSound {
    $activePetDir = Get-SelectedCustomPetDir
    if ($null -eq $activePetDir) {
        return
    }

    $soundDir = Join-Path $activePetDir $SoundSubdir
    if (-not (Test-Path -LiteralPath $soundDir)) {
        Write-BridgeLog "sound-dir-missing dir=$soundDir"
        return
    }

    $sound = Get-ChildItem -LiteralPath $soundDir -File -Filter '*.wav' |
        Where-Object { $_.Length -gt 0 } |
        Get-Random

    if ($null -eq $sound) {
        Write-BridgeLog "sound-none dir=$soundDir"
        return
    }

    $SND_ASYNC = 0x0001
    $SND_FILENAME = 0x00020000
    $SND_NODEFAULT = 0x0002
    $ok = [CodexPetBridgeWinmmSound]::PlaySound($sound.FullName, [IntPtr]::Zero, $SND_ASYNC -bor $SND_FILENAME -bor $SND_NODEFAULT)
    Write-BridgeLog "play-direct ok=$ok petDir=$activePetDir file=$($sound.Name)"
}

$lastLength = 0L
if (Test-Path -LiteralPath $EventLogPath) {
    $lastLength = (Get-Item -LiteralPath $EventLogPath).Length
}

$lastPlay = [DateTime]::MinValue
Write-BridgeLog "bridge-start eventLog=$EventLogPath codexHome=$CodexHome fixedPetDir=$PetDir startLength=$lastLength pollMs=$PollMs cooldownMs=$CooldownMs"

while ($true) {
    try {
        if (Test-Path -LiteralPath $EventLogPath) {
            $item = Get-Item -LiteralPath $EventLogPath
            if ($item.Length -lt $lastLength) {
                $lastLength = 0L
            }

            if ($item.Length -gt $lastLength) {
                $stream = [System.IO.File]::Open($EventLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try {
                    $stream.Seek($lastLength, [System.IO.SeekOrigin]::Begin) | Out-Null
                    $reader = [System.IO.StreamReader]::new($stream)
                    $newText = $reader.ReadToEnd()
                    $lastLength = $item.Length
                } finally {
                    if ($reader) { $reader.Dispose() }
                    $stream.Dispose()
                }

                if ($newText.Trim().Length -gt 0) {
                    $now = Get-Date
                    if (($now - $lastPlay).TotalMilliseconds -ge $CooldownMs) {
                        $lastPlay = $now
                        Write-BridgeLog ("trigger lines={0}" -f (($newText -split "`r?`n") | Where-Object { $_.Trim().Length -gt 0 }).Count)
                        Invoke-PetSound
                    }
                }
            }
        }
    } catch {
        Write-BridgeLog "bridge-error $($_.Exception.GetType().FullName): $($_.Exception.Message)"
    }

    Start-Sleep -Milliseconds $PollMs
}
