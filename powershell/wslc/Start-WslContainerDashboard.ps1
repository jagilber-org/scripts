<#
.SYNOPSIS
    Serves a local web dashboard with working Stop/Start/Restart/Logs buttons for WSL containers.

.DESCRIPTION
    Starts a lightweight HTTP server bound to 127.0.0.1 that renders an auto-refreshing
    HTML dashboard of WSL containers (via 'wslc container ls --format json') with real
    clickable buttons to stop, start, restart, view logs, and inspect each container.
    Unlike terminal hyperlinks (which can only open URLs), these buttons POST back to the
    local server, which executes the corresponding 'wslc' command.

    Security: the listener binds only to the loopback address (127.0.0.1); container
    lifecycle actions are restricted to a fixed allow-list (stop/start/restart/remove); the
    target container name is validated against the live container list before any command
    runs; image removal validates the reference against the live image list; and create
    (run) / pull inputs (image reference, container name, port mappings) are regex-validated
    so they can never be interpreted as option flags. wslc is always invoked with an
    argument array (never a shell string), so there is no command injection surface. The
    image search proxies Docker Hub's public read-only API (the only outbound call; the
    query is validated and URL-encoded). Press Ctrl+C to stop the server.

.NOTES
    File Name  : Start-WslContainerDashboard.ps1
    Author     : jagilber
    Requires   : Windows Subsystem for Linux (WSL) with the WSL container feature
    Disclaimer : Provided AS-IS without warranty.
    Version    : 1.3.0
    Changelog  : 1.0.0 - Initial release
                 1.1.0 - Added Uptime and live CPU%/Mem/PIDs columns from 'wslc stats'
                 1.2.0 - Filter/sort, CPU/Mem threshold coloring, copy-id, confirm-stop,
                         logs auto-follow, prune button, graceful wslc-missing banner
                 1.2.1 - Fixed logs auto-follow flicker: sequential stale-guarded poll
                         loop (no overlapping fetches) and scroll-pin only when at bottom
                 1.3.0 - Added Images section (Reference/Age/Size + optional platform/layers/
                         ports details) with validated image-inspect endpoint
                 1.3.1 - Auto-bind first free port at/above -Port (clear message instead of an
                         HttpListener stack trace when the port is already in use)
                 1.4.0 - Create-and-run container form and pull/update image controls
                         (validated image ref / name / port mappings; per-image Update button)
                 1.5.0 - Action log (in-memory + temp file) with an in-page viewer; optional
                         container command field (e.g. 'sleep infinity') on the create form
                 1.6.0 - Remove container (force) and remove image (rmi) buttons with
                         confirmation and validated targets
                 1.6.1 - Image details (platform/layers/ports) always shown (removed toggle)
                 1.6.2 - Show a '(no output)' placeholder for empty container logs
                 1.7.0 - Docker Hub image search (validated query, proxied) with per-result Pull
                 1.7.1 - Local images offered as a dropdown (datalist) on the create form
                 1.7.2 - Selecting a local image prefills name/ports and disables the command
                         for service images (prevents overriding the image's own process)
                 1.8.0 - Environment variables field on the create form (-e KEY=VALUE, validated)
                 1.9.0 - Registry dropdown for search (Docker Hub + Quay.io) with normalized results
                 1.9.1 - Added Microsoft (MCR) to search (cached catalog, substring filter)

.PARAMETER Port
    TCP port for the loopback dashboard server. Range 1024-65535. Defaults to 8973.

.PARAMETER RefreshSeconds
    Client-side auto-refresh interval in seconds. Range 1-3600. Defaults to 5.

.PARAMETER NoLaunch
    Do not open the default browser automatically when the server starts.

.PARAMETER WslcPath
    Path or command name for the WSL container CLI. Defaults to 'wslc.exe'.

.EXAMPLE
    .\Start-WslContainerDashboard.ps1
    Starts the dashboard on http://127.0.0.1:8973 and opens it in the browser.

.EXAMPLE
    .\Start-WslContainerDashboard.ps1 -Port 9090 -RefreshSeconds 2 -NoLaunch
    Serves on port 9090, refreshing every 2 seconds, without auto-opening a browser.
#>

[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 8973,
    [ValidateRange(1, 3600)]
    [int]$RefreshSeconds = 5,
    [switch]$NoLaunch,
    [string]$WslcPath = 'wslc.exe'
)

$ErrorActionPreference = 'continue'
$scriptName = "$PSScriptRoot\$($MyInvocation.MyCommand.Name)"
$script:allowedOps = @('stop', 'start', 'restart', 'remove')
$script:actionLog = [System.Collections.Generic.List[object]]::new()
$script:actionLogMax = 200
$script:logPath = Join-Path ([System.IO.Path]::GetTempPath()) 'wslc-dashboard.log'
$script:mcrCatalog = $null

function main() {
    $listener = $null
    try {
        # Resolve wslc but do not fail startup if it is missing - the page still loads
        # and shows a banner (the /api/containers endpoint reports the error gracefully).
        $wslc = $WslcPath
        try { $wslc = resolve-wslc -path $WslcPath }
        catch { write-console $psitem.Exception.Message -foregroundColor Yellow -warn }

        # Bind the first free port at or above $Port. HttpListener throws when the exact
        # prefix is already registered (e.g. another dashboard instance still running),
        # so try a small range instead of failing outright.
        $listener = start-listener -startPort $Port -maxAttempts 20
        $prefix = $listener.Prefixes | Select-Object -First 1
        if ("$prefix" -notmatch ":$Port/") {
            write-console "Port $Port was in use; using $prefix instead." -foregroundColor Yellow
        }

        write-console "WSL container dashboard listening at $prefix" -foregroundColor Green
        write-console "Action log: $script:logPath" -foregroundColor DarkGray
        write-console "Press Ctrl+C to stop." -foregroundColor DarkGray

        if (-not $NoLaunch) {
            Start-Process $prefix | Out-Null
        }

        # Async accept loop so Ctrl+C can interrupt between polls.
        while ($listener.IsListening) {
            $task = $listener.GetContextAsync()
            while (-not $task.Wait(200)) { }
            $context = $task.Result
            handle-request -context $context -wslc $wslc
        }
    }
    catch {
        write-host "exception::$($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
        write-verbose "variables:$((get-variable -scope local).value | convertto-json -WarningAction SilentlyContinue -depth 2)"
        return 1
    }
    finally {
        if ($listener -and $listener.IsListening) {
            $listener.Stop()
            $listener.Close()
            write-console "Server stopped." -foregroundColor DarkGray
        }
    }
}

function start-listener([int]$startPort, [int]$maxAttempts) {
    # Returns a started HttpListener bound to the first free loopback port at or above
    # $startPort. Throws a clear message if none of the attempted ports are available.
    for ($port = $startPort; $port -lt ($startPort + $maxAttempts) -and $port -le 65535; $port++) {
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add("http://127.0.0.1:$port/")
        try {
            $listener.Start()
            return $listener
        }
        catch [System.Net.HttpListenerException] {
            $listener.Close()
            continue
        }
        catch {
            $listener.Close()
            throw
        }
    }
    throw "No free loopback port found in range $startPort-$($startPort + $maxAttempts - 1). Close the process using it (likely another dashboard instance) or pass -Port <n>."
}

function get-containers([string]$wslc) {
    $output = & $wslc container ls --all --format json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "wslc container ls failed: $($output -join ' ')"
    }
    $json = $output | Out-String
    if ([string]::IsNullOrWhiteSpace($json)) { return @() }
    $items = $json | ConvertFrom-Json
    if ($null -eq $items) { return @() }

    $stateMap = @{ 0 = 'Invalid'; 1 = 'Created'; 2 = 'Running'; 3 = 'Exited'; 4 = 'Deleted' }
    $statsMap = get-statsMap -wslc $wslc

    $result = foreach ($item in @($items)) {
        $ports = @()
        foreach ($port in @($item.Ports)) {
            $proto = switch ([int]$port.Protocol) { 6 { 'tcp' } 17 { 'udp' } default { "proto$($port.Protocol)" } }
            $bind = if ($port.BindingAddress) { $port.BindingAddress } else { '0.0.0.0' }
            $ports += ('{0}:{1}->{2}/{3}' -f $bind, $port.HostPort, $port.ContainerPort, $proto)
        }
        $stateLabel = if ($stateMap.ContainsKey([int]$item.State)) { $stateMap[[int]$item.State] } else { "State$($item.State)" }
        $changed = if ($item.StateChangedAt) { [DateTimeOffset]::FromUnixTimeSeconds([long]$item.StateChangedAt).LocalDateTime } else { $null }
        $stat = $statsMap[$item.Id]
        [pscustomobject]@{
            Name     = $item.Name
            State    = $stateLabel
            Uptime   = get-uptime -stateLabel $stateLabel -stateChangedAt $changed
            Image    = $item.Image
            Ports    = ($ports -join ', ')
            ShortId  = if ($item.Id) { $item.Id.Substring(0, [math]::Min(12, $item.Id.Length)) } else { '' }
            CPUPerc  = if ($stat) { "$($stat.CPUPerc)" } else { '' }
            MemPerc  = if ($stat) { "$($stat.MemPerc)" } else { '' }
            MemUsage = if ($stat) { "$($stat.MemUsage)" } else { '' }
            PIDs     = if ($stat) { $stat.PIDs } else { '' }
        }
    }
    return @($result)
}

