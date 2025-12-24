# PowerShell Script Testing Guide

## Overview

All PowerShell scripts in this repository should have corresponding Pester tests. This ensures reliability, maintainability, and consistent behavior across updates.

## Testing Framework

We use **Pester v5+** for all PowerShell testing.

### Installation

```powershell
Install-Module -Name Pester -Force -SkipPublisherCheck
Import-Module Pester
```

### Running Tests

```powershell
# Run all tests
Invoke-Pester -Path .\tests\powershell

# Run specific test file
Invoke-Pester -Path .\tests\powershell\Get-AzVmImage.Tests.ps1

# Run with code coverage
Invoke-Pester -Path .\tests\powershell -CodeCoverage .\powershell\**\*.ps1

# Run tests for specific category
Invoke-Pester -Path .\tests\powershell\azure.Tests.ps1
```

## Test Structure

### File Naming Convention

Test files follow the pattern: `{ScriptName}.Tests.ps1`

Examples:
- `powershell/azure/Manage-AzKeyVault.ps1` → `tests/powershell/Manage-AzKeyVault.Tests.ps1`
- `powershell/diagnostics/Watch-Process.ps1` → `tests/powershell/Watch-Process.Tests.ps1`

### Test Organization

```powershell
Describe "ScriptName" {
    Context "Script Validation" {
        # Syntax, existence, help tests
    }
    
    Context "Parameter Validation" {
        # Parameter tests
    }
    
    Context "Functionality Tests" {
        # Core functionality tests
    }
    
    Context "Error Handling" {
        # Error scenario tests
    }
}
```

## Test Categories

### 1. Script Validation Tests (Required for all scripts)

```powershell
It "Should exist" {
    Test-Path $scriptPath | Should -Be $true
}

It "Should have valid PowerShell syntax" {
    $errors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize(
        (Get-Content $scriptPath -Raw), [ref]$errors)
    $errors.Count | Should -Be 0
}

It "Should have a synopsis" {
    $help = Get-Help $scriptPath
    $help.Synopsis | Should -Not -BeNullOrEmpty
}

It "Should have a description" {
    $help = Get-Help $scriptPath
    $help.Description | Should -Not -BeNullOrEmpty
}
```

### 2. Parameter Validation Tests

```powershell
It "Should have required parameters" {
    $params = (Get-Command $scriptPath).Parameters
    $params.Keys | Should -Contain 'ParameterName'
}

It "Should validate parameter types" {
    $param = (Get-Command $scriptPath).Parameters['ParameterName']
    $param.ParameterType.Name | Should -Be 'String'
}

It "Should have mandatory parameters marked" {
    $param = (Get-Command $scriptPath).Parameters['ParameterName']
    $param.Attributes.Mandatory | Should -Contain $true
}
```

### 3. Functionality Tests

```powershell
It "Should execute without errors with valid input" {
    { & $scriptPath -Parameter "ValidValue" } | Should -Not -Throw
}

It "Should return expected output type" {
    $result = & $scriptPath -Parameter "ValidValue"
    $result | Should -BeOfType [PSCustomObject]
}

It "Should handle pipeline input" {
    $input = "test"
    { $input | & $scriptPath } | Should -Not -Throw
}
```

### 4. Error Handling Tests

```powershell
It "Should throw on missing required parameter" {
    { & $scriptPath } | Should -Throw
}

It "Should validate parameter format" {
    { & $scriptPath -Email "invalid" } | Should -Throw "*valid email*"
}

It "Should handle non-existent resources gracefully" {
    $result = & $scriptPath -ResourceId "nonexistent"
    $result.Success | Should -Be $false
}
```

### 5. Integration Tests (Optional)

For scripts requiring external resources (Azure, Kusto, etc.):

```powershell
It "Should connect to Azure" -Tag 'Integration' {
    $result = & $scriptPath -SubscriptionId $testSubscriptionId
    $result | Should -Not -BeNullOrEmpty
}
```

Run integration tests separately:
```powershell
Invoke-Pester -Path .\tests\powershell -Tag 'Integration'
```

## Mocking External Dependencies

For scripts with external dependencies:

```powershell
BeforeAll {
    Mock Invoke-RestMethod {
        return @{ status = "success"; data = @() }
    }
    
    Mock Get-AzResource {
        return @{ Name = "TestResource"; Id = "/subscriptions/test" }
    }
}
```

