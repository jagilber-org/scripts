// Deploy-AzTestVmEnvironment.bicep
// Provisions a configurable set of Linux and Windows test VMs in Azure
// with public IPs, NSG restricted to deployer IP, auto-shutdown/start,
// B-series burstable SKUs, and dev tooling pre-installed.

@description('Azure region for all resources')
param location string = 'westus3'

@description('Number of Linux VMs to deploy')
@minValue(0)
@maxValue(10)
param linuxVmCount int = 1

@description('Number of Windows VMs to deploy')
@minValue(0)
@maxValue(10)
param windowsVmCount int = 1

@description('Linux VM size (B-series recommended for cost efficiency)')
param linuxVmSize string = 'Standard_B2s'

@description('Windows VM size (B-series recommended for cost efficiency)')
param windowsVmSize string = 'Standard_B2ms'

@description('Admin username for all VMs')
param adminUsername string = 'azureuser'

@description('Admin password for Windows VMs')
@secure()
param adminPassword string

@description('SSH public key for Linux VM authentication')
param sshPublicKey string

@description('Public IP address allowed to access VMs (deployer IP)')
param allowedSourceIP string

@description('Auto-shutdown time in 24h format (e.g. 2200 = 10:00 PM)')
param shutdownTime string = '2200'

@description('Auto-start time in 24h format (e.g. 0800 = 8:00 AM)')
param startupTime string = '0800'

@description('Timezone for auto-shutdown/start schedules')
param timezone string = 'Pacific Standard Time'

@description('Windows OS image offer (WindowsServer or windows-11)')
@allowed([
  'WindowsServer'
  'windows-11'
])
param windowsOsOffer string = 'WindowsServer'

@description('Windows OS image SKU')
param windowsOsSku string = '2025-datacenter-g2'

@description('Linux OS image publisher')
param linuxPublisher string = 'Canonical'

@description('Linux OS image offer')
@allowed([
  'ubuntu-24_04-lts'
  'ubuntu-22_04-lts'
  '0001-com-ubuntu-server-focal'
  'debian-12'
  'RHEL'
])
param linuxOsOffer string = 'ubuntu-24_04-lts'

@description('Linux OS image SKU')
param linuxOsSku string = 'server'

@description('Average CPU percent threshold below which VMs are considered idle (0 to disable idle shutdown)')
@minValue(0)
@maxValue(100)
param idleCpuThresholdPercent int = 5

@description('Number of minutes a VM must be idle before auto-shutdown (used by idle runbook)')
@minValue(5)
@maxValue(120)
param idleTimeoutMinutes int = 30

@description('Idle shutdown check interval in minutes (how often the runbook runs)')
@minValue(15)
@maxValue(120)
param idleCheckIntervalMinutes int = 30

@description('Install Node.js on VMs via cloud-init (Linux) and custom script extension (Windows)')
param installNodeJs bool = true

@description('Node.js major version to install')
param nodeVersion string = '22'

@description('Enable pen-test mode: opens dashboard ports to deployer IP, installs security tools on attacker VM')
param enablePenTest bool = false

@description('Number of attacker VMs to deploy for pen testing (only deployed when enablePenTest is true)')
@minValue(0)
@maxValue(3)
param attackerVmCount int = 1

@description('Resource tags')
param tags object = {
  environment: 'test'
  project: 'dev-testing'
}

@description('Base time for schedule start (defaults to current UTC time, used internally)')
param baseTime string = utcNow()

// Variables
var vnetName = 'vnet-test-vms'
var subnetName = 'snet-default'
var nsgName = 'nsg-test-vms'
var vnetAddressPrefix = '10.0.0.0/16'
var subnetAddressPrefix = '10.0.0.0/24'
var automationAccountName = 'aa-test-vms-${uniqueString(resourceGroup().id)}'
var runbookName = 'Start-TestVMs'
var idleRunbookName = 'Stop-IdleTestVMs'

var windowsPublisher = windowsOsOffer == 'WindowsServer' ? 'MicrosoftWindowsServer' : 'MicrosoftWindowsDesktop'
var windowsSkuMap = {
  WindowsServer: windowsOsSku
  'windows-11': 'win11-24h2-pro'
}
var actualWindowsSku = windowsSkuMap[windowsOsOffer]

