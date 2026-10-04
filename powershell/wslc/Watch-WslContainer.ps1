<#
.SYNOPSIS
    Live, auto-refreshing console dashboard for the WSL container CLI (wslc.exe).

.DESCRIPTION
    Provides a top-style holistic view of the local WSL container environment by
    repeatedly clearing and redrawing the console. Each refresh shows prerequisite
    status (wsl/wslc versions), running (or all) containers, available images, and
    summary counts. Each container NAME is a clickable link that opens its
    'wslc inspect' details (written to a temp JSON file). Running containers that
    publish TCP ports get a clickable http://host:port hyperlink (OSC 8, rendered by
    Windows Terminal and the VS Code integrated terminal), and the footer links to
    the WSL container docs. With -Interactive, select a container by number and press
    s=stop, r=restart, l=logs, i=inspect (terminal links cannot run commands, so
    actions use keystrokes). Wraps the documented wslc commands 'container ls',
    'image ls', 'inspect', 'logs', 'container stop/start' (see
    https://learn.microsoft.com/windows/wsl/wsl-container). Runs until the iteration
    limit is reached or the user presses Ctrl+C (or 'q' in interactive mode).

.NOTES
    File Name  : Watch-WslContainer.ps1
    Author     : jagilber
    Requires   : Windows Subsystem for Linux (WSL) with the WSL container feature
    Disclaimer : Provided AS-IS without warranty.
    Version    : 1.5.0
    Changelog  : 1.0.0 - Initial release
                 1.1.0 - JSON-based parsing; clickable OSC 8 port/doc hyperlinks (-NoHyperlink)
                 1.2.0 - Clickable container-name details link; -Interactive stop/restart/logs/inspect
                 1.3.0 - Added Uptime column and live CPU%/MEM% from 'wslc stats'
                 1.4.0 - Exit code + IP columns, CPU/MEM threshold coloring, header summary
                 1.5.0 - Enriched images (Reference/Age/human Size) + -ImageDetails (platform, layers)

.PARAMETER RefreshIntervalSeconds
    Seconds to wait between refreshes. Range 1-3600. Defaults to 5.

.PARAMETER MaxIterations
    Number of refresh cycles before exiting. 0 (default) runs until Ctrl+C.

.PARAMETER ShowStopped
    Include stopped containers (maps to 'wslc container ps --all').

.PARAMETER HideImages
    Suppress the image list section for a more compact view.

.PARAMETER ImageDetails
    Enrich the image list with per-image 'wslc image inspect' data (platform and
    layer count). Adds a CLI call per image, so it is off by default.

.PARAMETER NoHyperlink
    Render URLs as plain 'text (url)' instead of clickable OSC 8 terminal
    hyperlinks. Use in terminals that do not support hyperlink escape sequences.

.PARAMETER Interactive
    Enable keyboard actions. Press a container's number to select it, then
    s=stop, r=restart (stop+start), l=logs, i=inspect. Press q to quit or Enter to
    refresh immediately. Without this switch the dashboard is passive (view-only).

.PARAMETER WslcPath
    Path or command name for the WSL container CLI. Defaults to 'wslc.exe'.

.EXAMPLE
    .\Watch-WslContainer.ps1
    Refreshes the running-container dashboard every 5 seconds until Ctrl+C.

.EXAMPLE
    .\Watch-WslContainer.ps1 -RefreshIntervalSeconds 2 -ShowStopped -MaxIterations 10
    Refreshes every 2 seconds, includes stopped containers, and stops after 10 cycles.

.EXAMPLE
    .\Watch-WslContainer.ps1 -Interactive
    Interactive dashboard: press a container's number, then s/r/l/i to stop, restart,
    view logs, or inspect it; q to quit.
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$RefreshIntervalSeconds = 5,
    [ValidateRange(0, [int]::MaxValue)]
    [int]$MaxIterations = 0,
    [switch]$ShowStopped,
    [switch]$HideImages,
    [switch]$ImageDetails,
    [switch]$NoHyperlink,
    [switch]$Interactive,
    [string]$WslcPath = 'wslc.exe'
)

$ErrorActionPreference = 'continue'
$scriptName = "$PSScriptRoot\$($MyInvocation.MyCommand.Name)"
$script:currentContainers = @()
$script:selectedName = $null
$script:quit = $false
$script:detailsDir = Join-Path ([System.IO.Path]::GetTempPath()) 'wslc-watch'

