# WSL Container Scripts

PowerShell tooling around the **WSL container CLI** (`wslc.exe`) — the built-in
binary that ships with the [WSL container feature](https://learn.microsoft.com/windows/wsl/wsl-container)
for building, running, and interacting with Linux containers on Windows.

The primary interface is a single object-model script,
[Invoke-WslContainer.ps1](Invoke-WslContainer.ps1), which creates `$global:wslcObj`
with dot-callable methods (same pattern as `kusto-rest.ps1`/`nuget-functions.ps1`).
It turns the raw `wslc.exe` text output into structured PowerShell objects so
container workflows can be scripted and piped like any other PowerShell command.
The list methods parse `wslc`'s native `--format json` output (rather than scraping
tables) and enrich it — mapping the numeric container state to a label
(Created/Running/Exited/Deleted), converting Unix timestamps to local `DateTime`
values, deriving a human-readable **Uptime** (`up 12m` / `exited 38m ago`), and
formatting port mappings. Both dashboards and `$wslcObj.GetContainers($true, $true)` can
merge **live CPU% / memory / network / PIDs** from `wslc stats`.

> Requires Windows Subsystem for Linux (WSL) with the WSL container feature. Run
> `$wslcObj.Prerequisites()` first to confirm `wsl.exe` and `wslc.exe`
> are present. Install/update WSL with `wsl --install` / `wsl --update`.

## Prerequisites

The WSL container CLI (`wslc.exe`) is a **recent, built-in** WSL binary. It ships
only with newer WSL builds and is **not present in older versions** (for example,
WSL `2.7.3.0` does not include it). As of this writing it is delivered through the
**pre-release** WSL channel (confirmed present in WSL `2.9.3.0`); the current
**stable** channel (`2.7.10.0`) does not yet include it. `wsl.exe` being installed
is **not** enough on its own — `wslc.exe` must also resolve on `PATH`.

To install or update to a build that includes `wslc.exe`:

```powershell
# Install WSL (if not already present)
wsl --install

# Update to the latest build; include pre-release since wslc currently ships there
wsl --update
wsl --update --pre-release

# Verify
wsl --version                        # confirm the updated version (>= 2.9.x)
Get-Command wslc.exe                 # should resolve once available
. .\Invoke-WslContainer.ps1          # creates $wslcObj
$wslcObj.Prerequisites()             # reports Ready = $true when wslc is present
```

### If `wsl --version` shows a new build but `wslc` won't resolve

The WSL binaries install to **`C:\Program Files\WSL`**. Unlike `wsl.exe` (which has
a `System32` app-execution alias), `wslc.exe` is only in that folder, so it may not
be on `PATH`. Confirm and, if needed, add the directory to your **User** `PATH`:

```powershell
# wslc is there, just not on PATH
& 'C:\Program Files\WSL\wslc.exe' --version

# Add the WSL folder to the User PATH (persists across sessions)
$wslDir = 'C:\Program Files\WSL'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $wslDir) {
    [Environment]::SetEnvironmentVariable('Path', "$($userPath.TrimEnd(';'));$wslDir", 'User')
}
$env:Path = "$($env:Path.TrimEnd(';'));$wslDir"   # update the current session too
```

Until `wslc.exe` is available, `$wslcObj.Prerequisites()` returns
`WslcInstalled = $false` / `Ready = $false`, and `$wslcObj` methods throw a clear
"wslc CLI not available" message rather than failing obscurely. If `wslc.exe` lives in
a non-default location, `Invoke-WslContainer.ps1` and both dashboards accept a
`-WslcPath` parameter to point at it.

## Scripts

| Script | Wraps | Purpose |
|--------|-------|---------|
| **Invoke-WslContainer.ps1** | all `wslc` commands | **Primary interface.** Creates `$wslcObj`, a `WslcObj` class with dot-callable methods (`Prerequisites()`, `GetContainers()`, `GetImages()`, `ImageInspect()`, `Run()`, `Exec()`, `Start()`, `Stop()`, `Restart()`, `Remove()`, `Logs()`, `Inspect()`, `Prune()`, `Help()`). |
| **Watch-WslContainer.ps1** | `wslc container ps` / `image ls` | Live auto-refreshing console dashboard (containers, enriched images, status counts). Container names link to inspect details; `-ImageDetails` adds platform/layers; `-Interactive` adds stop/restart/logs/inspect keys. |
| **Start-WslContainerDashboard.ps1** | `container ls` / `image ls` + `stop`/`start`/`logs`/`inspect` | Local (127.0.0.1) web dashboard with working Stop/Start/Restart/Logs/Inspect **buttons** and an **Images** table with inspect. |

## Examples