// Linux image mapping for non-Canonical publishers
var linuxPublisherMap = {
  'ubuntu-24_04-lts': 'Canonical'
  'ubuntu-22_04-lts': 'Canonical'
  '0001-com-ubuntu-server-focal': 'Canonical'
  'debian-12': 'Debian'
  'RHEL': 'RedHat'
}
var actualLinuxPublisher = linuxPublisher != 'Canonical' ? linuxPublisher : linuxPublisherMap[linuxOsOffer]
var linuxSkuMap = {
  'ubuntu-24_04-lts': linuxOsSku
  'ubuntu-22_04-lts': '22_04-lts-gen2'
  '0001-com-ubuntu-server-focal': '20_04-lts-gen2'
  'debian-12': '12-gen2'
  'RHEL': '9-lvm-gen2'
}
var actualLinuxSku = linuxOsSku != 'server' ? linuxOsSku : linuxSkuMap[linuxOsOffer]

// Cloud-init script for Linux VMs - conditionally installs Node.js, npm, git, docker
var linuxCloudInitWithNode = '''#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Update and install prerequisites
apt-get update -y
apt-get install -y ca-certificates curl gnupg git apt-transport-https

# Install Node.js {0} LTS
curl -fsSL https://deb.nodesource.com/setup_{0}.x | bash -
apt-get install -y nodejs

# Install Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${{UBUNTU_CODENAME:-$VERSION_CODENAME}}") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add admin user to docker group
usermod -aG docker {1} || true

# Verify installations
node --version
npm --version
git --version
docker --version

echo "Cloud-init provisioning complete" > /var/log/cloud-init-custom.log
'''

var linuxCloudInitNoNode = '''#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Update and install prerequisites
apt-get update -y
apt-get install -y ca-certificates curl gnupg git apt-transport-https

# Install Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${{UBUNTU_CODENAME:-$VERSION_CODENAME}}") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add admin user to docker group
usermod -aG docker {0} || true

git --version
docker --version

echo "Cloud-init provisioning complete" > /var/log/cloud-init-custom.log
'''

var linuxCloudInitRaw = installNodeJs ? format(linuxCloudInitWithNode, nodeVersion, adminUsername) : format(linuxCloudInitNoNode, adminUsername)
var linuxCloudInit = base64(linuxCloudInitRaw)

// Windows custom script extension - conditionally installs Node.js, git, VS Code
var windowsInstallScriptWithNode = format('''
$ErrorActionPreference = "Continue"
$logFile = "C:\\WindowsAzure\\Logs\\custom-script-install.log"

function Write-Log {{
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -Append -FilePath $logFile
    Write-Output $Message
}}

Write-Log "Starting software installation..."

# Install Node.js {0} LTS
Write-Log "Installing Node.js {0} LTS..."
$nodeIndexUrl = "https://nodejs.org/dist/latest-v{0}.x/"
$nodeIndexPage = Invoke-WebRequest -Uri $nodeIndexUrl -UseBasicParsing
$msiMatch = [regex]::Match($nodeIndexPage.Content, "node-v{0}\.\d+\.\d+-x64\.msi")
if ($msiMatch.Success) {{
    $nodeUrl = "$nodeIndexUrl$($msiMatch.Value)"
}} else {{
    $nodeUrl = "https://nodejs.org/dist/latest-v{0}.x/node-v{0}.0.0-x64.msi"
}}
$nodeInstaller = "$env:TEMP\\node-v{0}-x64.msi"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $nodeUrl -OutFile $nodeInstaller -UseBasicParsing
Start-Process msiexec.exe -ArgumentList "/i `"$nodeInstaller`" /qn /norestart" -Wait -NoNewWindow
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
Write-Log "Node.js installed."

# Install Git
Write-Log "Installing Git..."
$gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe" # pii-allowlist
$gitInstaller = "$env:TEMP\\git-installer.exe"
Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
Start-Process $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS=`"icons,ext\\reg\\shellhere,assoc,assoc_sh`"" -Wait -NoNewWindow
Write-Log "Git installed."

# Install VS Code
Write-Log "Installing VS Code..."
$vscodeUrl = "https://update.code.visualstudio.com/latest/win32-x64/stable"
$vscodeInstaller = "$env:TEMP\\vscode-installer.exe"
Invoke-WebRequest -Uri $vscodeUrl -OutFile $vscodeInstaller -UseBasicParsing
Start-Process $vscodeInstaller -ArgumentList "/verysilent /norestart /mergetasks=!runcode,addcontextmenufiles,addcontextmenufolders,addtopath" -Wait -NoNewWindow
Write-Log "VS Code installed."

Write-Log "All installations complete."
''', nodeVersion)