function get-statsMap([string]$wslc) {
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

function get-images([string]$wslc, [bool]$includeDetails) {
    $output = & $wslc image ls --format json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "wslc image ls failed: $($output -join ' ')"
    }
    $json = $output | Out-String
    if ([string]::IsNullOrWhiteSpace($json)) { return @() }
    $items = $json | ConvertFrom-Json
    if ($null -eq $items) { return @() }

    $detailMap = if ($includeDetails) { get-imageDetailsMap -wslc $wslc -json $json } else { @{} }

    $result = foreach ($item in @($items)) {
        $id = "$($item.Id)" -replace '^sha256:', ''
        $repo = if ($item.Repository) { $item.Repository } else { '<none>' }
        $tag = if ($item.Tag) { $item.Tag } else { '<none>' }
        $created = if ($item.Created) { [DateTimeOffset]::FromUnixTimeSeconds([long]$item.Created).LocalDateTime } else { $null }
        $age = if ($created) { format-duration -span ((Get-Date) - $created) } else { '' }
        $detail = $detailMap[$id]
        [pscustomobject]@{
            Reference    = '{0}:{1}' -f $repo, $tag
            Tag          = $tag
            Age          = $age
            Size         = if ($item.Size) { format-size -bytes $item.Size } else { '' }
            Dangling     = ($repo -eq '<none>' -or $tag -eq '<none>')
            Platform     = if ($detail -and $detail.Os -and $detail.Architecture) { '{0}/{1}' -f $detail.Os, $detail.Architecture } else { '' }
            Layers       = if ($detail -and $detail.RootFS -and $detail.RootFS.Layers) { @($detail.RootFS.Layers).Count } else { '' }
            ExposedPorts = if ($detail -and $detail.Config -and $detail.Config.ExposedPorts) { (($detail.Config.ExposedPorts.PSObject.Properties.Name) -join ', ') } else { '' }
            ShortId      = if ($id) { $id.Substring(0, [math]::Min(12, $id.Length)) } else { '' }
        }
    }
    return @($result)
}

function get-validatedImageRef([System.Net.HttpListenerContext]$context, [string]$wslc) {
    # Only accept a reference / short id that currently exists, preventing arbitrary
    # values reaching wslc (mirrors get-validatedName for containers).
    $ref = $context.Request.QueryString['ref']
    if ([string]::IsNullOrWhiteSpace($ref)) { return $null }
    $images = @(get-images -wslc $wslc -includeDetails $false)
    foreach ($image in $images) {
        if ($ref -eq $image.Reference -or $ref -eq $image.ShortId) { return $ref }
    }
    return $null
}