function main() {
    try {
        $wslc = resolve-wslc -path $WslcPath
        $wslVersion = get-wslVersion
        $iteration = 0

        if (-not (Test-Path $script:detailsDir)) {
            New-Item -ItemType Directory -Path $script:detailsDir -Force | Out-Null
        }

        while (($MaxIterations -eq 0 -or $iteration -lt $MaxIterations) -and -not $script:quit) {
            $iteration++
            render-dashboard -wslc $wslc -wslVersion $wslVersion -iteration $iteration

            if ($MaxIterations -ne 0 -and $iteration -ge $MaxIterations) {
                break
            }
            wait-interval -wslc $wslc
        }
    }
    catch {
        write-host "exception::$($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
        write-verbose "variables:$((get-variable -scope local).value | convertto-json -WarningAction SilentlyContinue -depth 2)"
        return 1
    }
}

function convertContainers([string]$json) {
    # State enum from the open-source WSL repo: 0=Invalid 1=Created 2=Running 3=Exited 4=Deleted.
    if ([string]::IsNullOrWhiteSpace($json)) { return @() }
    $items = $json | ConvertFrom-Json
    if ($null -eq $items) { return @() }

    $stateMap = @{ 0 = 'Invalid'; 1 = 'Created'; 2 = 'Running'; 3 = 'Exited'; 4 = 'Deleted' }

    $result = foreach ($item in @($items)) {
        $stateCode = [int]$item.State
        $stateLabel = if ($stateMap.ContainsKey($stateCode)) { $stateMap[$stateCode] } else { "State$stateCode" }
        [pscustomobject][ordered]@{
            Name    = $item.Name
            State   = $stateLabel
            Uptime  = get-uptime -stateLabel $stateLabel -stateChangedAt (convertUnixTime -seconds $item.StateChangedAt)
            Image   = $item.Image
            Ports   = convertPorts -ports $item.Ports
            ShortId = if ($item.Id) { $item.Id.Substring(0, [math]::Min(12, $item.Id.Length)) } else { $null }
            Id      = $item.Id
        }
    }

    return @($result)
}

function convertUnixTime([long]$seconds) {
    if (!$seconds) { return $null }
    return [DateTimeOffset]::FromUnixTimeSeconds($seconds).LocalDateTime
}

function get-uptime([string]$stateLabel, [datetime]$stateChangedAt) {
    if (!$stateChangedAt) { return '' }
    $span = (Get-Date) - $stateChangedAt
    $human = format-duration -span $span
    switch ($stateLabel) {
        'Running' { return "up $human" }
        'Exited' { return "exited $human ago" }
        'Created' { return 'created' }
        default { return $human }
    }
}

function format-duration([timespan]$span) {
    if ($span.TotalSeconds -lt 0) { return '0s' }
    if ($span.TotalSeconds -lt 60) { return ('{0}s' -f [int]$span.TotalSeconds) }
    if ($span.TotalMinutes -lt 60) { return ('{0}m' -f [int]$span.TotalMinutes) }
    if ($span.TotalHours -lt 24) { return ('{0}h {1}m' -f [int]$span.Hours, [int]$span.Minutes) }
    return ('{0}d {1}h' -f [int]$span.Days, [int]$span.Hours)
}

function get-statsMap([string]$wslc) {
    # Live resource stats keyed by full container Id (best-effort).
    $map = @{}
    try {
        $out = & $wslc stats --all --format json 2>$null
        if ($LASTEXITCODE -ne 0 -or !$out) { return $map }
        $items = ($out | Out-String) | ConvertFrom-Json
        foreach ($stat in @($items)) { $map[$stat.ID] = $stat }
    }
    catch { }
    return $map
}

