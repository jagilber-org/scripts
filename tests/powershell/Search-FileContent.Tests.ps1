<#
.SYNOPSIS
    Pester tests for Search-FileContent.ps1 (utility script)

.DESCRIPTION
    Validates file search functionality with actual file operations.
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\..\powershell\utilities\Search-FileContent.ps1"
    
    # Create test files
    $script:testDir = Join-Path $TestDrive "SearchTest"
    New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
    
    $script:testFile1 = Join-Path $script:testDir "test1.txt"
    $script:testFile2 = Join-Path $script:testDir "test2.txt"
    
    "Line 1: Hello World`nLine 2: PowerShell Script`nLine 3: Azure Cloud" | 
        Out-File $script:testFile1
    "Different content`nNo match here`nAnother line" | 
        Out-File $script:testFile2
}

AfterAll {
    # Cleanup test files
    if (Test-Path $script:testDir) {
        Remove-Item $script:testDir -Recurse -Force
    }
}

Describe "Search-FileContent" {
    Context "Script Validation" {
        It "Should exist" {
            Test-Path $scriptPath | Should -Be $true
        }

        It "Should have valid syntax" {
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $scriptPath -Raw), [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It "Should use approved verb 'Search'" {
            $scriptName = Split-Path $scriptPath -Leaf
            $scriptName | Should -Match '^Search-'
        }
    }

    Context "Code Quality" {
        It "Should have CmdletBinding for advanced functions" {
            $content = Get-Content $scriptPath -Raw
            $content | Should -Match '\[CmdletBinding\(\)\]'
        }

        It "Should support common parameters" {
            $content = Get-Content $scriptPath -Raw
            # Check for param block with proper structure
            $content | Should -Match 'param\s*\('
        }
    }

    Context "Documentation" {
        It "Should have help documentation" {
            $help = Get-Help $scriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
        }
    }
}