var windowsInstallScriptNoNode = '''
$ErrorActionPreference = "Continue"
$logFile = "C:\\WindowsAzure\\Logs\\custom-script-install.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -Append -FilePath $logFile
    Write-Output $Message
}

Write-Log "Starting software installation..."

# Install Git
Write-Log "Installing Git..."
$gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe" # pii-allowlist
$gitInstaller = "$env:TEMP\\git-installer.exe"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
Start-Process $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS=`"icons,ext\\reg\\shellhere,assoc,assoc_sh`"" -Wait -NoNewWindow
Write-Log "Git installed."

# Install VS Code
Write-Log "Installing VS Code..."
$vscodeUrl = "https://update.code.visualstudio.com/latest/win32-x64/stable"
$vscodeInstaller = "$env:TEMP\\vscode-installer.exe"
Invoke-WebRequest -Uri $vscodeUrl -OutFile $vscodeInstaller -UseBasicParsing
Start-Process $vscodeInstaller -ArgumentList "/verysilent /norestart /mergetasks=!runcode,addcontextmenufiles,addcontextmenufolders,addtopath" -Wait -NoNewWindow
Write-Log "VS Code installed."

Write-Log "All installations complete."
'''

var windowsInstallScript = installNodeJs ? windowsInstallScriptWithNode : windowsInstallScriptNoNode

// PowerShell runbook script for auto-starting VMs
var autoStartRunbookContent = '''
<#
.SYNOPSIS
    Starts all VMs in the specified resource group.
.DESCRIPTION
    Azure Automation runbook that starts all VMs in the resource group
    using the system-assigned managed identity.
#>
param(
    [string]$ResourceGroupName
)

try {
    # Authenticate with system-assigned managed identity
    Connect-AzAccount -Identity -ErrorAction Stop
    Write-Output "Authenticated with managed identity."

    # Get all VMs in the resource group
    $vms = Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction Stop
    Write-Output "Found $($vms.Count) VMs in resource group '$ResourceGroupName'."

    foreach ($vm in $vms) {
        Write-Output "Starting VM: $($vm.Name)..."
        Start-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -NoWait -ErrorAction Continue
        Write-Output "Start command sent for VM: $($vm.Name)"
    }

    Write-Output "All VM start commands have been sent."
}
catch {
    Write-Error "Failed to start VMs: $_"
    throw
}
'''

// PowerShell runbook script for idle shutdown - monitors CPU and stops idle VMs
var idleShutdownRunbookContent = '''
<#
.SYNOPSIS
    Stops VMs that have been idle (low CPU) for a specified duration.
.DESCRIPTION
    Azure Automation runbook that checks average CPU usage of all running VMs
    in the resource group. If a VM's average CPU has been below the threshold
    for the configured period, it is deallocated to save costs.
#>
param(
    [string]$ResourceGroupName,
    [int]$CpuThresholdPercent = 5,
    [int]$IdleMinutes = 30
)

try {
    Connect-AzAccount -Identity -ErrorAction Stop
    Write-Output "Authenticated with managed identity."

    $vms = Get-AzVM -ResourceGroupName $ResourceGroupName -Status -ErrorAction Stop
    $runningVms = $vms | Where-Object { $_.PowerState -eq 'VM running' }
    Write-Output "Found $($runningVms.Count) running VMs in '$ResourceGroupName'."

    $endTime = (Get-Date).ToUniversalTime()
    $startTime = $endTime.AddMinutes(-$IdleMinutes)

    foreach ($vm in $runningVms) {
        Write-Output "Checking VM: $($vm.Name)..."

        $metrics = Get-AzMetric `
            -ResourceId $vm.Id `
            -MetricName 'Percentage CPU' `
            -StartTime $startTime `
            -EndTime $endTime `
            -TimeGrain 00:05:00 `
            -AggregationType Average `
            -ErrorAction SilentlyContinue

        if (-not $metrics -or -not $metrics.Data) {
            Write-Output "  No CPU metrics available for $($vm.Name), skipping."
            continue
        }

        $avgCpu = ($metrics.Data | Where-Object { $null -ne $_.Average } |
            Measure-Object -Property Average -Average).Average

        if ($null -eq $avgCpu) {
            Write-Output "  No CPU data points for $($vm.Name), skipping."
            continue
        }

        Write-Output "  Average CPU over last ${IdleMinutes}m: $([math]::Round($avgCpu, 2))%"

        if ($avgCpu -lt $CpuThresholdPercent) {
            Write-Output "  VM $($vm.Name) is idle (CPU $([math]::Round($avgCpu, 2))% < ${CpuThresholdPercent}%). Deallocating..."
            Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $vm.Name -Force -NoWait -ErrorAction Continue
            Write-Output "  Deallocate command sent for $($vm.Name)."
        }
        else {
            Write-Output "  VM $($vm.Name) is active (CPU $([math]::Round($avgCpu, 2))%)."
        }
    }

    Write-Output "Idle check complete."
}
catch {
    Write-Error "Idle shutdown runbook failed: $_"
    throw
}
'''