function handle-request([System.Net.HttpListenerContext]$context, [string]$wslc) {
    try {
        $path = $context.Request.Url.AbsolutePath
        $method = $context.Request.HttpMethod

        switch -regex ($path) {
            '^/$' {
                write-response -context $context -status 200 -contentType 'text/html; charset=utf-8' -body (get-pageHtml)
                return
            }
            '^/api/containers$' {
                try {
                    $body = ConvertTo-Json @(get-containers -wslc $wslc) -Depth 4
                    if (!$body) { $body = '[]' }
                    write-response -context $context -status 200 -contentType 'application/json' -body $body
                }
                catch {
                    # Graceful degradation: surface a message the page can display as a banner
                    # (e.g. when wslc is missing) instead of returning a bare 500.
                    $err = ConvertTo-Json @{ error = "Unable to query wslc: $($psitem.Exception.Message)" }
                    write-response -context $context -status 200 -contentType 'application/json' -body $err
                }
                return
            }
            '^/api/images$' {
                try {
                    $details = ($context.Request.QueryString['details'] -eq '1')
                    $body = ConvertTo-Json @(get-images -wslc $wslc -includeDetails $details) -Depth 4
                    if (!$body) { $body = '[]' }
                    write-response -context $context -status 200 -contentType 'application/json' -body $body
                }
                catch {
                    $err = ConvertTo-Json @{ error = "Unable to query wslc: $($psitem.Exception.Message)" }
                    write-response -context $context -status 200 -contentType 'application/json' -body $err
                }
                return
            }
            '^/api/prune$' {
                if ($method -ne 'POST') { write-response -context $context -status 405 -contentType 'text/plain' -body 'method not allowed'; return }
                $out = & $wslc container prune 2>&1
                $ok = ($LASTEXITCODE -eq 0)
                add-actionLog -action 'prune' -target 'stopped containers' -ok $ok -message ("$out")
                write-response -context $context -status 200 -contentType 'application/json' -body (ConvertTo-Json @{ ok = $ok; message = ("$out").Trim() })
                return
            }
            '^/api/actionlog$' {
                $body = ConvertTo-Json @($script:actionLog | Select-Object -Last 100) -Depth 3
                if (!$body) { $body = '[]' }
                write-response -context $context -status 200 -contentType 'application/json' -body $body
                return
            }
            '^/api/search$' {
                invoke-search -context $context
                return
            }
            '^/api/action$' {
                if ($method -ne 'POST') { write-response -context $context -status 405 -contentType 'text/plain' -body 'method not allowed'; return }
                invoke-action -context $context -wslc $wslc
                return
            }
            '^/api/run$' {
                if ($method -ne 'POST') { write-response -context $context -status 405 -contentType 'text/plain' -body 'method not allowed'; return }
                invoke-run -context $context -wslc $wslc
                return
            }
            '^/api/pull$' {
                if ($method -ne 'POST') { write-response -context $context -status 405 -contentType 'text/plain' -body 'method not allowed'; return }
                invoke-pull -context $context -wslc $wslc
                return
            }
            '^/api/removeimage$' {
                if ($method -ne 'POST') { write-response -context $context -status 405 -contentType 'text/plain' -body 'method not allowed'; return }
                invoke-removeImage -context $context -wslc $wslc
                return
            }
            '^/api/logs$' {
                $name = get-validatedName -context $context -wslc $wslc
                if (!$name) { write-response -context $context -status 400 -contentType 'text/plain' -body 'unknown container'; return }
                $logs = (& $wslc logs -n 200 $name 2>&1 | Out-String)
                write-response -context $context -status 200 -contentType 'text/plain; charset=utf-8' -body $logs
                return
            }
            '^/api/inspect$' {
                $name = get-validatedName -context $context -wslc $wslc
                if (!$name) { write-response -context $context -status 400 -contentType 'text/plain' -body 'unknown container'; return }
                $inspect = (& $wslc container inspect $name 2>&1 | Out-String)
                write-response -context $context -status 200 -contentType 'application/json; charset=utf-8' -body $inspect
                return
            }
            '^/api/imageinspect$' {
                $ref = get-validatedImageRef -context $context -wslc $wslc
                if (!$ref) { write-response -context $context -status 400 -contentType 'text/plain' -body 'unknown image'; return }
                $inspect = (& $wslc image inspect $ref 2>&1 | Out-String)
                write-response -context $context -status 200 -contentType 'application/json; charset=utf-8' -body $inspect
                return
            }
            default {
                write-response -context $context -status 404 -contentType 'text/plain' -body 'not found'
            }
        }
    }
    catch {
        write-console "request error: $($psitem.Exception.Message)" -foregroundColor Yellow
        try { write-response -context $context -status 500 -contentType 'text/plain' -body 'server error' } catch { }
    }
}

function get-validatedName([System.Net.HttpListenerContext]$context, [string]$wslc) {
    # Only accept names that currently exist, preventing arbitrary values reaching wslc.
    $name = $context.Request.QueryString['name']
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    $names = @(get-containers -wslc $wslc | Select-Object -ExpandProperty Name)
    if ($names -contains $name) { return $name }
    return $null
}

function invoke-action([System.Net.HttpListenerContext]$context, [string]$wslc) {
    $reader = [System.IO.StreamReader]::new($context.Request.InputStream, $context.Request.ContentEncoding)
    $rawBody = $reader.ReadToEnd()
    $reader.Close()

    $data = $null
    try { $data = $rawBody | ConvertFrom-Json } catch { }
    $op = "$($data.op)".ToLowerInvariant()
    $name = "$($data.name)"

    $names = @(get-containers -wslc $wslc | Select-Object -ExpandProperty Name)
    if ($script:allowedOps -notcontains $op) {
        write-response -context $context -status 400 -contentType 'application/json' -body (ConvertTo-Json @{ ok = $false; message = "unsupported op '$op'" })
        return
    }
    if ($names -notcontains $name) {
        write-response -context $context -status 400 -contentType 'application/json' -body (ConvertTo-Json @{ ok = $false; message = "unknown container '$name'" })
        return
    }

    switch ($op) {
        'stop' { $out = & $wslc container stop $name 2>&1 }
        'start' { $out = & $wslc container start $name 2>&1 }
        'restart' {
            $out = & $wslc container stop $name 2>&1
            $out += & $wslc container start $name 2>&1
        }
        'remove' { $out = & $wslc container remove --force $name 2>&1 }
    }
    $ok = ($LASTEXITCODE -eq 0)
    add-actionLog -action $op -target $name -ok $ok -message ("$out")
    write-response -context $context -status 200 -contentType 'application/json' -body (ConvertTo-Json @{ ok = $ok; message = ("$out").Trim() })
}

function write-response([System.Net.HttpListenerContext]$context, [int]$status, [string]$contentType, [string]$body) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$body")
    $context.Response.StatusCode = $status
    $context.Response.ContentType = $contentType
    $context.Response.ContentLength64 = $bytes.Length
    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $context.Response.OutputStream.Close()
}

function read-jsonBody([System.Net.HttpListenerContext]$context) {
    $reader = [System.IO.StreamReader]::new($context.Request.InputStream, $context.Request.ContentEncoding)
    $raw = $reader.ReadToEnd()
    $reader.Close()
    try { return $raw | ConvertFrom-Json } catch { return $null }
}

