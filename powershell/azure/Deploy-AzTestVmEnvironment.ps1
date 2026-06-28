<#
.SYNOPSIS
    Deploys or tears down an Azure test VM environment using a Bicep template.

.DESCRIPTION
    Deploys a configurable set of Linux and Windows test VMs in Azure using a Bicep
    template. Features include public IPs per VM, NSG restricted to the deployer's
    current public IP, auto-shutdown schedule, auto-start via Azure Automation runbook,
    B-series burstable SKUs for cost efficiency, SSH key auth for Linux, password auth
    for Windows, and dev tools (Node.js, git, Docker/VS Code) pre-installed.

    The script auto-detects the deployer's public IP, reads SSH keys from environment
    variables or parameters, and outputs connection strings for all deployed VMs.

    Requires: Az PowerShell module (Az 10.0.0+), active Azure connection (Connect-AzAccount),
    and the companion Bicep template Deploy-AzTestVmEnvironment.bicep in the same directory.

    to enable script execution, you may need to Set-ExecutionPolicy Bypass -Force

.EXAMPLE
    $secPwd = Read-Host -AsSecureString -Prompt 'Admin password'
    .\Deploy-AzTestVmEnvironment.ps1 -AdminPassword $secPwd
    Deploys 1 Linux + 1 Windows VM with defaults in westus3.

.EXAMPLE
    .\Deploy-AzTestVmEnvironment.ps1 -LinuxVmCount 2 -WindowsVmCount 0 -Location eastus2
    Deploys 2 Linux VMs only in East US 2.

.EXAMPLE
    .\Deploy-AzTestVmEnvironment.ps1 -Teardown
    Deletes the test VM resource group and all contained resources.

.EXAMPLE
    .\Deploy-AzTestVmEnvironment.ps1 -Validate
    Validates the Bicep template without deploying any resources.

.EXAMPLE
    .\Deploy-AzTestVmEnvironment.ps1 -Connect
    Lists all VMs in the resource group and connects to the first one (SSH for Linux, RDP for Windows).

.EXAMPLE
    .\Deploy-AzTestVmEnvironment.ps1 -Connect -ConnectVmName vm-linux-0
    Connects via SSH to the specified Linux VM.

.EXAMPLE
    .\Deploy-AzTestVmEnvironment.ps1 -UpdateAllowedIP
    Detects current public IP and updates all deployer-IP NSG rules.

.PARAMETER ResourceGroupName
    Name of the Azure resource group. Default: rg-test-vms

.PARAMETER Location
    Azure region for deployment. Default: westus3

.PARAMETER LinuxVmCount
    Number of Linux VMs to deploy. Default: 1

.PARAMETER WindowsVmCount
    Number of Windows VMs to deploy. Default: 1

.PARAMETER LinuxVmSize
    SKU for Linux VMs. Default: Standard_B2s

.PARAMETER WindowsVmSize
    SKU for Windows VMs. Default: Standard_B2ms

.PARAMETER AdminUsername
    Admin username for all VMs. Default: azureuser

.PARAMETER AdminPassword
    Secure string password for Windows VMs. Required unless -Teardown or -Validate.

.PARAMETER SshPublicKey
    SSH public key for Linux VM auth. Falls back to $env:GIT_SIGNING_KEY_PUBLIC or
    the default SSH key at ~/.ssh/id_rsa.pub.

.PARAMETER AllowedSourceIP
    Public IP allowed through NSG rules. Auto-detected from ifconfig.me if not specified.

.PARAMETER ShutdownTime
    Auto-shutdown time in 24h format. Default: 2200

.PARAMETER StartupTime
    Auto-start time in 24h format. Default: 0800

.PARAMETER Timezone
    Timezone for auto-shutdown/start schedules. Default: Pacific Standard Time

.PARAMETER WindowsOsOffer
    Windows OS image offer. Default: WindowsServer

.PARAMETER WindowsOsSku
    Windows OS image SKU. Default: 2025-datacenter-g2

.PARAMETER LinuxOsOffer
    Linux OS image offer. Default: ubuntu-24_04-lts

.PARAMETER LinuxOsSku
    Linux OS image SKU. Default: server (Ubuntu 24.04 server)

