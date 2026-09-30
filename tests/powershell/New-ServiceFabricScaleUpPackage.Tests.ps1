<#
.SYNOPSIS
    Pester tests for New-ServiceFabricScaleUpPackage.ps1.

.DESCRIPTION
    Validates script syntax, comment-based help, and the parameter contract for the
    Service Fabric primary node type scale-up package generator, then loads the
    comprehensive deterministic package-generation suite colocated with the script.

.NOTES
    Run tests: Invoke-Pester -Path .\tests\powershell\New-ServiceFabricScaleUpPackage.Tests.ps1
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\service-fabric\scale-up-package\New-ServiceFabricScaleUpPackage.ps1"

    if (-not (Test-Path $scriptPath)) {
        throw "Script not found: $scriptPath"
    }
}

Describe "New-ServiceFabricScaleUpPackage" {
    Context "Script Validation" {
        It "Should exist" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\service-fabric\scale-up-package\New-ServiceFabricScaleUpPackage.ps1"
            Test-Path $scriptPath | Should -Be $true
        }

        It "Should have valid PowerShell syntax" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\service-fabric\scale-up-package\New-ServiceFabricScaleUpPackage.ps1"
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $scriptPath -Raw), [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It "Should have a synopsis" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\service-fabric\scale-up-package\New-ServiceFabricScaleUpPackage.ps1"
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
        }

        It "Should have a description" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\service-fabric\scale-up-package\New-ServiceFabricScaleUpPackage.ps1"
            $help = Get-Help $scriptPath
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It "Should declare CmdletBinding" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\service-fabric\scale-up-package\New-ServiceFabricScaleUpPackage.ps1"
            (Get-Content $scriptPath -Raw) | Should -Match '\[CmdletBinding\('
        }
    }

    Context "Parameter Validation" {
        It "Should define required parameter <_>" -ForEach @('ResourceGroupName', 'ReplacementVmssName', 'TargetVmSku', 'OutputPath') {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\service-fabric\scale-up-package\New-ServiceFabricScaleUpPackage.ps1"
            (Get-Command $scriptPath).PSObject.Properties['Parameters'].Value.Keys | Should -Contain $_
        }

        It "Should constrain ReplacementVmssName to 9 characters (Service Fabric limit)" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\service-fabric\scale-up-package\New-ServiceFabricScaleUpPackage.ps1"
            $attr = (Get-Command $scriptPath).PSObject.Properties['Parameters'].Value['ReplacementVmssName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateLengthAttribute] }
            $attr | Should -Not -BeNullOrEmpty
            $attr.MaxLength | Should -Be 9
        }

        It "Should accept AdminPassword as SecureString" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\service-fabric\scale-up-package\New-ServiceFabricScaleUpPackage.ps1"
            (Get-Command $scriptPath).PSObject.Properties['Parameters'].Value['AdminPassword'].ParameterType |
                Should -Be ([securestring])
        }

        It "Should support ShouldProcess (WhatIf)" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\service-fabric\scale-up-package\New-ServiceFabricScaleUpPackage.ps1"
            (Get-Command $scriptPath).PSObject.Properties['Parameters'].Value.Keys | Should -Contain 'WhatIf'
        }
    }

    Context "Version Contract" {
        It "Should declare version 2.1.1 in the help block" {
            $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\service-fabric\scale-up-package\New-ServiceFabricScaleUpPackage.ps1"
            (Get-Content $scriptPath -Raw) | Should -Match 'Version\s*:\s*2\.1\.1'
        }
    }
}

. (Join-Path $PSScriptRoot '..\..\powershell\service-fabric\scale-up-package\New-ServiceFabricScaleUpPackage.Tests.ps1')