function add-actionLog([string]$action, [string]$target, [bool]$ok, [string]$message) {
    # Record a dashboard action in the in-memory ring buffer (served to the page) and
    # append it to a temp log file. Best-effort - logging never breaks an action.
    $entry = [pscustomobject]@{
        Time    = (Get-Date).ToString('HH:mm:ss')
        Action  = $action
        Target  = $target
        Ok      = $ok
        Message = ("$message").Trim()
    }
    $script:actionLog.Add($entry)
    if ($script:actionLog.Count -gt $script:actionLogMax) {
        $script:actionLog.RemoveRange(0, $script:actionLog.Count - $script:actionLogMax)
    }
    write-console ("action: {0} {1} -> {2}" -f $action, $target, $(if ($ok) { 'ok' } else { 'failed' })) -foregroundColor $(if ($ok) { 'Cyan' } else { 'Yellow' })
    try {
        $line = '{0} [{1}] {2} {3} :: {4}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $(if ($ok) { 'ok' } else { 'ERR' }), $action, $target, $entry.Message
        Add-Content -Path $script:logPath -Value $line -Encoding utf8
    }
    catch { }
}

function test-imageRef([string]$ref) {
    # Repository[:tag][@digest] with optional registry host; no leading dash / whitespace,
    # so the value can never be interpreted by wslc as an option flag.
    return ("$ref" -match '^[A-Za-z0-9][A-Za-z0-9_./:@-]*$')
}

function test-containerName([string]$name) {
    return ("$name" -match '^[A-Za-z0-9][A-Za-z0-9_.-]*$')
}

function test-publishSpec([string]$spec) {
    # [ip:]hostPort:containerPort[/proto]
    return ("$spec" -match '^(\d{1,3}(\.\d{1,3}){3}:)?\d{1,5}:\d{1,5}(/(tcp|udp))?$')
}

function test-searchQuery([string]$q) {
    return ("$q" -match '^[A-Za-z0-9][A-Za-z0-9._/ -]{0,99}$')
}

