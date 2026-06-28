<#
.SYNOPSIS
    Validates Node.js and npm package installation on Azure test VMs.

.DESCRIPTION
    Runs post-deployment validation on VMs in an Azure resource group to verify
    Node.js is installed and optionally test npx package execution (e.g.,
    @jagilber-org/index-server from GitHub Packages).

    Uses Invoke-AzVMRunCommand for both Linux and Windows VMs — no SSH or open
    ports required (runs via Azure control plane).

    Requires: Az PowerShell module (Az 10.0.0+), active Azure connection,
    and VMs in a running state.

    to enable script execution, you may need to Set-ExecutionPolicy Bypass -Force

.EXAMPLE
    .\Test-AzTestVmValidation.ps1 -ResourceGroupName rg-test-vms
    Validates Node.js is installed on all VMs in the resource group.

.EXAMPLE
    $token = Read-Host "GitHub token" -AsSecureString
    .\Test-AzTestVmValidation.ps1 -ResourceGroupName rg-test-vms -PackageName '@jagilber-org/index-server' -NpmToken $token -NpmRegistry github
    Validates Node.js AND runs npx @jagilber-org/index-server --help on all VMs.

.EXAMPLE
    .\Test-AzTestVmValidation.ps1 -ResourceGroupName rg-test-vms -PackageName 'cowsay' -NpmRegistry npmjs
    Validates using a public npm package (no token needed).

.PARAMETER ResourceGroupName
    Name of the Azure resource group containing the VMs to validate.

.PARAMETER PackageName
    npm package to test via npx. If not specified, only Node.js version is validated.

.PARAMETER NpmToken
    SecureString token for private registry auth (e.g., GitHub Packages PAT).

.PARAMETER NpmRegistry
    Registry to use: 'github' for npm.pkg.github.com or 'npmjs' for registry.npmjs.org.

.PARAMETER NpmScope
    npm scope for registry configuration (e.g., '@jagilber-org'). Auto-detected from PackageName if scoped.

.PARAMETER VmName
    Specific VM name(s) to validate. If not specified, validates all VMs in the resource group.

.PARAMETER SaveResults
    If specified, appends validation results to the specified file path.

.PARAMETER ResultsPath
    Path to save results. Used with -SaveResults.

.NOTES
    File Name  : Test-AzTestVmValidation.ps1
    Requires   : Az PowerShell module
    Version    : 1.0.0
    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)

.LINK
    https://learn.microsoft.com/en-us/powershell/module/az.compute/invoke-azvmruncommand
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [string]$PackageName,

    [securestring]$NpmToken,

    [ValidateSet('github', 'npmjs')]
    [string]$NpmRegistry = 'github',

    [string]$NpmScope,

    [string[]]$VmName,

    [switch]$SaveResults,

    [string]$ResultsPath
)

$ErrorActionPreference = 'Stop'
$error.Clear()