// ============================================================================
// Network Security Group
// ============================================================================
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: concat([
      {
        name: 'Allow-SSH-Deployer'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: allowedSourceIP
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-RDP-Deployer'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: allowedSourceIP
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-HTTP-Any'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-HTTPS-Any'
        properties: {
          priority: 210
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-Dashboard-VNet'
        properties: {
          priority: 220
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '8787'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          description: 'Dashboard access from within VNet only'
        }
      }
      {
        name: 'Allow-CustomPorts-Deployer'
        properties: {
          priority: 300
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3000-9999'
          sourceAddressPrefix: allowedSourceIP
          destinationAddressPrefix: '*'
        }
      }
    ], enablePenTest ? [
      {
        name: 'Allow-Dashboard-Deployer-PenTest'
        properties: {
          priority: 320
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '8787'
          sourceAddressPrefix: allowedSourceIP
          destinationAddressPrefix: '*'
          description: 'Dashboard direct access from deployer IP (pen-test mode)'
        }
      }
      {
        name: 'Allow-HTTPS-Deployer-PenTest'
        properties: {
          priority: 330
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: allowedSourceIP
          destinationAddressPrefix: '*'
          description: 'HTTPS dashboard with TLS from deployer IP (pen-test mode)'
        }
      }
    ] : [])
  }
}

// ============================================================================
// Virtual Network + Subnet
// ============================================================================
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// ============================================================================
// Linux VMs
// ============================================================================
resource linuxPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = [for i in range(0, linuxVmCount): {
  name: 'pip-linux-${i}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'testvm-linux-${uniqueString(resourceGroup().id)}-${i}'
    }
  }
}]

resource linuxNic 'Microsoft.Network/networkInterfaces@2024-05-01' = [for i in range(0, linuxVmCount): {
  name: 'nic-linux-${i}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          publicIPAddress: {
            id: linuxPublicIp[i].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}]

resource linuxVm 'Microsoft.Compute/virtualMachines@2024-07-01' = [for i in range(0, linuxVmCount): {
  name: 'vm-linux-${i}'
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: linuxVmSize
    }
    osProfile: {
      computerName: 'linux${i}'
      adminUsername: adminUsername
      customData: linuxCloudInit
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: actualLinuxPublisher
        offer: linuxOsOffer
        sku: actualLinuxSku
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: linuxNic[i].id
        }
      ]
    }
  }
}]

// Auto-shutdown for Linux VMs
resource linuxAutoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = [for i in range(0, linuxVmCount): {
  name: 'shutdown-computevm-vm-linux-${i}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: shutdownTime
    }
    timeZoneId: timezone
    targetResourceId: linuxVm[i].id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}]

// ============================================================================
// Windows VMs
// ============================================================================
resource windowsPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = [for i in range(0, windowsVmCount): {
  name: 'pip-windows-${i}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'testvm-win-${uniqueString(resourceGroup().id)}-${i}'
    }
  }
}]

resource windowsNic 'Microsoft.Network/networkInterfaces@2024-05-01' = [for i in range(0, windowsVmCount): {
  name: 'nic-windows-${i}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          publicIPAddress: {
            id: windowsPublicIp[i].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}]

