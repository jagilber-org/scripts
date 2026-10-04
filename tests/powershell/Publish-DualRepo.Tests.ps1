<#
.SYNOPSIS
    Pester tests for Publish-DualRepo.ps1
.NOTES
    Author: jagilber-org
    Requires: Pester 5.x+
#>

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\..\powershell\automation\Publish-DualRepo.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
    $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($func in $functions) {
        Invoke-Expression $func.Extent.Text
    }
}

Describe 'Get-ExcludeList' {
    BeforeAll {
        $script:testDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-publish-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
    }
    AfterAll {
        Remove-Item -Path $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should parse exclusion entries and skip comments' {
        $excludeFile = Join-Path $script:testDir 'test-exclude'
        "# comment`n.specify/`ninstructions/`n`n# another`nbuild-output.txt`n.test-run-complete.*" | Set-Content -Path $excludeFile
        $result = Get-ExcludeList -Path $excludeFile
        $result.Count | Should -Be 4
        $result | Should -Contain '.specify/'
        $result | Should -Contain 'instructions/'
        $result | Should -Contain 'build-output.txt'
        $result | Should -Contain '.test-run-complete.*'
    }

    It 'Should skip blank lines' {
        $excludeFile = Join-Path $script:testDir 'test-exclude-blanks'
        ".specify/`n`ninstructions/`n`n`nbuild-output.txt" | Set-Content -Path $excludeFile
        $result = Get-ExcludeList -Path $excludeFile
        $result.Count | Should -Be 3
    }
}

Describe 'Test-Excluded' {
    It 'Should match directory exclusion (trailing /)' {
        $excludes = @('instructions/', '.private/')
        Test-Excluded -RelativePath 'instructions/foo.json' -ExcludePaths $excludes | Should -Be $true
        Test-Excluded -RelativePath '.private/secrets.txt' -ExcludePaths $excludes | Should -Be $true
        Test-Excluded -RelativePath 'src/index.ts' -ExcludePaths $excludes | Should -Be $false
    }

    It 'Should match exact file exclusion' {
        $excludes = @('build-output.txt', '.secrets.baseline')
        Test-Excluded -RelativePath 'build-output.txt' -ExcludePaths $excludes | Should -Be $true
        Test-Excluded -RelativePath '.secrets.baseline' -ExcludePaths $excludes | Should -Be $true
        Test-Excluded -RelativePath 'src/build-output.txt' -ExcludePaths $excludes | Should -Be $false
    }

    It 'Should match prefix glob exclusion (trailing *)' {
        $excludes = @('.test-run-complete.*')
        Test-Excluded -RelativePath '.test-run-complete.12345.marker' -ExcludePaths $excludes | Should -Be $true
        Test-Excluded -RelativePath '.test-run-complete.json' -ExcludePaths $excludes | Should -Be $true
        Test-Excluded -RelativePath 'test-run-complete.txt' -ExcludePaths $excludes | Should -Be $false
    }

    It 'Should normalize backslashes to forward slashes' {
        $excludes = @('docs/archive/')
        Test-Excluded -RelativePath 'docs\archive\report.md' -ExcludePaths $excludes | Should -Be $true
    }

    It 'Should not match non-excluded paths' {
        $excludes = @('.specify/', 'instructions/', 'build-output.txt')
        Test-Excluded -RelativePath 'src/index.ts' -ExcludePaths $excludes | Should -Be $false
        Test-Excluded -RelativePath 'package.json' -ExcludePaths $excludes | Should -Be $false
        Test-Excluded -RelativePath 'README.md' -ExcludePaths $excludes | Should -Be $false
    }
}

Describe 'Test-LeakedArtifacts' {
    BeforeAll {
        $script:testDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-leak-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
    }
    AfterAll {
        Remove-Item -Path $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should return empty when no forbidden items exist' {
        $result = Test-LeakedArtifacts -Directory $script:testDir -Forbidden @('.specify', 'instructions')
        @($result).Count | Should -Be 0
    }

    It 'Should detect forbidden directories' {
        $forbidden = Join-Path $script:testDir '.specify'
        New-Item -ItemType Directory -Path $forbidden -Force | Out-Null
        $result = Test-LeakedArtifacts -Directory $script:testDir -Forbidden @('.specify', 'instructions')
        $result | Should -Contain '.specify'
        Remove-Item -Path $forbidden -Recurse -Force
    }

    It 'Should detect forbidden files' {
        $forbidden = Join-Path $script:testDir '.secrets.baseline'
        Set-Content -Path $forbidden -Value 'test'
        $result = Test-LeakedArtifacts -Directory $script:testDir -Forbidden @('.secrets.baseline')
        $result | Should -Contain '.secrets.baseline'
        Remove-Item -Path $forbidden -Force
    }
}

Describe 'Copy-RepoContent' {
    BeforeAll {
        $script:srcDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-src-$(Get-Random)"
        $script:destDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-dest-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:srcDir -Force | Out-Null
        New-Item -ItemType Directory -Path $script:destDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:srcDir '.git') -Force | Out-Null
        Set-Content -Path (Join-Path $script:srcDir '.git\HEAD') -Value 'ref: refs/heads/main'
        New-Item -ItemType Directory -Path (Join-Path $script:srcDir 'src') -Force | Out-Null
        Set-Content -Path (Join-Path $script:srcDir 'src\index.ts') -Value 'console.log("hello")'
        Set-Content -Path (Join-Path $script:srcDir 'package.json') -Value '{}'
        Set-Content -Path (Join-Path $script:srcDir 'build-output.txt') -Value 'build log'
        New-Item -ItemType Directory -Path (Join-Path $script:srcDir 'instructions') -Force | Out-Null
        Set-Content -Path (Join-Path $script:srcDir 'instructions\secret.json') -Value '{}'
    }
    AfterAll {
        Remove-Item -Path $script:srcDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $script:destDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Should copy non-excluded files and skip .git' {
        $excludes = @('build-output.txt', 'instructions/')
        Copy-RepoContent -Source $script:srcDir -Destination $script:destDir -Root $script:srcDir -ExcludePaths $excludes
        Test-Path (Join-Path $script:destDir 'package.json') | Should -Be $true
        Test-Path (Join-Path $script:destDir 'src\index.ts') | Should -Be $true
        Test-Path (Join-Path $script:destDir '.git') | Should -Be $false
        Test-Path (Join-Path $script:destDir 'build-output.txt') | Should -Be $false
        Test-Path (Join-Path $script:destDir 'instructions') | Should -Be $false
    }
}
