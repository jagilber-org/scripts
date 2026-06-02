param(
    [switch]$Check
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$rootScript = Join-Path $repoRoot 'sync-constitution.ps1'

if (-not (Test-Path $rootScript)) {
    Write-Error "sync-constitution.ps1 was not found at $rootScript"
    exit 1
}

if ($Check) {
    & $rootScript -Check
    exit $LASTEXITCODE
}

& $rootScript
exit $LASTEXITCODE
