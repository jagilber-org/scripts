<#
.SYNOPSIS
    Pester tests for Invoke-WslContainer.ps1 (combined WslcObj object model).

.DESCRIPTION
    Validates script existence, syntax, comment-based help, and that the WslcObj
    class exposes the expected dot-callable methods.
#>

BeforeAll {
    $script:scriptPath = Join-Path $PSScriptRoot "..\..\powershell\wslc\Invoke-WslContainer.ps1"
}

Describe "Invoke-WslContainer" {
    Context "Script Validation" {
        It "Should exist" {
            Test-Path $script:scriptPath | Should -Be $true
        }

        It "Should have valid PowerShell syntax" {
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $script:scriptPath -Raw), [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It "Should have a synopsis" {
            (Get-Help $script:scriptPath).Synopsis | Should -Not -BeNullOrEmpty
        }

        It "Should have a description" {
            (Get-Help $script:scriptPath).Description | Should -Not -BeNullOrEmpty
        }
    }

    Context "Parameter Validation" {
        It "Should expose a WslcPath parameter" {
            (Get-Command $script:scriptPath).Parameters.Keys | Should -Contain 'WslcPath'
        }
    }

    Context "WslcObj Object Model" {
        It "Should define the WslcObj class" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match 'class WslcObj'
        }

        It "Should create the global `$wslcObj object" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match '\$global:wslcObj\s*=\s*\[WslcObj\]::new'
        }

        It "Should expose the expected dot-callable methods" {
            $content = Get-Content $script:scriptPath -Raw
            foreach ($method in @('Prerequisites', 'GetContainers', 'GetImages', 'GetStats', 'Run', 'Exec', 'Start', 'Stop', 'Restart', 'Remove', 'Logs', 'Inspect', 'ImageInspect', 'Prune', 'IsReady', 'Help')) {
                $content | Should -Match "\]\s*$method\("
            }
        }

        It "Should provide image enrichment helpers and a details overload" {
            $content = Get-Content $script:scriptPath -Raw
            $content | Should -Match '\]\s*FormatSize\('
            $content | Should -Match '\]\s*GetImageDetailsMap\('
            $content | Should -Match '\[object\[\]\]\s*GetImages\(\[bool\]\$includeDetails\)'
        }
    }
}
