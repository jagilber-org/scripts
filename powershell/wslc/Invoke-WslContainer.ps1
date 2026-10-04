<#
.SYNOPSIS
    Combined WSL container (wslc.exe) helper that creates a $wslcObj object with dot-callable methods.

.DESCRIPTION
    Consolidates the individual wslc wrapper scripts into a single object-oriented helper,
    following the same pattern as kusto-rest.ps1 (KustoObj) and nuget-functions.ps1 (NugetObj).
    Running or dot-sourcing this script creates $global:wslcObj, a WslcObj instance whose
    methods wrap the documented wslc commands (see
    https://learn.microsoft.com/windows/wsl/wsl-container). Native '--format json' output is
    parsed and enriched (friendly state, uptime, ports, optional live CPU/mem stats).

    Example methods:
        $wslcObj.GetContainers()            # running containers as objects
        $wslcObj.GetContainers($true, $true)# all containers with live CPU/mem stats
        $wslcObj.GetImages()
        $wslcObj.Run('nginx', 'web', @('8080:80'), $true)
        $wslcObj.Stop('web'); $wslcObj.Start('web'); $wslcObj.Restart('web')
        $wslcObj.Exec('ubuntu:latest', @('bash','-c','echo hello'))
        $wslcObj.Logs('web', 50); $wslcObj.Inspect('web'); $wslcObj.Prune()

.NOTES
    File Name  : Invoke-WslContainer.ps1
    Author     : jagilber
    Requires   : Windows Subsystem for Linux (WSL) with the WSL container feature
    Disclaimer : Provided AS-IS without warranty.
    Version    : 1.0.0
    Changelog  : 1.0.0 - Initial release (combined WslcObj object model)

.PARAMETER WslcPath
    Path or command name for the WSL container CLI. Defaults to 'wslc.exe'.

.EXAMPLE
    . .\Invoke-WslContainer.ps1
    $wslcObj.GetContainers() | Format-Table
    Dot-source the script and list running containers.

.EXAMPLE
    .\Invoke-WslContainer.ps1
    $wslcObj.Run('nginx', 'web', @('8080:80'), $true)
    Creates $wslcObj and starts a detached nginx container publishing port 8080.

.LINK
    https://learn.microsoft.com/windows/wsl/wsl-container
#>

[CmdletBinding()]
param(
    [string]$WslcPath = 'wslc.exe'
)

$ErrorActionPreference = 'continue'
$global:wslcObj = $null

class WslcObj {
    [string]$WslcPath = 'wslc.exe'
    [bool]$Ready = $false
    [string]$WslVersion = 'unknown'
    hidden [string]$wslc = $null
    hidden [hashtable]$stateMap = @{ 0 = 'Invalid'; 1 = 'Created'; 2 = 'Running'; 3 = 'Exited'; 4 = 'Deleted' }

    WslcObj() { $this.Initialize('wslc.exe') }
    WslcObj([string]$wslcPath) { $this.Initialize($wslcPath) }

    hidden [void] Initialize([string]$wslcPath) {
        $this.WslcPath = $wslcPath
        $command = Get-Command $wslcPath -ErrorAction SilentlyContinue
        if ($command) {
            $this.wslc = $command.Source
            $this.Ready = $true
            $this.WslVersion = $this.GetWslVersion()
        }
        else {
            Write-Warning "wslc CLI '$wslcPath' not found. Run `$wslcObj.Prerequisites() or 'wsl --update --pre-release'."
        }
    }

    # --- hidden helpers ---------------------------------------------------

    hidden [void] EnsureReady() {
        if (!$this.Ready) { throw "wslc CLI '$($this.WslcPath)' is not available." }
    }

    hidden [string] InvokeCli([string[]]$arguments) {
        $this.EnsureReady()
        $output = & $this.wslc @arguments 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "wslc $($arguments -join ' ') failed with exit code $LASTEXITCODE`n$($output -join "`n")"
        }
        return ($output | Out-String)
    }

    hidden [string] GetWslVersion() {
        $wsl = Get-Command 'wsl.exe' -ErrorAction SilentlyContinue
        if (!$wsl) { return 'unknown' }
        $versionOutput = (& $wsl.Source '--version') 2>$null
        if ($versionOutput) {
            return ($versionOutput | Where-Object { $_ -match '\S' } | Select-Object -First 1).Trim()
        }
        return 'unknown'
    }

    hidden [object] FromUnix([long]$seconds) {
        if (!$seconds) { return $null }
        return [DateTimeOffset]::FromUnixTimeSeconds($seconds).LocalDateTime
    }

    hidden [string] FormatDuration([timespan]$span) {
        if ($span.TotalSeconds -lt 0) { return '0s' }
        if ($span.TotalSeconds -lt 60) { return ('{0}s' -f [int]$span.TotalSeconds) }
        if ($span.TotalMinutes -lt 60) { return ('{0}m' -f [int]$span.TotalMinutes) }
        if ($span.TotalHours -lt 24) { return ('{0}h {1}m' -f [int]$span.Hours, [int]$span.Minutes) }
        return ('{0}d {1}h' -f [int]$span.Days, [int]$span.Hours)
    }

    hidden [string] GetUptime([string]$stateLabel, [object]$changed) {
        if (!$changed) { return '' }
        $span = (Get-Date) - [datetime]$changed
        $human = $this.FormatDuration($span)
        switch ($stateLabel) {
            'Running' { return "up $human" }
            'Exited' { return "exited $human ago" }
            'Created' { return 'created' }
            default { return $human }
        }
        return $human
    }

    hidden [string] FormatPorts([object]$ports) {
        if (!$ports) { return '' }
        $parts = foreach ($port in @($ports)) {
            $proto = switch ([int]$port.Protocol) { 6 { 'tcp' } 17 { 'udp' } default { "proto$($port.Protocol)" } }
            $bind = if ($port.BindingAddress) { $port.BindingAddress } else { '0.0.0.0' }
            '{0}:{1}->{2}/{3}' -f $bind, $port.HostPort, $port.ContainerPort, $proto
        }
        return ($parts -join ', ')
    }

    hidden [string] FormatSize([long]$bytes) {
        if ($bytes -le 0) { return '0 B' }
        $units = @('B', 'KB', 'MB', 'GB', 'TB')
        $value = [double]$bytes
        $unit = 0
        while ($value -ge 1024 -and $unit -lt ($units.Count - 1)) {
            $value = $value / 1024
            $unit++
        }
        return ('{0:0.#} {1}' -f $value, $units[$unit])
    }

    hidden [hashtable] GetStatsMap() {
        $map = @{}
        try {
            $out = & $this.wslc stats --all --format json 2>$null
            if ($LASTEXITCODE -ne 0 -or !$out) { return $map }
            $items = ($out | Out-String) | ConvertFrom-Json
            foreach ($stat in @($items)) { $map[$stat.ID] = $stat }
        }
        catch { }
        return $map
    }

    # --- images -----------------------------------------------------------

    hidden [hashtable] GetImageDetailsMap([string[]]$ids) {
        # Per-image 'image inspect' enrichment, keyed by stripped Id. Best-effort.
        $map = @{}
        foreach ($id in $ids) {
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            try {
                $out = & $this.wslc image inspect $id 2>$null
                if ($LASTEXITCODE -ne 0 -or !$out) { continue }
                $detail = @(($out | Out-String) | ConvertFrom-Json)[0]
                if ($detail) { $map[$id] = $detail }
            }
            catch { }
        }
        return $map
    }

    [object[]] GetImages() { return $this.GetImages($false) }

    [object[]] GetImages([bool]$includeDetails) {
        $json = $this.InvokeCli(@('image', 'ls', '--format', 'json'))
        if ([string]::IsNullOrWhiteSpace($json)) { return @() }
        $items = $json | ConvertFrom-Json
        if ($null -eq $items) { return @() }

        $ids = @(foreach ($item in @($items)) { "$($item.Id)" -replace '^sha256:', '' })
        $detailMap = if ($includeDetails) { $this.GetImageDetailsMap($ids) } else { @{} }

        $result = foreach ($item in @($items)) {
            $id = "$($item.Id)" -replace '^sha256:', ''
            $repo = if ($item.Repository) { $item.Repository } else { '<none>' }
            $tag = if ($item.Tag) { $item.Tag } else { '<none>' }
            $created = $this.FromUnix($item.Created)
            $age = if ($created) { $this.FormatDuration((Get-Date) - [datetime]$created) } else { '' }

            $obj = [ordered]@{
                Reference  = '{0}:{1}' -f $repo, $tag
                Repository = $repo
                Tag        = $tag
                Age        = $age
                Size       = if ($item.Size) { $this.FormatSize($item.Size) } else { '' }
                SizeMB     = if ($item.Size) { [math]::Round($item.Size / 1MB, 2) } else { 0 }
                Created    = $created
                Dangling   = ($repo -eq '<none>' -or $tag -eq '<none>')
                ShortId    = if ($id) { $id.Substring(0, [math]::Min(12, $id.Length)) } else { $null }
                Id         = $id
            }

            if ($includeDetails) {
                $detail = $detailMap[$id]
                $config = if ($detail) { $detail.Config } else { $null }
                $obj.Architecture = if ($detail) { $detail.Architecture } else { '' }
                $obj.Os = if ($detail) { $detail.Os } else { '' }
                $obj.Platform = if ($detail -and $detail.Os -and $detail.Architecture) { '{0}/{1}' -f $detail.Os, $detail.Architecture } else { '' }
                $obj.Layers = if ($detail -and $detail.RootFS -and $detail.RootFS.Layers) { @($detail.RootFS.Layers).Count } else { 0 }
                $obj.ExposedPorts = if ($config -and $config.ExposedPorts) { (($config.ExposedPorts.PSObject.Properties.Name) -join ', ') } else { '' }
                $obj.Entrypoint = if ($config) { (@($config.Entrypoint) -join ' ').Trim() } else { '' }
                $obj.Command = if ($config) { (@($config.Cmd) -join ' ').Trim() } else { '' }
                $obj.EnvCount = if ($config -and $config.Env) { @($config.Env).Count } else { 0 }
                $obj.Labels = if ($config) { $config.Labels } else { $null }
                $obj.StopSignal = if ($config) { $config.StopSignal } else { '' }
                $obj.WorkingDir = if ($config) { $config.WorkingDir } else { '' }
                $obj.User = if ($config) { $config.User } else { '' }
                $obj.Digest = if ($detail -and $detail.RepoDigests) { @($detail.RepoDigests)[0] } else { '' }
            }

            [pscustomobject]$obj
        }
        return @($result)
    }

    [object] ImageInspect([string]$reference) {
        $json = $this.InvokeCli(@('image', 'inspect', $reference))
        if ([string]::IsNullOrWhiteSpace($json)) { return $null }
        return @($json | ConvertFrom-Json)[0]
    }

    # --- containers -------------------------------------------------------

    [object[]] GetContainers() { return $this.GetContainers($false, $false) }
    [object[]] GetContainers([bool]$all) { return $this.GetContainers($all, $false) }

    [object[]] GetContainers([bool]$all, [bool]$includeStats) {
        $arguments = [collections.generic.list[string]]@('container', 'ls', '--format', 'json')
        if ($all) { $arguments.Add('--all') }
        $json = $this.InvokeCli($arguments)
        if ([string]::IsNullOrWhiteSpace($json)) { return @() }
        $items = $json | ConvertFrom-Json
        if ($null -eq $items) { return @() }

        $statsMap = if ($includeStats) { $this.GetStatsMap() } else { @{} }

        $result = foreach ($item in @($items)) {
            $stateCode = [int]$item.State
            $stateLabel = if ($this.stateMap.ContainsKey($stateCode)) { $this.stateMap[$stateCode] } else { "State$stateCode" }
            $changed = $this.FromUnix($item.StateChangedAt)

            $obj = [ordered]@{
                Name    = $item.Name
                State   = $stateLabel
                Uptime  = $this.GetUptime($stateLabel, $changed)
                Image   = $item.Image
                Ports   = $this.FormatPorts($item.Ports)
                ShortId = if ($item.Id) { $item.Id.Substring(0, [math]::Min(12, $item.Id.Length)) } else { $null }
                Id      = $item.Id
            }

            if ($includeStats) {
                $stat = $statsMap[$item.Id]
                $obj.CPUPerc = if ($stat) { $stat.CPUPerc } else { '' }
                $obj.MemPerc = if ($stat) { $stat.MemPerc } else { '' }
                $obj.MemUsage = if ($stat) { $stat.MemUsage } else { '' }
                $obj.PIDs = if ($stat) { $stat.PIDs } else { '' }
            }

            [pscustomobject]$obj
        }
        return @($result)
    }

    [object[]] GetStats() {
        $json = $this.InvokeCli(@('stats', '--all', '--format', 'json'))
        if ([string]::IsNullOrWhiteSpace($json)) { return @() }
        return @($json | ConvertFrom-Json)
    }

    [object] Inspect([string]$name) {
        $json = $this.InvokeCli(@('container', 'inspect', $name))
        if ([string]::IsNullOrWhiteSpace($json)) { return $null }
        return @($json | ConvertFrom-Json)[0]
    }

    [string] Logs([string]$name) { return $this.Logs($name, 200) }
    [string] Logs([string]$name, [int]$tail) {
        return $this.InvokeCli(@('logs', '-n', "$tail", $name))
    }

    # --- lifecycle --------------------------------------------------------

    [string] Run([string]$image) { return $this.Run($image, $null, @(), $false, @()) }
    [string] Run([string]$image, [string]$name, [string[]]$publish, [bool]$detach) {
        return $this.Run($image, $name, $publish, $detach, @())
    }

    [string] Run([string]$image, [string]$name, [string[]]$publish, [bool]$detach, [string[]]$command) {
        $arguments = [collections.generic.list[string]]@('run')
        if ($detach) { $arguments.Add('-d') }
        foreach ($mapping in $publish) { $arguments.Add('-p'); $arguments.Add($mapping) }
        if ($name) { $arguments.Add('--name'); $arguments.Add($name) }
        $arguments.Add($image)
        foreach ($token in $command) { $arguments.Add($token) }
        return $this.InvokeCli($arguments).Trim()
    }

    [string] Exec([string]$image, [string[]]$command) {
        $arguments = [collections.generic.list[string]]@('run', '--rm')
        $arguments.Add($image)
        foreach ($token in $command) { $arguments.Add($token) }
        return $this.InvokeCli($arguments)
    }

    [string] Start([string]$name) { return $this.InvokeCli(@('container', 'start', $name)).Trim() }
    [string] Stop([string]$name) { return $this.InvokeCli(@('container', 'stop', $name)).Trim() }

    [string] Restart([string]$name) {
        [void]$this.InvokeCli(@('container', 'stop', $name))
        return $this.InvokeCli(@('container', 'start', $name)).Trim()
    }

    [string] Remove([string]$name) { return $this.Remove($name, $false) }
    [string] Remove([string]$name, [bool]$force) {
        $arguments = [collections.generic.list[string]]@('container', 'remove')
        if ($force) { $arguments.Add('--force') }
        $arguments.Add($name)
        return $this.InvokeCli($arguments).Trim()
    }
    [string] Prune() { return $this.InvokeCli(@('container', 'prune')).Trim() }

    # --- info -------------------------------------------------------------

    [bool] IsReady() { return $this.Ready }

    [object] Prerequisites() {
        # Structured readiness report (replaces the standalone prerequisite script).
        $wslCommand = Get-Command 'wsl.exe' -ErrorAction SilentlyContinue
        $wslcCommand = Get-Command $this.WslcPath -ErrorAction SilentlyContinue
        $result = [pscustomobject][ordered]@{
            WslInstalled  = [bool]$wslCommand
            WslcInstalled = [bool]$wslcCommand
            WslcPath      = if ($wslcCommand) { $wslcCommand.Source } else { $null }
            WslVersion    = $this.WslVersion
            Ready         = ([bool]$wslCommand -and [bool]$wslcCommand)
        }
        if (-not $result.WslInstalled) {
            Write-Warning 'wsl.exe not found. Install with: wsl --install'
        }
        elseif (-not $result.WslcInstalled) {
            Write-Warning "wslc.exe not found. Ensure WSL is up to date: wsl --update --pre-release"
        }
        else {
            Write-Host 'WSL container prerequisites satisfied.' -ForegroundColor Green
        }
        return $result
    }

    [void] Help() {
        Write-Host "wslc: $($this.wslc)  |  wsl: $($this.WslVersion)  |  ready: $($this.Ready)" -ForegroundColor Cyan
        Write-Host ($this | Get-Member -MemberType Method | Where-Object { $_.Name -notmatch '^(Equals|GetHashCode|GetType|ToString)$' } | Select-Object Name, Definition | Format-Table -AutoSize | Out-String)
    }
}

function main() {
    try {
        $global:wslcObj = [WslcObj]::new($WslcPath)

        if ($global:wslcObj.Ready) {
            Write-Host "`$wslcObj created (wsl $($global:wslcObj.WslVersion))." -ForegroundColor Green
            Write-Host "Examples:" -ForegroundColor Green
            Write-Host "  `$wslcObj.GetContainers() | Format-Table" -ForegroundColor DarkGray
            Write-Host "  `$wslcObj.GetContainers(`$true, `$true) | Format-Table Name,State,Uptime,CPUPerc,MemUsage" -ForegroundColor DarkGray
            Write-Host "  `$wslcObj.Run('nginx','web',@('8080:80'),`$true)" -ForegroundColor DarkGray
            Write-Host "  `$wslcObj.Stop('web'); `$wslcObj.Logs('web',50); `$wslcObj.Inspect('web')" -ForegroundColor DarkGray
            Write-Host "  `$wslcObj.Help()   # list all methods" -ForegroundColor DarkGray
        }
        else {
            Write-Warning "`$wslcObj created but wslc is not available. Install/update: wsl --update --pre-release"
        }
        return 0
    }
    catch {
        Write-Host "exception::$($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
        return 1
    }
}

main