.PARAMETER IdleCpuThresholdPercent
    Average CPU percent below which a VM is considered idle. Set to 0 to disable idle shutdown. Default: 5

.PARAMETER IdleTimeoutMinutes
    Minutes a VM must stay below the CPU threshold before being deallocated. Default: 30

.PARAMETER IdleCheckIntervalMinutes
    How often the idle check runbook runs (in minutes). Default: 30

.PARAMETER InstallNodeJs
    Install Node.js on VMs via cloud-init (Linux) and custom script extension (Windows). Default: true

.PARAMETER NodeVersion
    Node.js major version to install. Default: 22

.PARAMETER EnablePenTest
    Enable pen-test mode: opens dashboard ports to deployer IP and deploys attacker VMs with security tools.

.PARAMETER AttackerVmCount
    Number of attacker VMs to deploy for pen testing (only deployed when -EnablePenTest). Default: 1

.PARAMETER Tags
    Hashtable of resource tags. Default: @{ environment = 'test'; project = 'dev-testing' }

.PARAMETER Teardown
    If specified, deletes the resource group and all contained resources.

.PARAMETER Validate
    If specified, validates the Bicep template without deploying.

.PARAMETER SaveConnectionInfo
    If specified, appends VM connection info as environment variables to the specified file.

.PARAMETER ConnectionInfoPath
    Path to save connection info. Used with -SaveConnectionInfo.

.PARAMETER Connect
    If specified, connects to a VM via SSH (Linux) or RDP (Windows). Lists available VMs if -ConnectVmName not provided.

.PARAMETER ConnectVmName
    Name of the VM to connect to. Used with -Connect. If not specified, connects to the first available VM.

.PARAMETER UpdateAllowedIP
    If specified, detects the current public IP and updates all deployer-IP NSG rules in the resource group.

.NOTES
    File Name  : Deploy-AzTestVmEnvironment.ps1
    Requires   : Az PowerShell module, Deploy-AzTestVmEnvironment.bicep
    Version    : 1.0.0
    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)

.LINK
    https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/overview
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ResourceGroupName = 'rg-test-vms',

    [string]$Location = 'westus3',

    [ValidateRange(0, 10)]
    [int]$LinuxVmCount = 1,

    [ValidateRange(0, 10)]
    [int]$WindowsVmCount = 1,

    [string]$LinuxVmSize = 'Standard_B2s',

    [string]$WindowsVmSize = 'Standard_B2ms',

    [string]$AdminUsername = 'azureuser',

    [securestring]$AdminPassword,

    [string]$SshPublicKey,

    [string]$AllowedSourceIP,

    [string]$ShutdownTime = '2200',

    [string]$StartupTime = '0800',

    [string]$Timezone = 'Pacific Standard Time',

    [ValidateSet('WindowsServer', 'windows-11')]
    [string]$WindowsOsOffer = 'WindowsServer',

    [string]$WindowsOsSku = '2025-datacenter-g2',

    [ValidateSet('ubuntu-24_04-lts', 'ubuntu-22_04-lts', '0001-com-ubuntu-server-focal', 'debian-12', 'RHEL')]
    [string]$LinuxOsOffer = 'ubuntu-24_04-lts',

    [string]$LinuxOsSku = 'server',

    [ValidateRange(0, 100)]
    [int]$IdleCpuThresholdPercent = 5,

    [ValidateRange(5, 120)]
    [int]$IdleTimeoutMinutes = 30,

    [ValidateRange(15, 120)]
    [int]$IdleCheckIntervalMinutes = 30,

    [bool]$InstallNodeJs = $true,

    [string]$NodeVersion = '22',

    [switch]$EnablePenTest,

    [ValidateRange(0, 3)]
    [int]$AttackerVmCount = 1,

    [hashtable]$Tags = @{ environment = 'test'; project = 'dev-testing' },

    [switch]$Teardown,

    [switch]$Validate,

    [switch]$SaveConnectionInfo,

    [string]$ConnectionInfoPath,

    [switch]$Connect,

    [string]$ConnectVmName,

    [switch]$UpdateAllowedIP
)

$ErrorActionPreference = 'Stop'
$error.Clear()