function convertImages([string]$json, [hashtable]$detailMap = @{}) {
    if ([string]::IsNullOrWhiteSpace($json)) { return @() }
    $items = $json | ConvertFrom-Json
    if ($null -eq $items) { return @() }

    $result = foreach ($item in @($items)) {
        $id = "$($item.Id)" -replace '^sha256:', ''
        $repo = if ($item.Repository) { $item.Repository } else { '<none>' }
        $tag = if ($item.Tag) { $item.Tag } else { '<none>' }
        $created = convertUnixTime -seconds $item.Created
        $age = if ($created) { format-duration -span ((Get-Date) - $created) } else { '' }
        $obj = [ordered]@{
            Reference = '{0}:{1}' -f $repo, $tag
            Age       = $age
            Size      = if ($item.Size) { format-size -bytes $item.Size } else { '' }
            ShortId   = if ($id) { $id.Substring(0, [math]::Min(12, $id.Length)) } else { $null }
        }
        $detail = $detailMap[$id]
        if ($detail) {
            $obj.Platform = if ($detail.Os -and $detail.Architecture) { '{0}/{1}' -f $detail.Os, $detail.Architecture } else { "$($detail.Architecture)" }
            $obj.Layers = if ($detail.RootFS -and $detail.RootFS.Layers) { @($detail.RootFS.Layers).Count } else { 0 }
        }
        [pscustomobject]$obj
    }

    return @($result)
}

function format-size([long]$bytes) {
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

function get-imageDetailsMap([string]$wslc, [string]$json) {
    # Per-image 'image inspect' enrichment keyed by stripped Id. Best-effort.
    $map = @{}
    if ([string]::IsNullOrWhiteSpace($json)) { return $map }
    $items = $json | ConvertFrom-Json
    foreach ($item in @($items)) {
        $id = "$($item.Id)" -replace '^sha256:', ''
        if (!$id) { continue }
        try {
            $out = & $wslc image inspect $id 2>$null
            if ($LASTEXITCODE -ne 0 -or !$out) { continue }
            $detail = @(($out | Out-String) | ConvertFrom-Json)[0]
            if ($detail) { $map[$id] = $detail }
        }
        catch { }
    }
    return $map
}

function convertPorts($ports) {
    if (!$ports) { return '' }
    $parts = foreach ($port in @($ports)) {
        $proto = switch ([int]$port.Protocol) { 6 { 'tcp' } 17 { 'udp' } default { "proto$($port.Protocol)" } }
        $bind = if ($port.BindingAddress) { $port.BindingAddress } else { '0.0.0.0' }
        '{0}:{1}->{2}/{3}' -f $bind, $port.HostPort, $port.ContainerPort, $proto
    }
    return ($parts -join ', ')
}

function get-wslcJson([string]$wslc, [string[]]$arguments) {
    $output = & $wslc @arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "wslc $($arguments -join ' ') failed with exit code $LASTEXITCODE`r`n$($output -join "`r`n")"
    }
    return ($output | Out-String)
}

function get-wslVersion() {
    $wsl = Get-Command 'wsl.exe' -ErrorAction SilentlyContinue
    if (!$wsl) { return 'unknown' }
    $versionOutput = (& $wsl.Source '--version') 2>$null
    if ($versionOutput) {
        return ($versionOutput | Where-Object { $_ -match '\S' } | Select-Object -First 1).Trim()
    }
    return 'unknown'
}