function main() {
    # Verify Azure connection
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Error "Not connected to Azure. Run Connect-AzAccount first."
            return
        }
        Write-Verbose "Connected to subscription: $($context.Subscription.Name)"
    }
    catch {
        Write-Error "Failed to get Azure context: $_"
        return
    }

    # Get VMs
    $vms = Get-AzVM -ResourceGroupName $ResourceGroupName -Status -ErrorAction Stop
    if ($VmName) {
        $vms = $vms | Where-Object { $_.Name -in $VmName }
    }
    $runningVms = $vms | Where-Object { $_.PowerState -eq 'VM running' }

    if (-not $runningVms) {
        Write-Warning "No running VMs found in resource group '$ResourceGroupName'."
        return
    }

    Write-Host "Found $($runningVms.Count) running VM(s) to validate." -ForegroundColor Cyan

    # Auto-detect scope from package name if scoped
    if (-not $NpmScope -and $PackageName -match '^(@[^/]+)/') {
        $NpmScope = $Matches[1]
        Write-Verbose "Auto-detected npm scope: $NpmScope"
    }

    # Decrypt token if provided
    $plainToken = $null
    if ($NpmToken) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($NpmToken)
        try {
            $plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }

    # Build registry URL
    $registryUrl = switch ($NpmRegistry) {
        'github' { 'https://npm.pkg.github.com' }
        'npmjs' { 'https://registry.npmjs.org' }
    }

    # Validate each VM
    $results = @()
    foreach ($vm in $runningVms) {
        $isLinux = $vm.StorageProfile.OsDisk.OsType -eq 'Linux'
        $osLabel = if ($isLinux) { 'Linux' } else { 'Windows' }
        $commandId = if ($isLinux) { 'RunShellScript' } else { 'RunPowerShellScript' }

        Write-Host "`nValidating: $($vm.Name) ($osLabel)..." -ForegroundColor Cyan

        # Build validation script
        if ($isLinux) {
            $script = build-LinuxScript -PackageName $PackageName -Token $plainToken `
                -RegistryUrl $registryUrl -Scope $NpmScope
        }
        else {
            $script = build-WindowsScript -PackageName $PackageName -Token $plainToken `
                -RegistryUrl $registryUrl -Scope $NpmScope
        }

        try {
            $response = Invoke-AzVMRunCommand `
                -ResourceGroupName $ResourceGroupName `
                -VMName $vm.Name `
                -CommandId $commandId `
                -ScriptString $script `
                -ErrorAction Stop

            $stdout = ($response.Value | Where-Object { $_.Code -eq 'ComponentStatus/StdOut/succeeded' }).Message
            $stderr = ($response.Value | Where-Object { $_.Code -eq 'ComponentStatus/StdErr/succeeded' }).Message

            # Parse results
            $nodeVersion = if ($stdout -match 'NODE_VERSION=(.+)') { $Matches[1].Trim() } else { 'N/A' }
            $npmVersion = if ($stdout -match 'NPM_VERSION=(.+)') { $Matches[1].Trim() } else { 'N/A' }
            $npxResult = if ($stdout -match 'NPX_RESULT=(\d+)') { [int]$Matches[1] } else { -1 }

            $nodePass = $nodeVersion -ne 'N/A'
            $npxPass = if ($PackageName) { $npxResult -eq 0 } else { $null }

            $status = if ($nodePass -and ($null -eq $npxPass -or $npxPass)) { 'PASS' } else { 'FAIL' }

            $result = [PSCustomObject]@{
                VM          = $vm.Name
                OS          = $osLabel
                NodeVersion = $nodeVersion
                NpmVersion  = $npmVersion
                NpxPackage  = if ($PackageName) { $PackageName } else { '(skipped)' }
                NpxResult   = if ($null -eq $npxPass) { 'N/A' } elseif ($npxPass) { 'PASS' } else { 'FAIL' }
                Status      = $status
            }
            $results += $result

            # Display inline
            $color = if ($status -eq 'PASS') { 'Green' } else { 'Red' }
            Write-Host "  Node: $nodeVersion  npm: $npmVersion  npx: $($result.NpxResult)  [$status]" -ForegroundColor $color

            if ($stderr -and $status -eq 'FAIL') {
                Write-Verbose "  stderr: $stderr"
            }
        }
        catch {
            Write-Warning "  Failed to run command on $($vm.Name): $_"
            $results += [PSCustomObject]@{
                VM          = $vm.Name
                OS          = $osLabel
                NodeVersion = 'ERROR'
                NpmVersion  = 'ERROR'
                NpxPackage  = if ($PackageName) { $PackageName } else { '(skipped)' }
                NpxResult   = 'ERROR'
                Status      = 'ERROR'
            }
        }
    }

    # Summary table
    Write-Host "`n==================== VALIDATION RESULTS ====================" -ForegroundColor Cyan
    $results | Format-Table -AutoSize | Out-String | Write-Host

    $passed = ($results | Where-Object { $_.Status -eq 'PASS' }).Count
    $failed = ($results | Where-Object { $_.Status -ne 'PASS' }).Count
    Write-Host "Passed: $passed  Failed: $failed  Total: $($results.Count)" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })

    # Save results
    if ($SaveResults -and $ResultsPath) {
        $header = "`n# VM Validation Results - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $header | Out-File -Append -FilePath $ResultsPath -Encoding utf8
        foreach ($r in $results) {
            "AZURE_TEST_VM_$($r.VM)_NODE=$($r.NodeVersion)" | Out-File -Append -FilePath $ResultsPath -Encoding utf8
            "AZURE_TEST_VM_$($r.VM)_STATUS=$($r.Status)" | Out-File -Append -FilePath $ResultsPath -Encoding utf8
        }
        Write-Host "Results saved to $ResultsPath" -ForegroundColor Green
    }

    # Return results for pipeline use
    return $results
}

function build-LinuxScript {
    param([string]$PackageName, [string]$Token, [string]$RegistryUrl, [string]$Scope)

    $lines = @(
        '#!/bin/bash'
        'set -e'
        'export PATH="/usr/local/bin:/usr/bin:$PATH"'
        'echo "NODE_VERSION=$(node --version 2>/dev/null || echo N/A)"'
        'echo "NPM_VERSION=$(npm --version 2>/dev/null || echo N/A)"'
    )

    if ($PackageName) {
        if ($Token -and $Scope) {
            $lines += "npm config set ${Scope}:registry $RegistryUrl"
            $lines += "npm config set //${($RegistryUrl -replace 'https://','')}/:_authToken $Token"
        }
        $lines += "npx --yes $PackageName --help > /dev/null 2>&1"
        $lines += 'echo "NPX_RESULT=$?"'
    }

    return ($lines -join "`n")
}

function build-WindowsScript {
    param([string]$PackageName, [string]$Token, [string]$RegistryUrl, [string]$Scope)

    $lines = @(
        '$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")'
        '$nodeVer = try { & node --version 2>$null } catch { "N/A" }'
        'Write-Output "NODE_VERSION=$nodeVer"'
        '$npmVer = try { & npm --version 2>$null } catch { "N/A" }'
        'Write-Output "NPM_VERSION=$npmVer"'
    )

    if ($PackageName) {
        if ($Token -and $Scope) {
            $lines += "& npm config set ${Scope}:registry $RegistryUrl 2>`$null"
            $lines += "& npm config set //$($RegistryUrl -replace 'https://','')/:_authToken $Token 2>`$null"
        }
        $lines += "& npx --yes $PackageName --help 2>`$null"
        $lines += 'Write-Output "NPX_RESULT=$LASTEXITCODE"'
    }

    return ($lines -join "`n")
}

main
$error | Out-String
Write-Host "$([DateTime]::Now) finished"