function main() {
    $bicepFile = Join-Path $PSScriptRoot '..\..\templates\azure\Deploy-AzTestVmEnvironment.bicep'

    # Verify Azure connection
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Error "Not connected to Azure. Run Connect-AzAccount first."
            return
        }
        Write-Verbose "Connected to Azure subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
    }
    catch {
        Write-Error "Failed to get Azure context. Run Connect-AzAccount first. Error: $_"
        return
    }

    # Handle connect mode
    if ($Connect) {
        connect-ToVm
        return
    }

    # Handle NSG IP update
    if ($UpdateAllowedIP) {
        update-NsgAllowedIP
        return
    }

    # Handle teardown
    if ($Teardown) {
        if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
            Write-Warning "Resource group '$ResourceGroupName' does not exist. Nothing to tear down."
            return
        }

        if ($PSCmdlet.ShouldProcess($ResourceGroupName, 'Delete resource group and all resources')) {
            Write-Host "Deleting resource group '$ResourceGroupName'..." -ForegroundColor Yellow
            Remove-AzResourceGroup -Name $ResourceGroupName -Force
            Write-Host "Resource group '$ResourceGroupName' deleted." -ForegroundColor Green
        }
        return
    }

    # Verify Bicep template exists
    if (-not (Test-Path $bicepFile)) {
        Write-Error "Bicep template not found at: $bicepFile"
        return
    }

    # Auto-detect deployer public IP
    if (-not $AllowedSourceIP) {
        Write-Verbose "Auto-detecting public IP..."
        try {
            $AllowedSourceIP = (Invoke-RestMethod -Uri 'https://ifconfig.me/ip' -TimeoutSec 10).Trim()
            Write-Host "Detected public IP: $AllowedSourceIP" -ForegroundColor Cyan
        }
        catch {
            Write-Error "Failed to detect public IP. Specify -AllowedSourceIP manually. Error: $_"
            return
        }
    }

    # Resolve SSH public key
    if (-not $SshPublicKey -and $LinuxVmCount -gt 0) {
        if ($env:GIT_SIGNING_KEY_PUBLIC) {
            $SshPublicKey = $env:GIT_SIGNING_KEY_PUBLIC
            Write-Verbose "Using SSH key from GIT_SIGNING_KEY_PUBLIC environment variable."
        }
        elseif (Test-Path "$env:USERPROFILE\.ssh\id_rsa.pub") {
            $SshPublicKey = Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub" -Raw
            Write-Verbose "Using SSH key from ~/.ssh/id_rsa.pub."
        }
        elseif (Test-Path "$env:HOME/.ssh/id_rsa.pub") {
            $SshPublicKey = Get-Content "$env:HOME/.ssh/id_rsa.pub" -Raw
            Write-Verbose "Using SSH key from ~/.ssh/id_rsa.pub."
        }
        else {
            Write-Error "No SSH public key found. Specify -SshPublicKey, set GIT_SIGNING_KEY_PUBLIC, or ensure ~/.ssh/id_rsa.pub exists."
            return
        }
        $SshPublicKey = $SshPublicKey.Trim()
    }

    # Require admin password for Windows VMs
    if ($WindowsVmCount -gt 0 -and -not $AdminPassword -and -not $Validate) {
        $AdminPassword = Read-Host "Enter admin password for Windows VMs" -AsSecureString
    }

    # Ensure resource group exists
    if (-not $Validate) {
        $existingRg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
        if ($existingRg) {
            Write-Warning "Resource group '$ResourceGroupName' already exists in $($existingRg.Location)."
            $response = Read-Host "Continue deployment into existing resource group? (y/N)"
            if ($response -notin @('y', 'Y', 'yes', 'Yes')) {
                Write-Host "Deployment cancelled." -ForegroundColor Yellow
                return
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess($ResourceGroupName, "Create resource group in $Location")) {
                Write-Host "Creating resource group '$ResourceGroupName' in $Location..." -ForegroundColor Cyan
                New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag $Tags -Force | Out-Null
            }
        }
    }

    # Build deployment parameters
    $deploymentParams = @{
        location       = $Location
        linuxVmCount   = $LinuxVmCount
        windowsVmCount = $WindowsVmCount
        linuxVmSize    = $LinuxVmSize
        windowsVmSize  = $WindowsVmSize
        adminUsername   = $AdminUsername
        allowedSourceIP = $AllowedSourceIP
        shutdownTime   = $ShutdownTime
        startupTime    = $StartupTime
        timezone       = $Timezone
        windowsOsOffer = $WindowsOsOffer
        windowsOsSku   = $WindowsOsSku
        linuxOsOffer   = $LinuxOsOffer
        linuxOsSku     = $LinuxOsSku
        idleCpuThresholdPercent  = $IdleCpuThresholdPercent
        idleTimeoutMinutes       = $IdleTimeoutMinutes
        idleCheckIntervalMinutes = $IdleCheckIntervalMinutes
        installNodeJs     = $InstallNodeJs
        nodeVersion       = $NodeVersion
        enablePenTest     = [bool]$EnablePenTest
        attackerVmCount   = $AttackerVmCount
        tags           = $Tags
    }

    if ($AdminPassword) {
        $deploymentParams['adminPassword'] = $AdminPassword
    }
    else {
        # Provide a placeholder for validation (won't be deployed)
        $placeholder = New-Object System.Security.SecureString
        'P@ceHolder1!'.ToCharArray() | ForEach-Object { $placeholder.AppendChar($_) }
        $deploymentParams['adminPassword'] = $placeholder
    }

    if ($SshPublicKey) {
        $deploymentParams['sshPublicKey'] = $SshPublicKey
    }
    else {
        # Provide a placeholder for validation when no Linux VMs
        $deploymentParams['sshPublicKey'] = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQ placeholder'
    }

    # Validate only
    if ($Validate) {
        Write-Host "Validating Bicep template..." -ForegroundColor Cyan

        # Ensure resource group exists for validation context
        $existingRg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
        if (-not $existingRg) {
            Write-Host "Creating temporary resource group for validation..." -ForegroundColor Cyan
            New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag $Tags -Force | Out-Null
            $tempRg = $true
        }

        try {
            $result = Test-AzResourceGroupDeployment `
                -ResourceGroupName $ResourceGroupName `
                -TemplateFile $bicepFile `
                -TemplateParameterObject $deploymentParams

            if ($result) {
                Write-Error "Template validation failed:"
                $result | ForEach-Object { Write-Error "  $($_.Message)" }
            }
            else {
                Write-Host "Template validation succeeded." -ForegroundColor Green
            }
        }
        finally {
            if ($tempRg) {
                Write-Host "Cleaning up temporary resource group..." -ForegroundColor Cyan
                Remove-AzResourceGroup -Name $ResourceGroupName -Force | Out-Null
            }
        }
        return
    }

    # Deploy
    $deploymentName = "$ResourceGroupName-$(Get-Date -Format 'yyyyMMddHHmmss')"
    Write-Host "Starting deployment '$deploymentName'..." -ForegroundColor Cyan

    if ($PSCmdlet.ShouldProcess($ResourceGroupName, "Deploy Bicep template")) {
        $deployment = New-AzResourceGroupDeployment `
            -Name $deploymentName `
            -ResourceGroupName $ResourceGroupName `
            -TemplateFile $bicepFile `
            -TemplateParameterObject $deploymentParams `
            -Verbose

        if ($deployment.ProvisioningState -eq 'Succeeded') {
            Write-Host "`nDeployment succeeded!" -ForegroundColor Green
            Write-Host "============================================" -ForegroundColor Green

            # Publish automation runbooks (Bicep creates them in draft state)
            $aaName = $deployment.Outputs.automationAccountName.Value
            publish-AutomationRunbooks -AutomationAccountName $aaName

            # Output connection info
            $connectionInfo = @()

            if ($LinuxVmCount -gt 0) {
                Write-Host "`n--- Linux VMs ---" -ForegroundColor Cyan
                for ($i = 0; $i -lt $LinuxVmCount; $i++) {
                    $vmName = $deployment.Outputs.linuxVmNames.Value[$i]
                    $ip = $deployment.Outputs.linuxPublicIps.Value[$i]
                    $fqdn = $deployment.Outputs.linuxFqdns.Value[$i]
                    $ssh = $deployment.Outputs.linuxSshCommands.Value[$i]

                    Write-Host "  VM: $vmName" -ForegroundColor White
                    Write-Host "  IP: $ip" -ForegroundColor White
                    Write-Host "  FQDN: $fqdn" -ForegroundColor White
                    Write-Host "  SSH: $ssh" -ForegroundColor Yellow
                    Write-Host ""

                    $connectionInfo += "AZURE_TEST_VM_LINUX_${i}_NAME=$vmName"
                    $connectionInfo += "AZURE_TEST_VM_LINUX_${i}_IP=$ip"
                    $connectionInfo += "AZURE_TEST_VM_LINUX_${i}_FQDN=$fqdn"
                }
            }

            if ($WindowsVmCount -gt 0) {
                Write-Host "`n--- Windows VMs ---" -ForegroundColor Cyan
                for ($i = 0; $i -lt $WindowsVmCount; $i++) {
                    $vmName = $deployment.Outputs.windowsVmNames.Value[$i]
                    $ip = $deployment.Outputs.windowsPublicIps.Value[$i]
                    $fqdn = $deployment.Outputs.windowsFqdns.Value[$i]
                    $rdp = $deployment.Outputs.windowsRdpCommands.Value[$i]

                    Write-Host "  VM: $vmName" -ForegroundColor White
                    Write-Host "  IP: $ip" -ForegroundColor White
                    Write-Host "  FQDN: $fqdn" -ForegroundColor White
                    Write-Host "  RDP: $rdp" -ForegroundColor Yellow
                    Write-Host ""

                    $connectionInfo += "AZURE_TEST_VM_WIN_${i}_NAME=$vmName"
                    $connectionInfo += "AZURE_TEST_VM_WIN_${i}_IP=$ip"
                    $connectionInfo += "AZURE_TEST_VM_WIN_${i}_FQDN=$fqdn"
                }
            }

            # Save connection info if requested
            if ($SaveConnectionInfo -and $ConnectionInfoPath) {
                Write-Host "Saving connection info to $ConnectionInfoPath..." -ForegroundColor Cyan
                $header = "`n# Azure Test VM Environment - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                $header | Out-File -Append -FilePath $ConnectionInfoPath -Encoding utf8
                $connectionInfo | Out-File -Append -FilePath $ConnectionInfoPath -Encoding utf8
                Write-Host "Connection info saved." -ForegroundColor Green
            }

            # Output attacker VMs if pen-test mode
            if ($EnablePenTest -and $AttackerVmCount -gt 0) {
                Write-Host "`n--- Attacker VMs (Pen-Test) ---" -ForegroundColor Magenta
                for ($i = 0; $i -lt $AttackerVmCount; $i++) {
                    $vmName = $deployment.Outputs.attackerVmNames.Value[$i]
                    $ip = $deployment.Outputs.attackerPublicIps.Value[$i]
                    $fqdn = $deployment.Outputs.attackerFqdns.Value[$i]
                    $ssh = $deployment.Outputs.attackerSshCommands.Value[$i]

                    Write-Host "  VM: $vmName" -ForegroundColor White
                    Write-Host "  IP: $ip" -ForegroundColor White
                    Write-Host "  FQDN: $fqdn" -ForegroundColor White
                    Write-Host "  SSH: $ssh" -ForegroundColor Yellow
                    Write-Host "  Tools: nmap, nikto, ZAP, certbot, node" -ForegroundColor DarkGray
                    Write-Host ""
                }
            }
        }
        else {
            Write-Error "Deployment failed with state: $($deployment.ProvisioningState)"
        }
    }
}