resource windowsVm 'Microsoft.Compute/virtualMachines@2024-07-01' = [for i in range(0, windowsVmCount): {
  name: 'vm-windows-${i}'
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: windowsVmSize
    }
    osProfile: {
      computerName: 'win${i}'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: windowsPublisher
        offer: windowsOsOffer
        sku: actualWindowsSku
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: windowsNic[i].id
        }
      ]
    }
  }
}]

// Custom Script Extension for Windows VMs - install Node.js, Git, VS Code
resource windowsCustomScript 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = [for i in range(0, windowsVmCount): {
  parent: windowsVm[i]
  name: 'install-dev-tools'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    forceUpdateTag: baseTime
    settings: {}
    protectedSettings: {
      commandToExecute: 'powershell -ExecutionPolicy Bypass -Command "${windowsInstallScript}"'
    }
  }
}]

// Auto-shutdown for Windows VMs
resource windowsAutoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = [for i in range(0, windowsVmCount): {
  name: 'shutdown-computevm-vm-windows-${i}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: shutdownTime
    }
    timeZoneId: timezone
    targetResourceId: windowsVm[i].id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}]

// ============================================================================
// Azure Automation Account + Runbook for auto-start
// ============================================================================
resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
  }
}

resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: runbookName
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Starts all VMs in the resource group on a schedule'
  }
}

// Schedule for auto-start (weekdays)
resource startSchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'weekday-auto-start'
  properties: {
    frequency: 'Week'
    interval: 1
    timeZone: timezone
    startTime: dateTimeAdd(baseTime, 'P1D') // start from tomorrow
    advancedSchedule: {
      weekDays: [
        'Monday'
        'Tuesday'
        'Wednesday'
        'Thursday'
        'Friday'
      ]
    }
    description: 'Auto-start VMs on weekdays at ${startupTime}'
  }
}

// Link schedule to runbook
resource jobSchedule 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
  parent: automationAccount
  name: guid(automationAccount.id, startSchedule.name, runbook.name)
  properties: {
    runbook: {
      name: runbook.name
    }
    schedule: {
      name: startSchedule.name
    }
    parameters: {
      ResourceGroupName: resourceGroup().name
    }
  }
}

// Role assignment: Automation Account managed identity -> VM Contributor on RG
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(automationAccount.id, 'Virtual Machine Contributor', resourceGroup().id)
  properties: {
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9980e02c-c2be-4d73-94e8-173b1dc7cf3c') // Virtual Machine Contributor
  }
}

// Role assignment: Automation Account -> Monitoring Reader (for reading CPU metrics)
resource monitoringRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(automationAccount.id, 'Monitoring Reader', resourceGroup().id)
  properties: {
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05') // Monitoring Reader
  }
}

// ============================================================================
// Idle Shutdown Runbook + Schedule (disabled when idleCpuThresholdPercent == 0)
// ============================================================================
resource idleRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = if (idleCpuThresholdPercent > 0) {
  parent: automationAccount
  name: idleRunbookName
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    description: 'Monitors CPU metrics and deallocates idle VMs to save costs'
  }
}

resource idleSchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = if (idleCpuThresholdPercent > 0) {
  parent: automationAccount
  name: 'idle-vm-check'
  properties: {
    frequency: 'Hour'
    interval: 1
    timeZone: timezone
    startTime: dateTimeAdd(baseTime, 'PT1H')
    description: 'Check for idle VMs every ${idleCheckIntervalMinutes} minutes'
  }
}

resource idleJobSchedule 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (idleCpuThresholdPercent > 0) {
  parent: automationAccount
  name: guid(automationAccount.id, 'idle-vm-check', idleRunbookName)
  properties: {
    runbook: {
      name: idleRunbook.name
    }
    schedule: {
      name: idleSchedule.name
    }
    parameters: {
      ResourceGroupName: resourceGroup().name
      CpuThresholdPercent: '${idleCpuThresholdPercent}'
      IdleMinutes: '${idleTimeoutMinutes}'
    }
  }
}

// ============================================================================
// Pen-Test Attacker VMs (only deployed when enablePenTest is true)
// ============================================================================