function render-dashboard([string]$wslc, [string]$wslVersion, [int]$iteration) {
    # Per-refresh errors must not stop the loop; capture and display them instead.
    $errorMessage = $null
    $containers = @()
    $images = @()
    $links = @()
    $stats = @{}

    try {
        $psArgs = [collections.generic.list[string]]@('container', 'ls', '--format', 'json')
        if ($ShowStopped) { $psArgs.Add('--all') }
        $containerJson = get-wslcJson -wslc $wslc -arguments $psArgs
        $containers = @(convertContainers -json $containerJson)
        $links = @(get-containerLinks -json $containerJson)
        $stats = get-statsMap -wslc $wslc

        if (-not $HideImages) {
            $imageJson = get-wslcJson -wslc $wslc -arguments @('image', 'ls', '--format', 'json')
            $imageDetailMap = if ($ImageDetails) { get-imageDetailsMap -wslc $wslc -json $imageJson } else { @{} }
            $images = @(convertImages -json $imageJson -detailMap $imageDetailMap)
        }
    }
    catch {
        $errorMessage = $psitem.Exception.Message
    }

    # Expose the current container list for interactive selection.
    $script:currentContainers = $containers
    if ($script:selectedName -and ($containers.Name -notcontains $script:selectedName)) {
        $script:selectedName = $null
    }

    Clear-Host
    $scope = if ($ShowStopped) { 'all' } else { 'running' }
    $runningCount = @($containers | Where-Object State -eq 'Running').Count
    $totalCpu = 0.0; $totalMem = 0.0
    foreach ($s in $stats.Values) {
        $v = 0.0
        if ([double]::TryParse(("$($s.CPUPerc)" -replace '[%\s]', ''), [ref]$v)) { $totalCpu += $v }
        if ([double]::TryParse(("$($s.MemPerc)" -replace '[%\s]', ''), [ref]$v)) { $totalMem += $v }
    }
    write-host '========================================================================' -ForegroundColor DarkCyan
    write-host " WSL Container Dashboard   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')   refresh #$iteration" -ForegroundColor Cyan
    write-host " wsl: $wslVersion   |   wslc: $wslc" -ForegroundColor DarkGray
    write-host " containers ($scope): $($containers.Count)   running: $runningCount   images: $($images.Count)   interval: ${RefreshIntervalSeconds}s" -ForegroundColor DarkGray
    write-host (" total CPU: {0:0.00}%   total MEM: {1:0.00}%" -f $totalCpu, $totalMem) -ForegroundColor DarkGray
    write-host '========================================================================' -ForegroundColor DarkCyan

    if ($errorMessage) {
        write-host "`n[!] $errorMessage" -ForegroundColor Yellow
    }

    write-host "`nCONTAINERS ($scope)  " -ForegroundColor Green -NoNewline
    write-host '(container name links to inspect details)' -ForegroundColor DarkGray
    render-containerTable -wslc $wslc -containers $containers -stats $stats

    if ($links.Count -gt 0) {
        write-host "`nLINKS (published ports)" -ForegroundColor Green
        foreach ($link in $links) {
            $label = format-hyperlink -url $link.Url -text $link.Url
            write-host ('  {0,-20} ' -f $link.Name) -ForegroundColor Gray -NoNewline
            write-host $label -ForegroundColor Blue
        }
    }

    if (-not $HideImages) {
        write-host "`nIMAGES" -ForegroundColor Green
        if ($images.Count -gt 0) {
            write-host (($images | Format-Table -AutoSize | Out-String).TrimEnd())
        }
        else {
            write-host '  (none)' -ForegroundColor DarkGray
        }
    }

    $docs = format-hyperlink -url 'https://learn.microsoft.com/windows/wsl/wsl-container' -text 'WSL container docs'
    if ($Interactive) {
        $sel = if ($script:selectedName) { $script:selectedName } else { '(none)' }
        write-host "`nINTERACTIVE  selected: " -ForegroundColor Green -NoNewline
        write-host $sel -ForegroundColor Yellow
        write-host '  [number]=select   s=stop  r=restart  l=logs  i=inspect   Enter=refresh  q=quit' -ForegroundColor DarkGray
    }
    else {
        write-host "`nPress Ctrl+C to exit.   (add -Interactive for stop/restart/logs)" -ForegroundColor DarkGray
    }
    write-host $docs -ForegroundColor DarkGray
}