main
$error | Out-String
Write-Host "$([DateTime]::Now) finished"

# ============================================================================
# Helper: Connect to VM via SSH or RDP
# ============================================================================
function connect-ToVm() {
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $rg) {
        Write-Error "Resource group '$ResourceGroupName' not found."
        return
    }

    # Get all VMs with status
    $vms = Get-AzVM -ResourceGroupName $ResourceGroupName -Status -ErrorAction Stop
    if (-not $vms) {
        Write-Error "No VMs found in '$ResourceGroupName'."
        return
    }

    # Build VM info table
    $vmInfo = @()
    foreach ($vm in $vms) {
        $nicId = $vm.NetworkProfile.NetworkInterfaces[0].Id
        $nic = Get-AzNetworkInterface -ResourceId $nicId -ErrorAction SilentlyContinue
        $pipId = $nic.IpConfigurations[0].PublicIpAddress.Id
        $pip = if ($pipId) { Get-AzPublicIpAddress -ResourceId $pipId -ErrorAction SilentlyContinue } else { $null }
        $isLinux = $vm.StorageProfile.OsDisk.OsType -eq 'Linux'

        $vmInfo += [PSCustomObject]@{
            Name      = $vm.Name
            OS        = if ($isLinux) { 'Linux' } else { 'Windows' }
            State     = $vm.PowerState
            PublicIP  = if ($pip) { $pip.IpAddress } else { 'N/A' }
            FQDN      = if ($pip -and $pip.DnsSettings) { $pip.DnsSettings.Fqdn } else { 'N/A' }
            Protocol  = if ($isLinux) { 'SSH' } else { 'RDP' }
        }
    }

    # If no VM specified, show list and pick first running one
    if (-not $ConnectVmName) {
        Write-Host "`nAvailable VMs in '$ResourceGroupName':" -ForegroundColor Cyan
        $vmInfo | Format-Table -AutoSize | Out-String | Write-Host

        $target = $vmInfo | Where-Object { $_.State -eq 'VM running' } | Select-Object -First 1
        if (-not $target) {
            Write-Warning "No running VMs found. Start a VM first."
            return
        }
        Write-Host "Auto-selecting first running VM: $($target.Name)" -ForegroundColor Yellow
    }
    else {
        $target = $vmInfo | Where-Object { $_.Name -eq $ConnectVmName }
        if (-not $target) {
            Write-Error "VM '$ConnectVmName' not found. Available: $($vmInfo.Name -join ', ')"
            return
        }
    }

    if ($target.State -ne 'VM running') {
        Write-Warning "VM '$($target.Name)' is $($target.State). It must be running to connect."
        return
    }

    $connectHost = if ($target.FQDN -ne 'N/A') { $target.FQDN } else { $target.PublicIP }
    if ($connectHost -eq 'N/A') {
        Write-Error "VM '$($target.Name)' has no public IP or FQDN."
        return
    }

    if ($target.Protocol -eq 'SSH') {
        $sshCmd = "ssh $AdminUsername@$connectHost"
        Write-Host "Connecting: $sshCmd" -ForegroundColor Green
        & ssh $AdminUsername $connectHost
    }
    else {
        $rdpCmd = "mstsc /v:$connectHost"
        Write-Host "Connecting: $rdpCmd" -ForegroundColor Green
        & mstsc /v:$connectHost
    }
}