```powershell
# Create $wslcObj and verify prerequisites
. .\Invoke-WslContainer.ps1
$wslcObj.Prerequisites()

# Run a web server in the background, publishing port 80 to host port 8080
$wslcObj.Run('nginx', 'web', @('8080:80'), $true)

# List running containers, then stop the web server
$wslcObj.GetContainers() | Where-Object Name -eq 'web'
$wslcObj.Stop('web')

# Run a one-off command in a throwaway Ubuntu container
$wslcObj.Exec('ubuntu:latest', @('bash','-c','echo Hello world from WSL container!'))

# Live dashboard: refresh every 2s, include stopped containers
.\Watch-WslContainer.ps1 -RefreshIntervalSeconds 2 -ShowStopped

# Interactive console dashboard: select by number, then s=stop r=restart l=logs i=inspect
.\Watch-WslContainer.ps1 -Interactive

# Web dashboard with clickable Stop/Restart/Logs buttons (loopback-only control server)
.\Start-WslContainerDashboard.ps1        # opens http://127.0.0.1:8973
```

## Object model (`$wslcObj`)

For interactive/scripted use, `Invoke-WslContainer.ps1` provides a single `WslcObj`
class (same pattern as `kusto-rest.ps1`/`nuget-functions.ps1`).
Running or dot-sourcing it creates `$global:wslcObj` with dot-callable methods:

```powershell
. .\Invoke-WslContainer.ps1                       # creates $wslcObj
$wslcObj.Prerequisites()                           # WSL/wslc readiness report
$wslcObj.GetContainers($true, $true) | Format-Table Name,State,Uptime,CPUPerc,MemUsage
$wslcObj.GetImages() | Format-Table Reference,Age,Size,Dangling,ShortId
$wslcObj.GetImages($true) | Format-Table Reference,Platform,Layers,ExposedPorts   # + image inspect
$wslcObj.ImageInspect('nginx:latest')              # full image inspect object
$wslcObj.Run('nginx','web',@('8080:80'),$true)     # detached, publish 8080
$wslcObj.Stop('web'); $wslcObj.Start('web'); $wslcObj.Restart('web')
$wslcObj.Logs('web',50); $wslcObj.Inspect('web'); $wslcObj.Prune()
$wslcObj.Help()                                    # list all methods
```

> **Terminal links vs. actions:** OSC 8 terminal hyperlinks can only *open URLs* — they
> cannot run commands. So `Watch-WslContainer.ps1` links container names to their
> inspect JSON and published ports to `http://host:port`, but stop/restart/logs are
> driven by keystrokes (`-Interactive`). For true clickable action **buttons**, use
> `Start-WslContainerDashboard.ps1`, which serves an HTML page backed by a small
> localhost HTTP server that executes the `wslc` commands (bound to 127.0.0.1, with an
> action allow-list and container-name validation).

The web dashboard also supports **filter/sort**, **CPU/Mem threshold coloring**, live
**uptime + CPU/Mem/PIDs**, **syntax-highlighted inspect/logs** with logs **auto-follow**,
**copy-id**, **confirm-before-stop**, a **Prune stopped** button, a **Create &amp; run**
container form (image / name / ports / **command** / **env** / detached), a **Pull / update image**
control (plus a per-image **Update** button), **Remove** buttons for containers (force) and
images (`rmi`, with confirmation), an **Action log** panel (also written to
`%TEMP%\wslc-dashboard.log`), and a graceful banner when `wslc` is unavailable. It also
lists **images** (reference, age, human size, platform, layer count, exposed ports) each
with **Inspect**, **Update**, and **Remove** buttons backed by a
validated image-inspect endpoint. A **Search registries** panel (Docker Hub + Quay.io + Microsoft
MCR via a dropdown) queries their public APIs (validated, server-proxied) and lets you **Pull** any
result; other registries (GHCR, ECR Public, k8s, GitLab) work by pulling a
fully-qualified reference directly. Create/pull inputs (image ref, name, port mappings) are
regex-validated and passed to `wslc` as argument arrays, so there is no injection surface.
The console watcher adds **exit code**, **container IP**, **CPU/Mem coloring**, a header
**summary** (running count, total CPU/Mem), and enriched images (reference, age, human
size; `-ImageDetails` adds platform and layer count).

**Image enrichment fields** (`$wslcObj.GetImages()` base; `GetImages($true)` adds the
`image inspect` layer): `Reference`, `Tag`, `Age`, `Size` (+ `SizeMB`), `Created`,
`Dangling`, `ShortId`/`Id`, and with details `Architecture`/`Os`/`Platform`, `Layers`,
`ExposedPorts`, `Command`/`Entrypoint`, `EnvCount`, `Labels`, `StopSignal`, `WorkingDir`,
`User`, `Digest`.

## References

- [WSL container overview](https://learn.microsoft.com/windows/wsl/wsl-container)
- [WSL container tutorial](https://learn.microsoft.com/windows/wsl/tutorials/wsl-containers)
- [WSL container API reference](https://wsl.dev/api-reference/)
