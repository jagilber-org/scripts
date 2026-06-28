<#
.SYNOPSIS
    Inspect or clear VS Code and Copilot cache folders after repo moves or stale workspace identity.

.DESCRIPTION
    Default mode is inspect-only. Supply one or more cleanup switches to clear selected folders.
    DeepClean = workspaceStorage + github.copilot + github.copilot-chat.
    DeeperClean = DeepClean + github.copilot-chat\memory-tool\memories.
    FullClean = DeeperClean + ~/.copilot/session-state.

.NOTES

    File Name  : Clear-VsCodeCopilotCache.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Clear-VsCodeCopilotCache.ps1

.EXAMPLE
    .\Clear-VsCodeCopilotCache.ps1 -ClearWorkspaceStorage -WhatIf

.EXAMPLE
    .\Clear-VsCodeCopilotCache.ps1 -DeepClean -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Insiders', 'Stable', 'Both')]
    [string]$Product = 'Insiders',
    [switch]$ClearWorkspaceStorage,
    [switch]$ClearLegacyCopilotGlobalStorage,
    [switch]$ClearCopilotChatGlobalStorage,
    [switch]$ClearMemoryToolMemories,
    [switch]$ClearSessionState,
    [switch]$DeepClean,
    [switch]$DeeperClean,
    [switch]$FullClean,
    [ValidateSet('Move', 'Copy', 'Delete')]
    [string]$CleanupMode = 'Move',
    [string]$BackupRoot = (Join-Path $env:TEMP ('vscode-copilot-cache-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($FullClean) { $DeeperClean = $true; $ClearSessionState = $true }
if ($DeeperClean) { $DeepClean = $true; $ClearMemoryToolMemories = $true }
if ($DeepClean) {
    $ClearWorkspaceStorage = $true
    $ClearLegacyCopilotGlobalStorage = $true
    $ClearCopilotChatGlobalStorage = $true
}

function Get-Products {
    param([string]$Name)
    $items = @()
    if ($Name -in @('Insiders', 'Both')) {
        $items += [pscustomobject]@{ Name = 'Insiders'; Root = (Join-Path $env:APPDATA 'Code - Insiders\User') }
    }
    if ($Name -in @('Stable', 'Both')) {
        $items += [pscustomobject]@{ Name = 'Stable'; Root = (Join-Path $env:APPDATA 'Code\User') }
    }
    $items
}

function New-Target {
    param([string]$Channel, [string]$Kind, [string]$Path)
    [pscustomobject]@{ Channel = $Channel; Kind = $Kind; Path = [IO.Path]::GetFullPath($Path) }
}

function Remove-NestedTargets {
    param([object[]]$Targets)
    $keepers = New-Object System.Collections.Generic.List[object]
    foreach ($target in ($Targets | Group-Object Path | ForEach-Object { $_.Group[0] } | Sort-Object { $_.Path.TrimEnd('\').Length })) {
        $candidate = $target.Path.TrimEnd('\')
        $nested = $false
        foreach ($existing in $keepers) {
            $parent = $existing.Path.TrimEnd('\')
            if ($candidate.Length -gt $parent.Length -and $candidate.StartsWith($parent + '\', [StringComparison]::OrdinalIgnoreCase)) {
                $nested = $true
                break
            }
        }
        if (-not $nested) { [void]$keepers.Add($target) }
    }
    $keepers.ToArray()
}

function Get-Targets {
    param([bool]$InspectOnly)
    $targets = @()
    foreach ($productInfo in Get-Products -Name $Product) {
        $workspace = Join-Path $productInfo.Root 'workspaceStorage'
        $global = Join-Path $productInfo.Root 'globalStorage'
        $legacy = Join-Path $global 'github.copilot'
        $chat = Join-Path $global 'github.copilot-chat'
        $memories = Join-Path $chat 'memory-tool\memories'
        if ($InspectOnly -or $ClearWorkspaceStorage) { $targets += New-Target $productInfo.Name 'workspaceStorage' $workspace }
        if ($InspectOnly -or $ClearLegacyCopilotGlobalStorage) { $targets += New-Target $productInfo.Name 'legacyCopilotGlobalStorage' $legacy }
        if ($InspectOnly -or $ClearCopilotChatGlobalStorage) { $targets += New-Target $productInfo.Name 'copilotChatGlobalStorage' $chat }
        if ($InspectOnly -or $ClearMemoryToolMemories) { $targets += New-Target $productInfo.Name 'memoryToolMemories' $memories }
    }
    if ($InspectOnly -or $ClearSessionState) {
        $targets += New-Target 'Shared' 'sessionState' (Join-Path $env:USERPROFILE '.copilot\session-state')
    }
    Remove-NestedTargets -Targets $targets
}

function Get-State {
    param([object]$Target)
    $exists = Test-Path -LiteralPath $Target.Path
    $children = @()
    $dbCount = $null
    $lastWrite = $null
    if ($exists) {
        $item = Get-Item -LiteralPath $Target.Path -Force
        $lastWrite = $item.LastWriteTime
        $children = @(Get-ChildItem -LiteralPath $Target.Path -Force -ErrorAction SilentlyContinue)
        if ($Target.Kind -eq 'sessionState') {
            $dbCount = @(Get-ChildItem -LiteralPath $Target.Path -Filter 'session.db' -File -Recurse -Force -ErrorAction SilentlyContinue).Count
        }
    }
    [pscustomobject]@{
        Channel = $Target.Channel
        Kind = $Target.Kind
        Exists = $exists
        ChildCount = $(if ($exists) { $children.Count } else { $null })
        SessionDbCount = $dbCount
        LastWriteTime = $lastWrite
        Path = $Target.Path
        Recent = $(if ($children.Count -gt 0) { (($children | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object { '{0} [{1}] {2}' -f $_.Name, $(if ($_.PSIsContainer) { 'Dir' } else { 'File' }), $_.LastWriteTime.ToString('s') }) -join '; ') } else { '' })
    }
}

function Ensure-EmptyDirectory {
    param([string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Clear-Target {
    param([object]$Target, [string]$Mode, [string]$RunBackupRoot)
    if (-not (Test-Path -LiteralPath $Target.Path)) {
        return [pscustomobject]@{ Kind = $Target.Kind; Status = 'SkippedMissing'; BackupPath = $null; Path = $Target.Path }
    }
    $action = switch ($Mode) {
        'Move' { 'Move target to backup and recreate empty directory' }
        'Copy' { 'Copy target to backup, delete original, and recreate empty directory' }
        'Delete' { 'Delete target and recreate empty directory' }
    }
    if (-not $PSCmdlet.ShouldProcess($Target.Path, $action)) {
        return [pscustomobject]@{ Kind = $Target.Kind; Status = 'SkippedByShouldProcess'; BackupPath = $null; Path = $Target.Path }
    }
    $backupPath = $null
    if ($Mode -in @('Move', 'Copy')) {
        $leaf = Split-Path -Path $Target.Path -Leaf
        $safe = ('{0}-{1}-{2}' -f $Target.Channel, $Target.Kind, $leaf) -replace '[^A-Za-z0-9._-]', '_'
        $backupPath = Join-Path $RunBackupRoot $safe
    }
    switch ($Mode) {
        'Move' { Move-Item -LiteralPath $Target.Path -Destination $backupPath -Force }
        'Copy' { Copy-Item -LiteralPath $Target.Path -Destination $backupPath -Recurse -Force; Remove-Item -LiteralPath $Target.Path -Recurse -Force }
        'Delete' { Remove-Item -LiteralPath $Target.Path -Recurse -Force }
    }
    Ensure-EmptyDirectory -Path $Target.Path
    [pscustomobject]@{ Kind = $Target.Kind; Status = 'Cleaned'; BackupPath = $backupPath; Path = $Target.Path }
}

$requestedCleanup = @(
    $ClearWorkspaceStorage,
    $ClearLegacyCopilotGlobalStorage,
    $ClearCopilotChatGlobalStorage,
    $ClearMemoryToolMemories,
    $ClearSessionState
) -contains $true

$targets = Get-Targets -InspectOnly:(-not $requestedCleanup)
$inspection = @($targets | ForEach-Object { Get-State $_ })

$runningCode = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Code*' } | Select-Object -ExpandProperty ProcessName -Unique)
if ($requestedCleanup -and $runningCode.Count -gt 0) {
    Write-Warning ('VS Code appears to be running: ' + ($runningCode -join ', ') + '. Close it before cleanup for the cleanest reset.')
}

Write-Host 'Inspection summary:' -ForegroundColor Cyan
$inspection | Select-Object Channel, Kind, Exists, ChildCount, SessionDbCount, LastWriteTime, Path | Format-Table -AutoSize | Out-Host
foreach ($row in $inspection) {
    if ($row.Recent) { Write-Host ('Recent children for {0}/{1}: {2}' -f $row.Channel, $row.Kind, $row.Recent) -ForegroundColor DarkGray }
}

if (-not $requestedCleanup) {
    Write-Host 'No cleanup switches were supplied. Inspection only.' -ForegroundColor Yellow
    return
}

$runBackupRoot = $null
if ($CleanupMode -in @('Move', 'Copy')) {
    $runBackupRoot = Join-Path $BackupRoot ('run-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $runBackupRoot -Force | Out-Null
    Write-Host ('Backup root: ' + $runBackupRoot) -ForegroundColor Cyan
}

$results = @($targets | ForEach-Object { Clear-Target -Target $_ -Mode $CleanupMode -RunBackupRoot $runBackupRoot })
$post = @($targets | ForEach-Object { Get-State $_ })

Write-Host 'Cleanup results:' -ForegroundColor Cyan
$results | Format-Table Kind, Status, BackupPath -AutoSize | Out-Host
Write-Host 'Post-clean inspection:' -ForegroundColor Cyan
$post | Select-Object Channel, Kind, Exists, ChildCount, SessionDbCount, LastWriteTime, Path | Format-Table -AutoSize | Out-Host