# ============================================================================
# Helper: Update NSG deployer-IP rules with current public IP
# ============================================================================
function update-NsgAllowedIP() {
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $rg) {
        Write-Error "Resource group '$ResourceGroupName' not found."
        return
    }

    # Detect current public IP
    $currentIP = if ($AllowedSourceIP) { $AllowedSourceIP } else {
        try {
            (Invoke-RestMethod -Uri 'https://ifconfig.me/ip' -TimeoutSec 10).Trim()
        }
        catch {
            Write-Error "Failed to detect public IP. Specify -AllowedSourceIP. Error: $_"
            return
        }
    }
    Write-Host "Current public IP: $currentIP" -ForegroundColor Cyan

    # Find NSGs in the resource group
    $nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    if (-not $nsgs) {
        Write-Error "No NSGs found in '$ResourceGroupName'."
        return
    }

    # Deployer-IP rule name patterns
    $deployerRulePatterns = @('Allow-SSH-Deployer', 'Allow-RDP-Deployer', 'Allow-CustomPorts-Deployer',
        'Allow-Dashboard-Deployer-PenTest', 'Allow-HTTPS-Deployer-PenTest')

    foreach ($nsg in $nsgs) {
        $updated = $false
        foreach ($rule in $nsg.SecurityRules) {
            if ($rule.Name -in $deployerRulePatterns) {
                $oldIP = $rule.SourceAddressPrefix
                if ($oldIP -eq $currentIP) {
                    Write-Host "  $($nsg.Name) / $($rule.Name): already $currentIP" -ForegroundColor DarkGray
                    continue
                }
                Write-Host "  $($nsg.Name) / $($rule.Name): $oldIP -> $currentIP" -ForegroundColor Yellow
                $rule.SourceAddressPrefix = $currentIP
                $updated = $true
            }
        }

        if ($updated) {
            if ($PSCmdlet.ShouldProcess($nsg.Name, "Update NSG deployer-IP rules to $currentIP")) {
                Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg | Out-Null
                Write-Host "  $($nsg.Name): NSG updated." -ForegroundColor Green
            }
        }
        else {
            Write-Host "  $($nsg.Name): no deployer rules to update." -ForegroundColor DarkGray
        }
    }
}