## Test Template

See `tests/powershell/ScriptTemplate.Tests.ps1` for a complete template.

## Testing Best Practices

### 1. Test Independence
- Each test should be independent
- Use `BeforeEach` to set up test state
- Use `AfterEach` to clean up

### 2. Descriptive Test Names
```powershell
# Good
It "Should return error when subscription ID is invalid"

# Bad
It "Test 1"
```

### 3. Arrange-Act-Assert Pattern
```powershell
It "Should filter results by date" {
    # Arrange
    $startDate = Get-Date
    $endDate = $startDate.AddDays(7)
    
    # Act
    $result = & $scriptPath -StartDate $startDate -EndDate $endDate
    
    # Assert
    $result.Count | Should -BeGreaterThan 0
    $result[0].Date | Should -BeGreaterOrEqual $startDate
}
```

### 4. Use Should Assertions
```powershell
# Available assertions:
Should -Be $expected
Should -Not -Be $value
Should -BeNullOrEmpty
Should -BeOfType [type]
Should -Match "pattern"
Should -Contain $item
Should -BeGreaterThan $value
Should -BeLessThan $value
Should -Throw
```

### 5. Skip Tests Requiring External Resources Locally
```powershell
It "Should deploy to Azure" -Skip:(!$env:AZURE_SUBSCRIPTION_ID) {
    # Test code
}
```

## Code Coverage

Aim for minimum 70% code coverage:

```powershell
$config = New-PesterConfiguration
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = '.\powershell\**\*.ps1'
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath = '.\coverage.xml'

Invoke-Pester -Configuration $config
```

## CI/CD Integration

Tests are automatically run on:
- Pull requests
- Commits to master
- Pre-commit hooks (optional - fast tests only)

See `.github/workflows/test.yml` for CI configuration.

## Examples by Category

### Azure Script Test Example

```powershell
Describe "Get-AzVmImage" {
    Context "Script Validation" {
        It "Should have valid syntax" {
            $scriptPath = "..\..\powershell\azure\Get-AzVmImage.ps1"
            $errors = $null
            [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $scriptPath -Raw), [ref]$errors)
            $errors.Count | Should -Be 0
        }
    }

    Context "Parameter Validation" {
        It "Should accept Location parameter" {
            $params = (Get-Command "..\..\powershell\azure\Get-AzVmImage.ps1").Parameters
            $params.Keys | Should -Contain 'Location'
        }
    }
}
```

### Utility Script Test Example

```powershell
Describe "Search-FileContent" {
    BeforeAll {
        $testFile = New-TemporaryFile
        "test line 1`ntest line 2`nmatch this line" | Out-File $testFile
    }

    AfterAll {
        Remove-Item $testFile -Force
    }

    It "Should find matching lines" {
        $result = & "..\..\powershell\utilities\Search-FileContent.ps1" `
            -Path $testFile -Pattern "match"
        $result | Should -Contain "match this line"
    }
}
```

## Troubleshooting

### Common Issues

**Issue**: Test can't find script
```powershell
# Solution: Use Join-Path with $PSScriptRoot
$scriptPath = Join-Path $PSScriptRoot "..\..\powershell\azure\ScriptName.ps1"
```

**Issue**: Module import conflicts
```powershell
# Solution: Use -Force on Import-Module
Import-Module $modulePath -Force
```

**Issue**: Tests fail in CI but pass locally
```powershell
# Solution: Check for environment-specific assumptions
# Use Skip for tests requiring specific environments
It "Should work" -Skip:(!$IsWindows) { }
```

## Writing Your First Test

1. Copy `tests/powershell/ScriptTemplate.Tests.ps1`
2. Rename to `{YourScript}.Tests.ps1`
3. Update script path in BeforeAll
4. Customize test cases
5. Run: `Invoke-Pester -Path .\tests\powershell\YourScript.Tests.ps1`
6. Iterate until all tests pass

## Resources

- [Pester Documentation](https://pester.dev/)
- [PowerShell Testing Best Practices](https://learn.microsoft.com/en-us/powershell/scripting/dev-cross-plat/vscode/using-vscode-for-debugging)
- Template: `tests/powershell/ScriptTemplate.Tests.ps1`
