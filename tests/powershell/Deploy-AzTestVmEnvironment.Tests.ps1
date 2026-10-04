<#
.SYNOPSIS
    Pester tests for Deploy-AzTestVmEnvironment.ps1

.DESCRIPTION
    Validates Deploy-AzTestVmEnvironment script and Bicep template including
    syntax, parameter validation, code quality, and template structure.
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\azure\Deploy-AzTestVmEnvironment.ps1"
    $bicepPath = Join-Path $PSScriptRoot "..\..\templates\azure\Deploy-AzTestVmEnvironment.bicep"
}

Describe "Deploy-AzTestVmEnvironment" {
    Context "Script Validation" {
        It "Should exist" {
            Test-Path $scriptPath | Should -Be $true
        }

        It "Should have valid PowerShell syntax" {
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $scriptPath -Raw), [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It "Should have help documentation" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
        }

        It "Should have a description" {
            $help = Get-Help $scriptPath
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It "Should have examples" {
            $help = Get-Help $scriptPath -Full
            $help.Examples | Should -Not -BeNullOrEmpty
        }

        It "Should follow naming conventions" {
            $scriptName = Split-Path $scriptPath -Leaf
            $scriptName | Should -Match '^[A-Z][a-z]+-Az[A-Z][a-zA-Z]+\.ps1$'
        }
    }

    Context "Parameter Validation" {
        It "Should have CmdletBinding attribute" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\[CmdletBinding'
        }

        It "Should use approved PowerShell verbs" {
            $scriptName = Split-Path $scriptPath -Leaf
            $verb = $scriptName -replace '-.*', ''
            $approvedVerbs = Get-Verb | Select-Object -ExpandProperty Verb
            $approvedVerbs | Should -Contain $verb
        }

        It "Should define ResourceGroupName parameter" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\$ResourceGroupName'
        }

        It "Should define Location parameter" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\$Location'
        }

        It "Should define LinuxVmCount parameter with validation" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\[ValidateRange\(0,\s*10\)\]'
            $content | Should -Match '\$LinuxVmCount'
        }

        It "Should define WindowsVmCount parameter with validation" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\$WindowsVmCount'
        }

        It "Should define AdminPassword as SecureString" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\[securestring\]\$AdminPassword'
        }

        It "Should define Teardown switch parameter" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\[switch\]\$Teardown'
        }

        It "Should define Validate switch parameter" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\[switch\]\$Validate'
        }

        It "Should have SupportsShouldProcess" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match 'SupportsShouldProcess'
        }
    }

    Context "Code Quality" {
        It "Should not contain hardcoded credentials" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Not -Match 'password\s*=\s*[''"][^P][^l]'
            $content | Should -Not -Match 'secret\s*=\s*[''"]'
        }

        It "Should use proper error handling" {
            $content = Get-Content $scriptPath -Raw
            ($content -match 'try\s*{' -or $content -match '\$ErrorActionPreference') |
                Should -Be $true
        }

        It "Should verify Azure connection before deploying" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match 'Get-AzContext'
        }

        It "Should auto-detect public IP" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match 'ifconfig\.me'
        }

        It "Should check for SSH key from environment variable" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match 'GIT_SIGNING_KEY_PUBLIC'
        }

        It "Should prompt before overwriting existing resource group" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match 'already exists'
        }

        It "Should reference the Bicep template file" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match 'Deploy-AzTestVmEnvironment\.bicep'
        }
    }

    Context "Bicep Template Validation" {
        It "Bicep template file should exist" {
            Test-Path $bicepPath | Should -Be $true
        }

        It "Bicep template should define location parameter" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "param location string"
        }

        It "Bicep template should define linuxVmCount parameter" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "param linuxVmCount int"
        }

        It "Bicep template should define windowsVmCount parameter" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "param windowsVmCount int"
        }

        It "Bicep template should define adminPassword as secure" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "@secure\(\)"
            $content | Should -Match "param adminPassword string"
        }

        It "Bicep template should define NSG resource" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "Microsoft.Network/networkSecurityGroups"
        }

        It "Bicep template should define VNet resource" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "Microsoft.Network/virtualNetworks"
        }

        It "Bicep template should define auto-shutdown schedules" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "Microsoft.DevTestLab/schedules"
        }

        It "Bicep template should define Automation Account" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "Microsoft.Automation/automationAccounts"
        }

        It "Bicep template should define role assignment for managed identity" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "Microsoft.Authorization/roleAssignments"
        }

        It "Bicep template should include SSH NSG rule" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "Allow-SSH-Deployer"
        }

        It "Bicep template should include RDP NSG rule" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "Allow-RDP-Deployer"
        }

        It "Bicep template should include custom ports NSG rule" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "3000-9999"
        }

        It "Bicep template should use cloud-init for Linux" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "customData"
            $content | Should -Match "cloud-init"
        }

        It "Bicep template should use CustomScriptExtension for Windows" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "CustomScriptExtension"
        }

        It "Bicep template should output connection info" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "output linuxPublicIps"
            $content | Should -Match "output windowsPublicIps"
            $content | Should -Match "output linuxSshCommands"
            $content | Should -Match "output windowsRdpCommands"
        }

        It "Bicep template should install Node.js on Linux" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "nodesource.*setup_"
        }

        It "Bicep template should install Node.js on Windows" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "nodejs\.org"
        }

        It "Bicep template should parameterize Node.js installation" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "param installNodeJs bool"
            $content | Should -Match "param nodeVersion string"
        }

        It "Bicep template should conditionally install Node.js" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "installNodeJs"
            $content | Should -Match "linuxCloudInitWithNode"
            $content | Should -Match "linuxCloudInitNoNode"
        }

        It "Bicep template should parameterize Linux OS image" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "param linuxOsOffer string"
            $content | Should -Match "param linuxOsSku string"
        }

        It "Bicep template should support multiple Linux distros" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "ubuntu-24_04-lts"
            $content | Should -Match "debian-12"
            $content | Should -Match "RHEL"
        }

        It "Bicep template should define idle shutdown runbook" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "Stop-IdleTestVMs"
            $content | Should -Match "idleShutdownRunbookContent"
        }

        It "Bicep template should parameterize idle CPU threshold" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "param idleCpuThresholdPercent int"
            $content | Should -Match "param idleTimeoutMinutes int"
        }

        It "Bicep template idle runbook should check CPU metrics" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "Percentage CPU"
            $content | Should -Match "Get-AzMetric"
        }

        It "Bicep template should conditionally deploy idle resources" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "if \(idleCpuThresholdPercent > 0\)"
        }

        It "Bicep template should assign Monitoring Reader role for idle runbook" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "Monitoring Reader"
        }
    }

    Context "Pen-Test Features" {
        It "Bicep template should have enablePenTest parameter" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "param enablePenTest bool"
        }

        It "Bicep template should have attackerVmCount parameter" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "param attackerVmCount int"
        }

        It "Bicep template should add dashboard VNet-only NSG rule" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "Allow-Dashboard-VNet"
            $content | Should -Match "8787"
            $content | Should -Match "VirtualNetwork"
        }

        It "Bicep template should conditionally add pen-test NSG rules" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "Allow-Dashboard-Deployer-PenTest"
            $content | Should -Match "Allow-HTTPS-Deployer-PenTest"
            $content | Should -Match "enablePenTest"
        }

        It "Bicep template should define attacker VM resources conditionally" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "vm-attacker-"
            $content | Should -Match "enablePenTest \? attackerVmCount"
        }

        It "Bicep template attacker VM should install security tools" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "nmap"
            $content | Should -Match "nikto"
            $content | Should -Match "zap"
            $content | Should -Match "certbot"
        }

        It "Bicep template should output attacker VM info" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "output attackerVmNames"
            $content | Should -Match "output attackerPublicIps"
            $content | Should -Match "output attackerSshCommands"
        }

        It "Bicep template should tag attacker VMs with pen-test role" {
            $content = Get-Content $bicepPath -Raw
            $content | Should -Match "pen-test-attacker"
        }

        It "Deploy script should have EnablePenTest parameter" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\[switch\]\$EnablePenTest'
        }

        It "Deploy script should have AttackerVmCount parameter" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\$AttackerVmCount'
        }

        It "Deploy script should output attacker VM connection info" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match "Attacker VMs.*Pen-Test"
        }
    }
}