function render-containerTable([string]$wslc, [object[]]$containers, [hashtable]$stats) {
    if (!$containers -or $containers.Count -eq 0) {
        write-host '  (none)' -ForegroundColor DarkGray
        return
    }

    # Compute column widths from plain text (hyperlink escapes have zero display width).
    $nameW = [math]::Max(4, ($containers.Name | Measure-Object -Maximum -Property Length).Maximum)
    $upW = [math]::Max(10, (($containers.Uptime | Measure-Object -Maximum -Property Length).Maximum) + 5)
    $imageW = [math]::Max(5, ($containers.Image | Measure-Object -Maximum -Property Length).Maximum)
    $portsW = [math]::Max(5, (@($containers.Ports | ForEach-Object { "$_".Length }) + 5 | Measure-Object -Maximum).Maximum)
    $ipW = 15

    $headerFmt = '  {0,-3} {1,-' + $nameW + '} {2,-8} {3,-' + $upW + '} {4,-7} {5,-8} {6,-' + $ipW + '} {7,-' + $imageW + '} {8,-' + $portsW + '} {9}'
    $upCellFmt = '{0,-' + $upW + '} '
    $tailFmt = '{0,-' + $ipW + '} {1,-' + $imageW + '} {2,-' + $portsW + '} {3}'
    write-host ($headerFmt -f '#', 'NAME', 'STATE', 'UPTIME', 'CPU%', 'MEM%', 'IP', 'IMAGE', 'PORTS', 'ID') -ForegroundColor DarkGray

    for ($i = 0; $i -lt $containers.Count; $i++) {
        $c = $containers[$i]
        $index = $i + 1
        $isSelected = $Interactive -and ($script:selectedName -eq $c.Name)
        $marker = if ($isSelected) { '>' } else { ' ' }

        # Inspect-derived details (path for name link, exit code, IP).
        $details = write-detailsFile -wslc $wslc -container $c
        $namePadded = "$($c.Name)".PadRight($nameW)
        $nameCell = if ($details.Path) { format-hyperlink -url ("file:///" + ($details.Path -replace '\\', '/')) -text $namePadded } else { $namePadded }

        $uptimeText = $c.Uptime
        if ($c.State -eq 'Exited' -and $null -ne $details.ExitCode) {
            $uptimeText = $uptimeText -replace '^exited ', "exited ($($details.ExitCode)) "
        }

        $stat = $stats[$c.Id]
        $cpu = if ($stat) { "$($stat.CPUPerc)" } else { '-' }
        $mem = if ($stat) { "$($stat.MemPerc)" } else { '-' }
        $cpuColor = get-percentColor -pct $cpu
        $memColor = get-percentColor -pct $mem
        $ip = if ($details.Ip) { $details.Ip } else { '' }

        $stateColor = switch ($c.State) { 'Running' { 'Green' } 'Exited' { 'DarkGray' } 'Created' { 'Cyan' } default { 'Yellow' } }
        $rowColor = if ($isSelected) { 'Yellow' } else { 'Gray' }

        write-host ('{0} {1,-3} ' -f $marker, $index) -ForegroundColor $rowColor -NoNewline
        write-host $nameCell -ForegroundColor $rowColor -NoNewline
        write-host (' {0,-8} ' -f $c.State) -ForegroundColor $stateColor -NoNewline
        write-host ($upCellFmt -f $uptimeText) -ForegroundColor $rowColor -NoNewline
        write-host ('{0,-7} ' -f $cpu) -ForegroundColor $cpuColor -NoNewline
        write-host ('{0,-8} ' -f $mem) -ForegroundColor $memColor -NoNewline
        write-host ($tailFmt -f $ip, $c.Image, "$($c.Ports)", $c.ShortId) -ForegroundColor $rowColor
    }
}

function get-percentColor([string]$pct) {
    $value = 0.0
    if ([double]::TryParse(($pct -replace '[%\s]', ''), [ref]$value)) {
        if ($value -ge 80) { return 'Red' }
        if ($value -ge 50) { return 'Yellow' }
        return 'Green'
    }
    return 'DarkGray'
}

function write-detailsFile([string]$wslc, [object]$container) {
    # Writes the container's inspect JSON to a temp file and parses a few useful
    # fields (exit code, IP) from it. Returns [pscustomobject]@{ Path; ExitCode; Ip }.
    # Best-effort: on failure returns an object with $null fields.
    $result = [pscustomobject]@{ Path = $null; ExitCode = $null; Ip = $null }
    try {
        if (!$container.ShortId) { return $result }
        $path = Join-Path $script:detailsDir "$($container.ShortId).json"
        $json = & $wslc container inspect $container.Name 2>$null
        if ($LASTEXITCODE -ne 0 -or !$json) { return $result }
        $text = $json | Out-String
        $text | Set-Content -Path $path -Encoding utf8
        $result.Path = $path
        try {
            $parsed = @($text | ConvertFrom-Json)[0]
            $result.ExitCode = $parsed.State.ExitCode
            $net = $parsed.NetworkSettings.Networks
            if ($net) {
                $first = $net.PSObject.Properties | Select-Object -First 1
                if ($first) { $result.Ip = $first.Value.IPAddress }
            }
        }
        catch { }
        return $result
    }
    catch {
        return $result
    }
}

function get-containerLinks([string]$json) {
    # Build clickable host URLs for running containers that publish TCP ports.
    if ([string]::IsNullOrWhiteSpace($json)) { return @() }
    $items = $json | ConvertFrom-Json
    if ($null -eq $items) { return @() }

    $links = [collections.generic.list[object]]::new()
    foreach ($item in @($items)) {
        # State 2 = Running; only running containers actually expose mapped ports.
        if ([int]$item.State -ne 2 -or !$item.Ports) { continue }
        foreach ($port in @($item.Ports)) {
            if ([int]$port.Protocol -ne 6) { continue } # 6 = TCP
            $bind = if ($port.BindingAddress -and $port.BindingAddress -ne '0.0.0.0') { $port.BindingAddress } else { 'localhost' }
            $links.Add([pscustomobject]@{
                    Name = $item.Name
                    Url  = "http://$($bind):$($port.HostPort)"
                })
        }
    }
    return $links.ToArray()
}