function invoke-run([System.Net.HttpListenerContext]$context, [string]$wslc) {
    # Create and run a container. All user input is validated and passed to wslc as a
    # distinct argument array (never a shell string), so there is no injection surface.
    $data = read-jsonBody -context $context
    $image = "$($data.image)".Trim()
    $name = "$($data.name)".Trim()
    $publishRaw = "$($data.publish)".Trim()
    $commandRaw = "$($data.command)".Trim()
    $envRaw = "$($data.env)".Trim()
    $detach = [bool]$data.detach

    if (-not (test-imageRef $image)) {
        write-response -context $context -status 400 -contentType 'application/json' -body (ConvertTo-Json @{ ok = $false; message = 'invalid or missing image reference' })
        return
    }
    $arguments = [collections.generic.list[string]]@('run')
    if ($detach) { $arguments.Add('-d') }
    if ($name) {
        if (-not (test-containerName $name)) {
            write-response -context $context -status 400 -contentType 'application/json' -body (ConvertTo-Json @{ ok = $false; message = "invalid container name '$name'" })
            return
        }
        $arguments.Add('--name'); $arguments.Add($name)
    }
    if ($publishRaw) {
        foreach ($spec in ($publishRaw -split '[,\s]+' | Where-Object { $_ })) {
            if (-not (test-publishSpec $spec)) {
                write-response -context $context -status 400 -contentType 'application/json' -body (ConvertTo-Json @{ ok = $false; message = "invalid port mapping '$spec'" })
                return
            }
            $arguments.Add('-p'); $arguments.Add($spec)
        }
    }
    if ($envRaw) {
        # KEY=VALUE pairs, separated by ';' or newlines. Key must be a valid env name;
        # value is arbitrary (passed as the argument to -e, so it cannot inject a flag).
        foreach ($pair in ($envRaw -split '[;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
            if ($pair -notmatch '^[A-Za-z_][A-Za-z0-9_]*=') {
                write-response -context $context -status 400 -contentType 'application/json' -body (ConvertTo-Json @{ ok = $false; message = "invalid env var '$pair' (expected KEY=VALUE)" })
                return
            }
            $arguments.Add('-e'); $arguments.Add($pair)
        }
    }
    $arguments.Add($image)
    # Everything after the image is the container's command/args (positional, not wslc
    # options), so passing tokens as-is cannot inject wslc flags. Simple whitespace split.
    if ($commandRaw) {
        foreach ($tok in ($commandRaw -split '\s+' | Where-Object { $_ })) { $arguments.Add($tok) }
    }

    $out = & $wslc @arguments 2>&1
    $ok = ($LASTEXITCODE -eq 0)
    add-actionLog -action 'run' -target $image -ok $ok -message ("$out")
    write-response -context $context -status 200 -contentType 'application/json' -body (ConvertTo-Json @{ ok = $ok; message = ("$out").Trim() })
}

function invoke-pull([System.Net.HttpListenerContext]$context, [string]$wslc) {
    # Download / update an image. Reference is validated and passed as a single argument.
    $data = read-jsonBody -context $context
    $image = "$($data.image)".Trim()
    if (-not (test-imageRef $image)) {
        write-response -context $context -status 400 -contentType 'application/json' -body (ConvertTo-Json @{ ok = $false; message = 'invalid or missing image reference' })
        return
    }
    write-console "action: pull $image" -foregroundColor Cyan
    $out = & $wslc pull $image 2>&1
    $ok = ($LASTEXITCODE -eq 0)
    add-actionLog -action 'pull' -target $image -ok $ok -message ("$out")
    write-response -context $context -status 200 -contentType 'application/json' -body (ConvertTo-Json @{ ok = $ok; message = ("$out").Trim() })
}

function invoke-removeImage([System.Net.HttpListenerContext]$context, [string]$wslc) {
    # Remove an image. The reference is validated against the live image list before use.
    $data = read-jsonBody -context $context
    $ref = "$($data.ref)".Trim()
    $images = @(get-images -wslc $wslc -includeDetails $false)
    $valid = $false
    foreach ($im in $images) { if ($ref -eq $im.Reference -or $ref -eq $im.ShortId) { $valid = $true; break } }
    if (-not $valid) {
        write-response -context $context -status 400 -contentType 'application/json' -body (ConvertTo-Json @{ ok = $false; message = "unknown image '$ref'" })
        return
    }
    $out = & $wslc rmi --force $ref 2>&1
    $ok = ($LASTEXITCODE -eq 0)
    add-actionLog -action 'rmi' -target $ref -ok $ok -message ("$out")
    write-response -context $context -status 200 -contentType 'application/json' -body (ConvertTo-Json @{ ok = $ok; message = ("$out").Trim() })
}

function invoke-search([System.Net.HttpListenerContext]$context) {
    # Proxy a registry's public search API (the browser cannot call them directly due to
    # CORS). Query + registry are validated; results are normalized to a common shape.
    $q = "$($context.Request.QueryString['q'])".Trim()
    $registry = "$($context.Request.QueryString['registry'])".Trim().ToLowerInvariant()
    if (-not $registry) { $registry = 'dockerhub' }
    if (-not (test-searchQuery $q)) {
        write-response -context $context -status 400 -contentType 'application/json' -body (ConvertTo-Json @{ error = 'invalid or missing search query' })
        return
    }
    if ($registry -notin @('dockerhub', 'quay', 'mcr')) {
        write-response -context $context -status 400 -contentType 'application/json' -body (ConvertTo-Json @{ error = "unsupported search registry '$registry'" })
        return
    }
    try {
        $encoded = [uri]::EscapeDataString($q)
        if ($registry -eq 'quay') {
            $resp = Invoke-RestMethod -Uri "https://quay.io/api/v1/find/repositories?page=1&query=$encoded" -Method Get -TimeoutSec 15
            $results = foreach ($r in $resp.results) {
                $ns = if ($r.namespace -and $r.namespace.name) { $r.namespace.name } else { "$($r.namespace)" }
                [pscustomobject]@{
                    Name        = "quay.io/$ns/$($r.name)"
                    Stars       = ''
                    Official    = $false
                    Description = "$($r.description)"
                }
            }
        }
        elseif ($registry -eq 'mcr') {
            # MCR has no fuzzy-search API; fetch the (cached) Docker v2 catalog once and
            # substring-filter it. All entries are Microsoft-published, so mark Official.
            if ($null -eq $script:mcrCatalog) {
                $cat = Invoke-RestMethod -Uri 'https://mcr.microsoft.com/v2/_catalog' -Method Get -TimeoutSec 20
                $script:mcrCatalog = @($cat.repositories)
            }
            $hits = @($script:mcrCatalog | Where-Object { $_ -like "*$q*" } | Select-Object -First 25)
            $results = foreach ($repo in $hits) {
                [pscustomobject]@{
                    Name        = "mcr.microsoft.com/$repo"
                    Stars       = ''
                    Official    = $true
                    Description = ''
                }
            }
        }
        else {
            $resp = Invoke-RestMethod -Uri "https://hub.docker.com/v2/search/repositories/?page_size=25&query=$encoded" -Method Get -TimeoutSec 15
            $results = foreach ($r in $resp.results) {
                [pscustomobject]@{
                    Name        = $r.repo_name
                    Stars       = [int]$r.star_count
                    Official    = [bool]$r.is_official
                    Description = "$($r.short_description)"
                }
            }
        }
        $body = ConvertTo-Json @($results) -Depth 3
        if (!$body) { $body = '[]' }
        write-response -context $context -status 200 -contentType 'application/json' -body $body
    }
    catch {
        write-response -context $context -status 200 -contentType 'application/json' -body (ConvertTo-Json @{ error = "search failed: $($psitem.Exception.Message)" })
    }
}

function get-pageHtml() {
    $template = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>WSL Container Dashboard</title>
<style>
  :root { color-scheme: dark; }
  body { font-family: 'Segoe UI', system-ui, sans-serif; background:#1e1e1e; color:#e6e6e6; margin:0; padding:1.5rem; }
  h1 { font-size:1.25rem; margin:0 0 .25rem; }
  .meta { color:#9a9a9a; font-size:.85rem; margin-bottom:1rem; }
  table { border-collapse:collapse; width:100%; }
  th,td { text-align:left; padding:.5rem .75rem; border-bottom:1px solid #333; font-size:.9rem; vertical-align:middle; }
  th { color:#9a9a9a; font-weight:600; cursor:pointer; user-select:none; white-space:nowrap; }
  th:hover { color:#e6e6e6; }
  th .arrow { color:#569cd6; }
  .state { font-weight:600; }
  .Running { color:#4ec9b0; }
  .Exited { color:#808080; }
  .Created { color:#569cd6; }
  a.port { color:#569cd6; }
  .pct-ok { color:#4ec9b0; } .pct-warn { color:#dcdcaa; } .pct-hi { color:#f48771; font-weight:600; }
  .toolbar { display:flex; gap:.5rem; align-items:center; margin-bottom:.75rem; flex-wrap:wrap; }
  .toolbar input { background:#111; border:1px solid #333; color:#e6e6e6; border-radius:4px; padding:.35rem .5rem; font-size:.85rem; min-width:14rem; }
  .toolbar select { background:#111; border:1px solid #333; color:#e6e6e6; border-radius:4px; padding:.35rem .5rem; font-size:.85rem; }
  .toolbar label { color:#9a9a9a; font-size:.8rem; }
  #banner { display:none; background:#5a1d0d; border:1px solid #a1260d; color:#f0c8bd; padding:.5rem .75rem; border-radius:4px; margin-bottom:.75rem; font-size:.85rem; }
  button { background:#0e639c; color:#fff; border:0; border-radius:4px; padding:.3rem .6rem; margin-right:.25rem; cursor:pointer; font-size:.8rem; }
  button:hover { background:#1177bb; }
  button.danger { background:#a1260d; } button.danger:hover { background:#c42b0f; }
  button.ghost { background:#333; } button.ghost:hover { background:#444; }
  #out { white-space:pre-wrap; background:#111; border:1px solid #333; padding:.75rem; margin-top:1rem; max-height:40vh; overflow:auto; font-family:Consolas,monospace; font-size:.8rem; display:none; }
  #out .key { color:#9cdcfe; } #out .str { color:#ce9178; } #out .num { color:#b5cea8; }
  #out .bool, #out .null { color:#569cd6; }
  #out .log-error { color:#f48771; } #out .log-warn { color:#dcdcaa; }
  #out .log-info { color:#4ec9b0; } #out .log-debug { color:#808080; }
  #out .dim { color:#808080; }
  .none { color:#808080; padding:1rem 0; }
  h2.section { font-size:1rem; margin:1.5rem 0 .5rem; }
  h2.section label { font-size:.75rem; font-weight:400; color:#9a9a9a; margin-left:.5rem; }
  td.ok { color:#4ec9b0; } td.err { color:#f48771; font-weight:600; }
  #ltbl td { font-size:.82rem; }
</style>
</head>
<body>
<h1>WSL Container Dashboard</h1>
<div class="meta">127.0.0.1 · auto-refresh __REFRESH__s · <span id="ts"></span></div>
<div id="banner"></div>
<div class="toolbar">
  <input id="filter" type="text" placeholder="filter by name / image / id ..." oninput="render()">
  <button class="danger" onclick="prune()">Prune stopped</button>
  <span id="count" class="meta"></span>
</div>
<div class="toolbar">
  <input id="runImage" type="text" list="imageOptions" onchange="onImageSelected()" placeholder="image (pick local or type, e.g. nginx:latest)">
  <datalist id="imageOptions"></datalist>
  <input id="runName" type="text" placeholder="name (optional)" style="min-width:9rem">
  <input id="runPorts" type="text" placeholder="ports 8080:80, 53:53/udp (optional)">
  <input id="runEnv" type="text" placeholder="env KEY=VALUE; e.g. ALLOW_EMPTY_PASSWORD=yes">
  <input id="runCmd" type="text" placeholder="command (optional, e.g. sleep infinity)">
  <label><input type="checkbox" id="runDetach" checked> detached</label>
  <button onclick="runContainer()">Create &amp; run</button>
</div>
<table id="tbl"><thead><tr>
  <th data-key="Name">Name</th><th data-key="State">State</th><th data-key="Uptime">Uptime</th>
  <th data-key="CPUPerc">CPU%</th><th data-key="MemPerc">Mem%</th><th data-key="MemUsage">Mem</th>
  <th data-key="PIDs">PIDs</th><th data-key="Image">Image</th><th data-key="Ports">Ports</th>
  <th data-key="ShortId">Id</th><th>Actions</th>
</tr></thead><tbody id="rows"></tbody></table>
<div id="empty" class="none" style="display:none">(no containers)</div>
<h2 class="section">Images</h2>
<div class="toolbar">
  <input id="pullImage" type="text" placeholder="pull / update image (e.g. alpine:latest)">
  <button onclick="pullImage()">Pull / update</button>
</div>
<table id="itbl"><thead><tr>
  <th>Reference</th><th>Tag</th><th>Age</th><th>Size</th><th>Platform</th><th>Layers</th><th>Ports</th><th>Id</th><th>Actions</th>
</tr></thead><tbody id="irows"></tbody></table>
<div id="iempty" class="none" style="display:none">(no images)</div>
<h2 class="section">Search registries</h2>
<div class="toolbar">
  <select id="searchRegistry">
    <option value="dockerhub">Docker Hub</option>
    <option value="quay">Quay.io</option>
    <option value="mcr">Microsoft (MCR)</option>
  </select>
  <input id="searchQ" type="text" placeholder="search images (e.g. redis, postgres) ..." onkeydown="if(event.key==='Enter')searchImages()">
  <button onclick="searchImages()">Search</button>
  <span id="scount" class="meta"></span>
</div>
<table id="stbl"><thead><tr>
  <th>Name</th><th>Stars</th><th>Official</th><th>Description</th><th>Actions</th>
</tr></thead><tbody id="srows"></tbody></table>
<div id="sempty" class="none" style="display:none">(no results)</div>
<h2 class="section">Action log</h2>
<table id="ltbl"><thead><tr>
  <th>Time</th><th>Action</th><th>Target</th><th>Result</th><th>Message</th>
</tr></thead><tbody id="lrows"></tbody></table>
<div id="lempty" class="none" style="display:none">(no actions yet)</div>
<pre id="out"></pre>
<script>
const REFRESH = __REFRESH__ * 1000;
const out = document.getElementById('out');
let data = [];
let images = [];
let sortKey = 'Name';
let sortDir = 1;
let followToken = 0;
function esc(s){ return (s||'').replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c])); }
function portsHtml(p){
  if(!p) return '';
  return p.split(',').map(x=>{
    const m = x.trim().match(/^([\d.]+):(\d+)->/);
    if(m){ const url = 'http://'+ (m[1]==='0.0.0.0'?'localhost':m[1]) +':'+m[2]; return '<a class="port" href="'+url+'" target="_blank">'+esc(x.trim())+'</a>'; }
    return esc(x.trim());
  }).join(', ');
}
async function act(name, op){
  if(op === 'stop' && !confirm('Stop container "'+name+'"?')) return;
  if(op === 'remove' && !confirm('Remove container "'+name+'"? This cannot be undone.')) return;
  out.style.display='block'; out.textContent = op+' '+name+' ...';
  const r = await fetch('/api/action', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({name, op})});
  const j = await r.json();
  out.textContent = (j.ok?'[ok] ':'[error] ') + op + ' ' + name + (j.message? '\n'+j.message : '');
  load();
}
async function prune(){
  if(!confirm('Remove ALL stopped containers?')) return;
  out.style.display='block'; out.textContent = 'prune ...';
  const r = await fetch('/api/prune', {method:'POST'});
  const j = await r.json();
  out.textContent = (j.ok?'[ok] ':'[error] ') + 'prune' + (j.message? '\n'+j.message : '');
  load();
}
async function runContainer(){
  const image = document.getElementById('runImage').value.trim();
  if(!image){ alert('Enter an image reference to run.'); return; }
  const name = document.getElementById('runName').value.trim();
  const publish = document.getElementById('runPorts').value.trim();
  const env = document.getElementById('runEnv').value.trim();
  const command = document.getElementById('runCmd').value.trim();
  const detach = document.getElementById('runDetach').checked;
  out.style.display='block'; out.textContent = 'run '+image+' ...';
  try {
    const r = await fetch('/api/run', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({image, name, publish, env, command, detach})});
    const j = await r.json();
    out.textContent = (j.ok?'[ok] ':'[error] ') + 'run ' + image + (j.message? '\n'+j.message : '');
    if(j.ok){ document.getElementById('runImage').value=''; document.getElementById('runName').value=''; document.getElementById('runPorts').value=''; document.getElementById('runEnv').value=''; document.getElementById('runCmd').value=''; resetCreateForm(); }
  } catch(e){ out.textContent = '[error] run '+image+': '+e; }
  load();
}
function findLocalImage(ref){
  return images.find(im => im.Reference === ref || im.ShortId === ref);
}
function resetCreateForm(){
  const cmd = document.getElementById('runCmd');
  cmd.disabled = false;
  cmd.placeholder = 'command (optional, e.g. sleep infinity)';
  cmd.title = '';
}
function onImageSelected(){
  const ref = document.getElementById('runImage').value.trim();
  const name = document.getElementById('runName');
  const ports = document.getElementById('runPorts');
  const cmd = document.getElementById('runCmd');
  resetCreateForm();
  const im = findLocalImage(ref);
  if(!im){ return; }                       // unknown/typed image: don't force anything
  if(!name.value){ name.value = ref.split(':')[0].split('/').pop(); }
  if(im.ExposedPorts){
    // Service image: it runs its own process. Prefill host:container for each exposed
    // port and disable the command so it can't be overridden (the redis footgun).
    ports.value = im.ExposedPorts.split(',').map(p => {
      const cp = (p.trim().split('/')[0] || '').trim();
      return cp ? cp+':'+cp : '';
    }).filter(Boolean).join(', ');
    cmd.value = '';
    cmd.disabled = true;
    cmd.placeholder = 'not needed \u2014 image runs its own service';
    cmd.title = 'This image exposes ports and runs its own service; a command would override it.';
  } else {
    // Base image: exits immediately without a long-running command.
    ports.value = '';
    if(!cmd.value){ cmd.value = 'sleep infinity'; }
    cmd.placeholder = 'base image needs a keep-alive command, e.g. sleep infinity';
  }
}
async function pullImage(ref){
  const image = ref || document.getElementById('pullImage').value.trim();
  if(!image){ alert('Enter an image reference to pull.'); return; }
  out.style.display='block'; out.textContent = 'pull '+image+' ...';
  try {
    const r = await fetch('/api/pull', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({image})});
    const j = await r.json();
    out.textContent = (j.ok?'[ok] ':'[error] ') + 'pull ' + image + (j.message? '\n'+j.message : '');
    if(j.ok && !ref){ document.getElementById('pullImage').value=''; }
  } catch(e){ out.textContent = '[error] pull '+image+': '+e; }
  load();
}
async function removeImage(ref){
  if(!confirm('Remove image "'+ref+'"? This cannot be undone.')) return;
  out.style.display='block'; out.textContent = 'rmi '+ref+' ...';
  try {
    const r = await fetch('/api/removeimage', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ref})});
    const j = await r.json();
    out.textContent = (j.ok?'[ok] ':'[error] ') + 'rmi ' + ref + (j.message? '\n'+j.message : '');
  } catch(e){ out.textContent = '[error] rmi '+ref+': '+e; }
  load();
}
async function searchImages(){
  const q = document.getElementById('searchQ').value.trim();
  if(!q){ alert('Enter a search term.'); return; }
  const reg = document.getElementById('searchRegistry').value;
  const rows = document.getElementById('srows');
  const scount = document.getElementById('scount');
  scount.textContent = 'searching \u201c'+q+'\u201d ...';
  try {
    const r = await fetch('/api/search?registry='+encodeURIComponent(reg)+'&q='+encodeURIComponent(q));
    const body = await r.json();
    if(body && body.error){ scount.textContent = body.error; rows.innerHTML=''; document.getElementById('sempty').style.display='block'; return; }
    const list = Array.isArray(body) ? body : [];
    scount.textContent = list.length + ' results';
    document.getElementById('sempty').style.display = list.length ? 'none' : 'block';
    rows.innerHTML = list.map(im =>
      '<tr>'
      + '<td>'+esc(im.Name)+'</td>'
      + '<td>'+esc(''+im.Stars)+'</td>'
      + '<td>'+(im.Official?'\u2713':'')+'</td>'
      + '<td>'+esc(im.Description||'')+'</td>'
      + '<td><button onclick="pullImage(\''+esc(im.Name)+'\')">Pull</button></td>'
      + '</tr>'
    ).join('');
  } catch(e){ scount.textContent = 'search failed: '+e; }
}
function copyId(id){ navigator.clipboard.writeText(id); }
function pctClass(p){
  const v = parseFloat((p||'').replace('%',''));
  if(isNaN(v)) return '';
  if(v >= 80) return 'pct-hi';
  if(v >= 50) return 'pct-warn';
  return 'pct-ok';
}
function prettyJson(text){ try { return JSON.stringify(JSON.parse(text), null, 2); } catch(e){ return text; } }
function highlightJson(text){
  return esc(text).replace(/("(?:\\.|[^"\\])*"\s*:)|("(?:\\.|[^"\\])*")|(\b(?:true|false)\b)|(\bnull\b)|(-?\d+(?:\.\d+)?(?:[eE][+\-]?\d+)?)/g,
    (m, key, str, bool, nul, num) => {
      if(key) return '<span class="key">'+key+'</span>';
      if(str) return '<span class="str">'+str+'</span>';
      if(bool) return '<span class="bool">'+bool+'</span>';
      if(nul) return '<span class="null">'+nul+'</span>';
      return '<span class="num">'+num+'</span>';
    });
}
function highlightLogs(text){
  return esc(text).split('\n').map(line => {
    let cls = '';
    if(/\b(error|err|fatal|panic|fail(?:ed|ure)?)\b/i.test(line)) cls = 'log-error';
    else if(/\b(warn(?:ing)?|deprecat)\b/i.test(line)) cls = 'log-warn';
    else if(/\b(info|notice|listening|started|ready)\b/i.test(line)) cls = 'log-info';
    else if(/\b(debug|trace|verbose)\b/i.test(line)) cls = 'log-debug';
    return cls ? '<span class="'+cls+'">'+line+'</span>' : line;
  }).join('\n');
}
function logsHtml(text){
  return (text && text.trim()) ? highlightLogs(text) : '<span class="dim">(no output)</span>';
}
async function show(name, kind){
  // Each call supersedes any prior follow loop; awaited responses that arrive
  // after a newer show() are discarded so out-of-order polls can't clobber the view.
  const token = ++followToken;
  out.style.display='block'; out.innerHTML = '<span class="dim">'+esc(kind+' '+name+' ...')+'</span>';
  try {
    const r = await fetch('/api/'+kind+'?name='+encodeURIComponent(name));
    const text = await r.text();
    if(token !== followToken) return;
    out.innerHTML = (kind === 'inspect') ? highlightJson(prettyJson(text)) : logsHtml(text);
    out.scrollTop = out.scrollHeight;
  } catch(e){
    if(token === followToken){ out.innerHTML = '<span class="log-error">'+esc('failed to load '+kind+': '+e)+'</span>'; }
    return;
  }
  if(kind !== 'logs') return;
  const nearBottom = () => (out.scrollHeight - out.scrollTop - out.clientHeight) < 30;
  const poll = async () => {
    if(token !== followToken) return;            // a newer show() took over
    try {
      const rr = await fetch('/api/logs?name='+encodeURIComponent(name));
      const t = await rr.text();
      if(token !== followToken) return;          // stale response, discard
      const stick = nearBottom();
      out.innerHTML = logsHtml(t);
      if(stick) out.scrollTop = out.scrollHeight; // keep pinned only if already at bottom
    } catch(e){ /* transient fetch error; keep following */ }
    if(token === followToken) setTimeout(poll, REFRESH);
  };
  setTimeout(poll, REFRESH);
}
function render(){
  const rows = document.getElementById('rows');
  const q = (document.getElementById('filter').value || '').toLowerCase();
  let list = data.filter(c => !q || (c.Name+' '+c.Image+' '+c.ShortId).toLowerCase().includes(q));
  list.sort((a,b) => {
    const av = (a[sortKey]==null?'':a[sortKey]).toString();
    const bv = (b[sortKey]==null?'':b[sortKey]).toString();
    const na = parseFloat(av.replace('%','')), nb = parseFloat(bv.replace('%',''));
    if(!isNaN(na) && !isNaN(nb)) return (na-nb)*sortDir;
    return av.localeCompare(bv)*sortDir;
  });
  document.getElementById('empty').style.display = list.length? 'none':'block';
  document.getElementById('count').textContent = list.length + ' of ' + data.length;
  rows.innerHTML = list.map(c => {
    const running = c.State === 'Running';
    return '<tr>'
      + '<td>'+esc(c.Name)+'</td>'
      + '<td class="state '+esc(c.State)+'">'+esc(c.State)+'</td>'
      + '<td>'+esc(c.Uptime)+'</td>'
      + '<td class="'+pctClass(c.CPUPerc)+'">'+esc(c.CPUPerc)+'</td>'
      + '<td class="'+pctClass(c.MemPerc)+'">'+esc(c.MemPerc)+'</td>'
      + '<td>'+esc(c.MemUsage)+'</td>'
      + '<td>'+esc(''+ (c.PIDs===''?'':c.PIDs))+'</td>'
      + '<td>'+esc(c.Image)+'</td>'
      + '<td>'+portsHtml(c.Ports)+'</td>'
      + '<td>'+esc(c.ShortId)+' <button class="ghost" title="copy id" onclick="copyId(\''+c.ShortId+'\')">&#128203;</button></td>'
      + '<td>'
        + (running? '<button class="danger" onclick="act(\''+c.Name+'\',\'stop\')">Stop</button>' : '<button onclick="act(\''+c.Name+'\',\'start\')">Start</button>')
        + '<button onclick="act(\''+c.Name+'\',\'restart\')">Restart</button>'
        + '<button onclick="show(\''+c.Name+'\',\'logs\')">Logs</button>'
        + '<button onclick="show(\''+c.Name+'\',\'inspect\')">Inspect</button>'
        + '<button class="danger" onclick="act(\''+c.Name+'\',\'remove\')">Remove</button>'
      + '</td></tr>';
  }).join('');
  document.querySelectorAll('th[data-key]').forEach(th => {
    th.textContent = th.dataset.label || (th.dataset.label = th.textContent);
    if(th.dataset.key === sortKey){ th.innerHTML = th.dataset.label + ' <span class="arrow">'+(sortDir>0?'\u25B2':'\u25BC')+'</span>'; }
  });
}
async function load(){
  const banner = document.getElementById('banner');
  try {
    const r = await fetch('/api/containers');
    const body = await r.json();
    if(body && body.error){ banner.style.display='block'; banner.textContent = body.error; data = []; render(); return; }
    banner.style.display='none';
    data = body;
    render();
    document.getElementById('ts').textContent = new Date().toLocaleTimeString();
  } catch(e){ banner.style.display='block'; banner.textContent = 'refresh failed: '+e; }
  try {
    const ir = await fetch('/api/images?details=1');
    const ibody = await ir.json();
    images = (ibody && ibody.error) ? [] : ibody;
    renderImages();
  } catch(e){ /* images are best-effort; keep last render */ }
  try {
    const lr = await fetch('/api/actionlog');
    const lg = await lr.json();
    renderLog(Array.isArray(lg) ? lg : []);
  } catch(e){ /* action log is best-effort */ }
}
function renderLog(entries){
  const rows = document.getElementById('lrows');
  document.getElementById('lempty').style.display = entries.length ? 'none' : 'block';
  rows.innerHTML = entries.slice().reverse().map(e =>
    '<tr>'
    + '<td>'+esc(e.Time)+'</td>'
    + '<td>'+esc(e.Action)+'</td>'
    + '<td>'+esc(e.Target)+'</td>'
    + '<td class="'+(e.Ok?'ok':'err')+'">'+(e.Ok?'ok':'error')+'</td>'
    + '<td>'+esc((e.Message||'').split('\n')[0])+'</td>'
    + '</tr>'
  ).join('');
}
function renderImages(){
  const rows = document.getElementById('irows');
  document.getElementById('iempty').style.display = images.length? 'none':'block';
  rows.innerHTML = images.map(im => {
    return '<tr>'
      + '<td>'+esc(im.Reference)+(im.Dangling?' <span class="dim">(dangling)</span>':'')+'</td>'
      + '<td>'+esc(im.Tag)+'</td>'
      + '<td>'+esc(im.Age)+'</td>'
      + '<td>'+esc(im.Size)+'</td>'
      + '<td>'+esc(im.Platform)+'</td>'
      + '<td>'+esc(''+(im.Layers===''?'':im.Layers))+'</td>'
      + '<td>'+esc(im.ExposedPorts)+'</td>'
      + '<td>'+esc(im.ShortId)+' <button class="ghost" title="copy id" onclick="copyId(\''+im.ShortId+'\')">&#128203;</button></td>'
      + '<td><button onclick="showImage(\''+esc(im.Reference)+'\')">Inspect</button>'
        + (im.Dangling?'':'<button onclick="pullImage(\''+esc(im.Reference)+'\')">Update</button>')
        + '<button class="danger" onclick="removeImage(\''+esc(im.Reference)+'\')">Remove</button>'
      + '</td>'
      + '</tr>';
  }).join('');
  document.getElementById('imageOptions').innerHTML = images
    .filter(im => !im.Dangling)
    .map(im => '<option value="'+esc(im.Reference)+'">').join('');
}
async function showImage(ref){
  const token = ++followToken;   // supersede any active logs follow
  out.style.display='block'; out.innerHTML = '<span class="dim">'+esc('inspect '+ref+' ...')+'</span>';
  try {
    const r = await fetch('/api/imageinspect?ref='+encodeURIComponent(ref));
    const text = await r.text();
    if(token !== followToken) return;
    out.innerHTML = highlightJson(prettyJson(text));
    out.scrollTop = 0;
  } catch(e){
    if(token === followToken){ out.innerHTML = '<span class="log-error">'+esc('failed to inspect '+ref+': '+e)+'</span>'; }
  }
}
document.querySelectorAll('th[data-key]').forEach(th => {
  th.addEventListener('click', () => {
    const k = th.dataset.key;
    if(sortKey === k){ sortDir = -sortDir; } else { sortKey = k; sortDir = 1; }
    render();
  });
});
load();
setInterval(load, REFRESH);
</script>
</body>
</html>
'@
    return ($template -replace '__REFRESH__', "$RefreshSeconds")
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