// Cloud-init for attacker VMs: installs security/pen-test tools
var attackerCloudInit = base64(format('''#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y ca-certificates curl gnupg git apt-transport-https nmap nikto \
  python3 python3-pip net-tools dnsutils whois traceroute tcpdump jq

# Install Node.js {0} LTS (for testing target services)
curl -fsSL https://deb.nodesource.com/setup_{0}.x | bash -
apt-get install -y nodejs

# Install OWASP ZAP (headless)
apt-get install -y default-jre
mkdir -p /opt/zap
curl -fsSL https://github.com/zaproxy/zaproxy/releases/download/v2.16.1/ZAP_2.16.1_Linux.tar.gz | tar xz -C /opt/zap --strip-components=1
ln -sf /opt/zap/zap.sh /usr/local/bin/zap

# Install certbot for Let's Encrypt testing
apt-get install -y certbot

# Add admin user to docker group if docker installed
usermod -aG docker {1} || true

echo "Attacker VM provisioning complete" > /var/log/cloud-init-custom.log
''', nodeVersion, adminUsername))

resource attackerPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = [for i in range(0, enablePenTest ? attackerVmCount : 0): {
  name: 'pip-attacker-${i}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'testvm-attacker-${uniqueString(resourceGroup().id)}-${i}'
    }
  }
}]

resource attackerNic 'Microsoft.Network/networkInterfaces@2024-05-01' = [for i in range(0, enablePenTest ? attackerVmCount : 0): {
  name: 'nic-attacker-${i}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          publicIPAddress: {
            id: attackerPublicIp[i].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}]

resource attackerVm 'Microsoft.Compute/virtualMachines@2024-07-01' = [for i in range(0, enablePenTest ? attackerVmCount : 0): {
  name: 'vm-attacker-${i}'
  location: location
  tags: union(tags, { role: 'pen-test-attacker' })
  properties: {
    hardwareProfile: {
      vmSize: linuxVmSize
    }
    osProfile: {
      computerName: 'attacker${i}'
      adminUsername: adminUsername
      customData: attackerCloudInit
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: attackerNic[i].id
        }
      ]
    }
  }
}]

// Auto-shutdown for attacker VMs
resource attackerAutoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = [for i in range(0, enablePenTest ? attackerVmCount : 0): {
  name: 'shutdown-computevm-vm-attacker-${i}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: shutdownTime
    }
    timeZoneId: timezone
    targetResourceId: attackerVm[i].id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}]

// ============================================================================
// Outputs
// ============================================================================
output linuxVmNames array = [for i in range(0, linuxVmCount): linuxVm[i].name]
output linuxPublicIps array = [for i in range(0, linuxVmCount): linuxPublicIp[i].properties.ipAddress]
output linuxFqdns array = [for i in range(0, linuxVmCount): linuxPublicIp[i].properties.dnsSettings.fqdn]
output linuxSshCommands array = [for i in range(0, linuxVmCount): 'ssh ${adminUsername}@${linuxPublicIp[i].properties.dnsSettings.fqdn}']

output windowsVmNames array = [for i in range(0, windowsVmCount): windowsVm[i].name]
output windowsPublicIps array = [for i in range(0, windowsVmCount): windowsPublicIp[i].properties.ipAddress]
output windowsFqdns array = [for i in range(0, windowsVmCount): windowsPublicIp[i].properties.dnsSettings.fqdn]
output windowsRdpCommands array = [for i in range(0, windowsVmCount): 'mstsc /v:${windowsPublicIp[i].properties.dnsSettings.fqdn}']

output automationAccountName string = automationAccount.name
output automationPrincipalId string = automationAccount.identity.principalId
output autoStartRunbookScript string = autoStartRunbookContent
output idleShutdownRunbookScript string = idleShutdownRunbookContent
output idleShutdownEnabled bool = idleCpuThresholdPercent > 0
output penTestEnabled bool = enablePenTest
output attackerVmNames array = [for i in range(0, enablePenTest ? attackerVmCount : 0): attackerVm[i].name]
output attackerPublicIps array = [for i in range(0, enablePenTest ? attackerVmCount : 0): attackerPublicIp[i].properties.ipAddress]
output attackerFqdns array = [for i in range(0, enablePenTest ? attackerVmCount : 0): attackerPublicIp[i].properties.dnsSettings.fqdn]
output attackerSshCommands array = [for i in range(0, enablePenTest ? attackerVmCount : 0): 'ssh ${adminUsername}@${attackerPublicIp[i].properties.dnsSettings.fqdn}']