function format-hyperlink([string]$url, [string]$text) {
    # OSC 8 terminal hyperlink (Windows Terminal / VS Code). Falls back to 'text (url)'
    # in unsupported terminals or when -NoHyperlink is set.
    if (!$text) { $text = $url }
    if ($NoHyperlink) {
        return "$text ($url)"
    }
    $esc = [char]27
    return "$esc]8;;$url$esc\$text$esc]8;;$esc\"
}

function wait-interval([string]$wslc) {
    # Passive mode: simple sleep. Interactive mode: poll the keyboard during the wait
    # and act on keystrokes (terminal hyperlinks cannot execute commands, so actions
    # are driven by keys instead of clicks).
    if (-not $Interactive) {
        Start-Sleep -Seconds $RefreshIntervalSeconds
        return
    }

    $deadline = (Get-Date).AddSeconds($RefreshIntervalSeconds)
    while ((Get-Date) -lt $deadline -and -not $script:quit) {
        $pressed = $false
        try { $pressed = [Console]::KeyAvailable } catch { Start-Sleep -Seconds $RefreshIntervalSeconds; return }
        if ($pressed) {
            $key = [Console]::ReadKey($true)
            if (handle-key -wslc $wslc -key $key) { return }
        }
        Start-Sleep -Milliseconds 120
    }
}

function handle-key([string]$wslc, $key) {
    # Returns $true when the dashboard should redraw immediately.
    $ch = "$($key.KeyChar)"
    if ($ch -match '^[0-9]$') {
        $index = [int]$ch
        if ($index -ge 1 -and $index -le $script:currentContainers.Count) {
            $script:selectedName = $script:currentContainers[$index - 1].Name
        }
        return $true
    }
    switch -regex ($ch) {
        '^[qQ]$' { $script:quit = $true; return $true }
        '^[sS]$' { invoke-containerAction -wslc $wslc -action 'stop'; return $true }
        '^[rR]$' { invoke-containerAction -wslc $wslc -action 'restart'; return $true }
        '^[lL]$' { invoke-containerAction -wslc $wslc -action 'logs'; return $true }
        '^[iI]$' { invoke-containerAction -wslc $wslc -action 'inspect'; return $true }
    }
    if ($key.Key -eq 'Enter' -or $ch -eq ' ') { return $true }
    return $false
}

function invoke-containerAction([string]$wslc, [string]$action) {
    $name = $script:selectedName
    if (!$name) {
        write-host "`n  No container selected - press its number first." -ForegroundColor Yellow
        Start-Sleep -Milliseconds 900
        return
    }

    switch ($action) {
        'stop' { & $wslc container stop $name *> $null }
        'start' { & $wslc container start $name *> $null }
        'restart' {
            & $wslc container stop $name *> $null
            & $wslc container start $name *> $null
        }
        'logs' {
            Clear-Host
            write-host "logs: $name  (last 40 lines)" -ForegroundColor Cyan
            write-host ''
            & $wslc logs -n 40 $name
            read-anyKey
        }
        'inspect' {
            Clear-Host
            write-host "inspect: $name" -ForegroundColor Cyan
            write-host ''
            & $wslc container inspect $name
            read-anyKey
        }
    }
}

function read-anyKey() {
    write-host "`n  -- press any key to return to the dashboard --" -ForegroundColor DarkGray
    try { [void][Console]::ReadKey($true) } catch { Start-Sleep -Seconds 2 }
}

function resolve-wslc([string]$path) {
    $command = Get-Command $path -ErrorAction SilentlyContinue
    if (!$command) {
        throw "wslc CLI '$path' not found. Update WSL with 'wsl --update --pre-release' to install the WSL container feature."
    }
    return $command.Source
}

function write-console($message, [consoleColor]$foregroundColor = 'White', [switch]$verbose, [switch]$err, [switch]$warn) {
    if (!$message) { return }
    if ($message.gettype().name -ine 'string') {
        $message = $message | convertto-json -Depth 10
    }

    if ($verbose) {
        write-verbose($message)
    }
    else {
        write-host($message) -ForegroundColor $foregroundColor
    }

    if ($warn) {
        write-warning($message)
    }
    elseif ($err) {
        write-error($message)
        throw
    }
}

main