# ============================================================================
# Helper: Publish automation runbooks with inline content
# ============================================================================
function publish-AutomationRunbooks {
    param([string]$AutomationAccountName)

    Write-Host "`nPublishing automation runbooks..." -ForegroundColor Cyan

    # Auto-start runbook content
    $startContent = @'
param(
    [string]$ResourceGroupName
)
try {
    Connect-AzAccount -Identity -ErrorAction Stop
    Write-Output "Authenticated with managed identity."
    $vms = Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    Write-Output "Found $($vms.Count) VMs in '$ResourceGroupName'."
    foreach ($vm in $vms) {
        Write-Output "Starting VM: $($vm.Name)..."
        Start-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -NoWait -ErrorAction Continue
    }
    Write-Output "All VM start commands sent."
} catch {
    Write-Error "Failed to start VMs: $_"
    throw
}
'@

    # Idle shutdown runbook content
    $idleContent = @'
param(
    [string]$ResourceGroupName,
    [int]$CpuThresholdPercent = 5,
    [int]$IdleMinutes = 30
)
try {
    Connect-AzAccount -Identity -ErrorAction Stop
    $vms = Get-AzVM -ResourceGroupName $ResourceGroupName -Status -ErrorAction Stop
    $runningVms = $vms | Where-Object { $_.PowerState -eq 'VM running' }
    Write-Output "Found $($runningVms.Count) running VMs in '$ResourceGroupName'."
    $endTime = (Get-Date).ToUniversalTime()
    $startTime = $endTime.AddMinutes(-$IdleMinutes)
    foreach ($vm in $runningVms) {
        $metrics = Get-AzMetric -ResourceId $vm.Id -MetricName 'Percentage CPU' `
            -StartTime $startTime -EndTime $endTime -TimeGrain 00:05:00 `
            -AggregationType Average -ErrorAction SilentlyContinue
        if (-not $metrics -or -not $metrics.Data) { continue }
        $avgCpu = ($metrics.Data | Where-Object { $null -ne $_.Average } |
            Measure-Object -Property Average -Average).Average
        if ($null -eq $avgCpu) { continue }
        Write-Output "$($vm.Name): CPU $([math]::Round($avgCpu,2))%"
        if ($avgCpu -lt $CpuThresholdPercent) {
            Write-Output "  Idle — deallocating $($vm.Name)..."
            Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -Force -NoWait -ErrorAction Continue
        }
    }
    Write-Output "Idle check complete."
} catch {
    Write-Error "Idle shutdown failed: $_"
    throw
}
'@

    $runbooks = @(
        @{ Name = 'Start-TestVMs'; Content = $startContent }
    )

    if ($IdleCpuThresholdPercent -gt 0) {
        $runbooks += @{ Name = 'Stop-IdleTestVMs'; Content = $idleContent }
    }

    foreach ($rb in $runbooks) {
        try {
            # Write content to temp file (Set-AzAutomationRunbookDefinition requires a file)
            $tempFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.ps1'
            $rb.Content | Out-File -FilePath $tempFile -Encoding utf8 -Force

            Write-Verbose "  Publishing runbook: $($rb.Name)"
            Import-AzAutomationRunbook `
                -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName `
                -Name $rb.Name `
                -Path $tempFile `
                -Type PowerShell72 `
                -Force | Out-Null

            Publish-AzAutomationRunbook `
                -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName `
                -Name $rb.Name | Out-Null

            Write-Host "  Published: $($rb.Name)" -ForegroundColor Green
        }
        catch {
            Write-Warning "  Failed to publish $($rb.Name): $_"
        }
        finally {
            if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        }
    }
}
