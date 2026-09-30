<#
.SYNOPSIS
    Pester tests for Publish-ToPublicRepo.ps1
.NOTES
    Author: jagilber-org
    Requires: Pester 5.x+
#>

BeforeAll {
    $script:scriptPath = Join-Path $PSScriptRoot '..\..\powershell\automation\Publish-ToPublicRepo.ps1'
}

Describe 'Script Validation' {
    Context 'File existence' {
        It 'Should exist at powershell/automation/Publish-ToPublicRepo.ps1' {
            Test-Path $script:scriptPath | Should -Be $true
        }
    }

    Context 'PowerShell syntax' {
        It 'Should have no parse errors' {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:scriptPath, [ref]$null, [ref]$errors
            )
            $errors.Count | Should -Be 0
        }
    }
}

Describe 'Parameter definitions' {
    BeforeAll {
        $script:content = Get-Content $script:scriptPath -Raw
    }

    It 'Should declare a [string] $Tag parameter' {
        $script:content | Should -Match '(?i)\[string\]\s*\$Tag'
    }

    It 'Should declare a [switch] $DryRun parameter' {
        $script:content | Should -Match '(?i)\[switch\]\s*\$DryRun'
    }

    It 'Should declare a [switch] $Force parameter' {
        $script:content | Should -Match '(?i)\[switch\]\s*\$Force'
    }

    It 'Should declare a [string] $RemoteUrl parameter' {
        $script:content | Should -Match '(?i)\[string\]\s*\$RemoteUrl'
    }

    It 'Should declare a [switch] $DirectPublish parameter' {
        $script:content | Should -Match '(?i)\[switch\]\s*\$DirectPublish'
    }

    It 'Should declare a [switch] $CreateReviewRepo parameter' {
        $script:content | Should -Match '(?i)\[switch\]\s*\$CreateReviewRepo'
    }

    It 'Should declare a [string] $LocalPath parameter' {
        $script:content | Should -Match '(?i)\[string\]\s*\$LocalPath'
    }
}

Describe 'Script content requirements' {
    BeforeAll {
        $script:content = Get-Content $script:scriptPath -Raw
    }

    It 'Should reference .publish-exclude' {
        $script:content | Should -Match '\.publish-exclude'
    }

    It 'Should include leaked artifact verification' {
        $script:content | Should -Match '(?i)(leaked|forbidden|verify)'
    }

    It 'Should stage only committed files' {
        $script:content | Should -Match 'git\s+-C\s+\$repoRoot\s+archive\s+--format=zip[\s\S]+?HEAD'
        $script:content | Should -Not -Match '(?m)^\s*\$robocopyArgs\s*='
    }

    It 'Should reject files exceeding the GitHub size limit' {
        $script:content | Should -Match '\$_\.Length\s+-gt\s+100MB'
    }

    It 'Should fail instead of reporting success when git push fails' {
        $script:content | Should -Match 'git push public HEAD:main --force[\s\S]+?\$LASTEXITCODE\s+-ne\s+0[\s\S]+?throw'
    }

    It 'Should use $ErrorActionPreference = ''Stop''' {
        $script:content | Should -Match '(?i)\$ErrorActionPreference\s*=\s*[''"]Stop[''"]'
    }

    It 'Should calculate $repoRoot from script location' {
        $script:content | Should -Match '(?i)\$repoRoot'
    }

    It 'Should support [CmdletBinding(SupportsShouldProcess)]' {
        $script:content | Should -Match 'SupportsShouldProcess'
    }

    It 'Should include comment-based help with .SYNOPSIS' {
        $script:content | Should -Match '\.SYNOPSIS'
    }

    It 'Should include .EXAMPLE in comment-based help' {
        $script:content | Should -Match '\.EXAMPLE'
    }
}

Describe 'DryRun behaviour' {
    It 'Script file is a non-function script (top-level logic)' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:scriptPath, [ref]$null, [ref]$null
        )
        # The script should have a param block at the top level
        $paramBlock = $ast.ParamBlock
        $paramBlock | Should -Not -BeNullOrEmpty
    }
}
