<#
.SYNOPSIS
    Pester tests for Update-OrgProfileReadme.ps1.

.DESCRIPTION
    Dot-sources the script to load its helper functions without running the update,
    then exercises the Markdown extraction and rendering logic against fixture
    README content. No network access: every test is offline and deterministic.

.NOTES
    Run: Invoke-Pester -Path .\tests\powershell\Update-OrgProfileReadme.Tests.ps1
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\..\powershell\automation\Update-OrgProfileReadme.ps1'

    if (-not (Test-Path $script:ScriptPath)) {
        throw "Script not found: $script:ScriptPath"
    }

    # Dot-sourcing loads the helpers; the script's main body is guarded against it.
    . $script:ScriptPath

    $script:Tick = [string][char]0x60
    $script:F = $script:Tick * 3
}

Describe 'Update-OrgProfileReadme' {

    Context 'Script Validation' {

        It 'Should exist' {
            Test-Path $script:ScriptPath | Should -Be $true
        }

        It 'Should have valid PowerShell syntax' {
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $script:ScriptPath -Raw), [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It 'Should have a synopsis' {
            (Get-Help $script:ScriptPath).Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'Should have a description' {
            (Get-Help $script:ScriptPath).Description | Should -Not -BeNullOrEmpty
        }

        It 'Should have at least one example' {
            @((Get-Help $script:ScriptPath).Examples.Example).Count | Should -BeGreaterThan 0
        }

        It 'Should not run its main body when dot-sourced' {
            # Proven by the fact that BeforeAll dot-sourced it without -Org and did not throw.
            Get-Command ConvertTo-OrgProfileMarkdown -CommandType Function | Should -Not -BeNullOrEmpty
        }
    }

    Context 'ConvertTo-PlainText' {

        It 'Unwraps an inline link to its text' {
            ConvertTo-PlainText 'See the [Model Context Protocol](https://example.com) spec.' |
                Should -Be 'See the Model Context Protocol spec.'
        }

        It 'Strips a row of reference-style badges' {
            ConvertTo-PlainText '[![Run Tests][tests-badge]][tests-workflow] [![Lint][lint-badge]][lint-workflow]' |
                Should -BeNullOrEmpty
        }

        It 'Strips inline images' {
            ConvertTo-PlainText '![CI](https://example.com/badge.svg) Build tooling.' |
                Should -Be 'Build tooling.'
        }

        It 'Removes bold and code markers' {
            ConvertTo-PlainText "**Primary capability:** runs $($script:Tick)npm build$($script:Tick)." |
                Should -Be 'Primary capability: runs npm build.'
        }
    }

    Context 'Format-PathReference' {

        It 'Reduces an absolute Windows path to its final segment' {
            Format-PathReference 'built on the template in C:\github\owner\template-repo.' |
                Should -Be 'built on the template in template-repo.'
        }

        It 'Leaves URLs untouched' {
            $url = 'clone https://github.com/owner/repo.git now'
            Format-PathReference $url | Should -Be $url
        }
    }

    Context 'Test-UsableSummary' {

        It 'Accepts an ordinary sentence' {
            Test-UsableSummary 'A local browser interface and JSON API for investigating SQLite databases.' |
                Should -Be $true
        }

        It 'Rejects text shorter than 40 characters' {
            Test-UsableSummary 'Index Server' | Should -Be $false
        }

        It 'Rejects a dangling lead-in to a list' {
            Test-UsableSummary 'The project combines three scan surfaces into one repeatable run:' |
                Should -Be $false
        }

        It 'Rejects license boilerplate' {
            Test-UsableSummary 'This project is licensed under the MIT License - see the LICENSE file for details.' |
                Should -Be $false
        }

        It 'Rejects text still carrying an absolute path' {
            Test-UsableSummary 'A scanning tool built on the template in C:\github\owner\template-repo today.' |
                Should -Be $false
        }

        It 'Rejects empty and null input' {
            Test-UsableSummary '' | Should -Be $false
            Test-UsableSummary $null | Should -Be $false
        }
    }

    Context 'Get-ReadmeSummary' {

        It 'Returns the first paragraph under the title' {
            $readme = @(
                '# widget-tool',
                '',
                'A command-line tool for inspecting widget manifests and reporting drift.',
                '',
                '## Install'
            )
            Get-ReadmeSummary -Line $readme |
                Should -Be 'A command-line tool for inspecting widget manifests and reporting drift.'
        }

        It 'Skips badges and blockquote notices above the description' {
            $readme = @(
                '# widget-tool',
                '',
                '> **Portfolio Project** | [Specs](docs/specs/)',
                '',
                '![CI](https://example.com/ci.svg)',
                '',
                'A command-line tool for inspecting widget manifests and reporting drift.',
                '',
                '## Install'
            )
            Get-ReadmeSummary -Line $readme |
                Should -Be 'A command-line tool for inspecting widget manifests and reporting drift.'
        }

        It 'Prefers an explicit Project Overview section' {
            $readme = @(
                '# widget-tool',
                '',
                '## Security Notice',
                '',
                'This repository follows the org security standards and gates every commit.',
                '',
                '## Project Overview',
                '',
                'A secure server for cross-file consistency and obfuscation of manifests.',
                '',
                '## Install'
            )
            Get-ReadmeSummary -Line $readme |
                Should -Be 'A secure server for cross-file consistency and obfuscation of manifests.'
        }

        It 'Does not wander out of an overview section into the License section' {
            # Regression: an unbounded scan reported "This project is licensed under..."
            # as the summary for a repo whose Overview held only a diagram.
            $readme = @(
                '# widget-tool',
                '',
                'An MCP server for exporting and importing widget dashboards via automation.',
                '',
                '## Architecture',
                '',
                '### Quick Overview',
                '',
                "$($script:F)text",
                'client -> server',
                $script:F,
                '',
                '## License',
                '',
                'This project is licensed under the MIT License - see the LICENSE file for details.'
            )
            Get-ReadmeSummary -Line $readme |
                Should -Be 'An MCP server for exporting and importing widget dashboards via automation.'
        }

        It 'Ignores a leading fenced code block' {
            $readme = @(
                '# widget-tool',
                '',
                "$($script:F)bash",
                'npm install',
                $script:F,
                '',
                'A command-line tool for inspecting widget manifests and reporting drift.'
            )
            Get-ReadmeSummary -Line $readme |
                Should -Be 'A command-line tool for inspecting widget manifests and reporting drift.'
        }

        It 'Returns null for a README with no usable prose' {
            Get-ReadmeSummary -Line @('# widget-tool', '', '- bullet one', '- bullet two') |
                Should -BeNullOrEmpty
        }

        It 'Returns null for empty input' {
            Get-ReadmeSummary -Line @() | Should -BeNullOrEmpty
        }
    }

    Context 'Get-ReadmeQuickStart' {

        It 'Returns a shell block from the Install section' {
            $readme = @(
                '# widget-tool',
                '## Install',
                "$($script:F)bash",
                'npm install',
                'npm run build',
                $script:F
            )
            $qs = Get-ReadmeQuickStart -Line $readme
            $qs.Lang | Should -Be 'bash'
            $qs.Body | Should -Be "npm install`nnpm run build"
        }

        It 'Prefers an Install block over a Usage block' {
            $readme = @(
                '# widget-tool',
                '## Usage',
                "$($script:F)bash",
                'widget scan',
                $script:F,
                '## Install',
                "$($script:F)bash",
                'npm install',
                $script:F
            )
            (Get-ReadmeQuickStart -Line $readme).Body | Should -Be 'npm install'
        }

        It 'Ignores blocks outside install and usage sections' {
            $readme = @(
                '# widget-tool',
                '## Architecture',
                "$($script:F)bash",
                'not-a-quick-start',
                $script:F
            )
            Get-ReadmeQuickStart -Line $readme | Should -BeNullOrEmpty
        }

        It 'Rejects a block containing an absolute local path' {
            $readme = @(
                '# widget-tool',
                '## Install',
                "$($script:F)bash",
                'node C:/github/owner/widget-tool/dist/server.js',
                $script:F
            )
            Get-ReadmeQuickStart -Line $readme | Should -BeNullOrEmpty
        }

        It 'Rejects a block containing a secret-shaped token' {
            $readme = @(
                '# widget-tool',
                '## Install',
                "$($script:F)bash",
                'export KEY=sk-ant-abc123',
                $script:F
            )
            Get-ReadmeQuickStart -Line $readme | Should -BeNullOrEmpty
        }

        It 'Keeps a block whose command contains an https URL' {
            # Regression: an over-broad path guard matched the "s:/" in "https://".
            $readme = @(
                '# widget-tool',
                '## Install',
                "$($script:F)bash",
                'git clone https://github.com/owner/widget-tool.git',
                $script:F
            )
            (Get-ReadmeQuickStart -Line $readme).Body |
                Should -Be 'git clone https://github.com/owner/widget-tool.git'
        }

        It 'Rejects a block longer than ten lines' {
            $readme = @('# widget-tool', '## Install', "$($script:F)bash") +
                      (1..11 | ForEach-Object { "step $_" }) + @($script:F)
            Get-ReadmeQuickStart -Line $readme | Should -BeNullOrEmpty
        }

        It 'Rejects a block that is only comments' {
            $readme = @(
                '# widget-tool',
                '## Install',
                "$($script:F)bash",
                '# first do this',
                '# then do that',
                $script:F
            )
            Get-ReadmeQuickStart -Line $readme | Should -BeNullOrEmpty
        }

        It 'Trims comments wrapped around a single command' {
            $readme = @(
                '# widget-tool',
                '## Usage',
                "$($script:F)bash",
                '# Files share one token',
                'node build/index.js --port 8787',
                '# Reuse the same id afterwards',
                $script:F
            )
            (Get-ReadmeQuickStart -Line $readme).Body | Should -Be 'node build/index.js --port 8787'
        }

        It 'De-indents a block nested inside a numbered list' {
            $readme = @(
                '# widget-tool',
                '## Getting Started',
                "   $($script:F)powershell",
                '   Start-Process pwsh',
                "   $($script:F)"
            )
            (Get-ReadmeQuickStart -Line $readme).Body | Should -Be 'Start-Process pwsh'
        }

        It 'Never invents a command when no block exists' {
            Get-ReadmeQuickStart -Line @('# widget-tool', '## Install', 'Run it however you like.') |
                Should -BeNullOrEmpty
        }
    }

    Context 'Get-RepoSummaryText' {

        It 'Prefers an informative GitHub description' {
            Get-RepoSummaryText -RepoName 'sqlite-explorer' `
                -Description 'Local diagnostics browser and JSON API for large SQLite databases.' `
                -ReadmeSummary 'Something much longer taken out of the README file body here.' |
                Should -Be 'Local diagnostics browser and JSON API for large SQLite databases.'
        }

        It 'Falls back to the README when the description just restates the name' {
            Get-RepoSummaryText -RepoName 'index-server' `
                -Description 'Index Server' `
                -ReadmeSummary 'A governed knowledge base that agents query over the Model Context Protocol.' |
                Should -Be 'A governed knowledge base that agents query over the Model Context Protocol.'
        }

        It 'Uses the README when there is no description at all' {
            Get-RepoSummaryText -RepoName 'widget-tool' -Description '' `
                -ReadmeSummary 'A command-line tool for inspecting widget manifests.' |
                Should -Be 'A command-line tool for inspecting widget manifests.'
        }

        It 'Keeps a thin description when the README offers nothing better' {
            Get-RepoSummaryText -RepoName 'sql-diagnostics' `
                -Description 'SQL diagnostics dashboard' -ReadmeSummary $null |
                Should -Be 'SQL diagnostics dashboard'
        }
    }

    Context 'ConvertTo-OrgProfileMarkdown' {

        BeforeAll {
            $script:Repos = @(
                [pscustomobject]@{
                    Name = 'alpha-tool'; Url = 'https://github.com/contoso/alpha-tool'
                    Private = $true; Archived = $false; Language = 'TypeScript'; License = 'MIT'
                    Updated = '2026-09-01'; Summary = 'Does the alpha thing for the platform.'
                    QuickStart = @{ Lang = 'bash'; Body = 'npm install' }
                },
                [pscustomobject]@{
                    Name = 'beta-tool'; Url = 'https://github.com/contoso/beta-tool'
                    Private = $false; Archived = $true; Language = $null; License = $null
                    Updated = '2026-08-02'; Summary = $null; QuickStart = $null
                }
            )
        }

        It 'Renders the org name, tagline and an accurate repository count' {
            $md = ConvertTo-OrgProfileMarkdown -Owner 'contoso' -Repo $script:Repos `
                -Tagline 'Tools for things.' -GeneratedOn ([datetime]'2026-09-24')
            $md | Should -Match '(?m)^# contoso\s*$'
            $md | Should -Match 'Tools for things\.'
            $md | Should -Match '2 repositories \(1 public, 1 private\)'
            $md | Should -Match 'generated 2026-09-24'
        }

        It 'Groups repositories under configured category headings' {
            $cats = [ordered]@{ 'Group A' = @('alpha-tool'); 'Group B' = @('beta-tool') }
            $md = ConvertTo-OrgProfileMarkdown -Owner 'contoso' -Repo $script:Repos -Category $cats
            $md | Should -Match '(?m)^### Group A\s*$'
            $md | Should -Match '(?m)^### Group B\s*$'
        }

        It 'Puts an uncategorised repository under Other rather than dropping it' {
            $cats = [ordered]@{ 'Group A' = @('alpha-tool') }
            $md = ConvertTo-OrgProfileMarkdown -Owner 'contoso' -Repo $script:Repos -Category $cats
            $md | Should -Match '(?m)^### Other\s*$'
            $md | Should -Match 'beta-tool'
        }

        It 'Lists every repository exactly once in the index and the body' {
            $md = ConvertTo-OrgProfileMarkdown -Owner 'contoso' -Repo $script:Repos
            ([regex]::Matches($md, '(?m)^#### \[')).Count | Should -Be 2
            ([regex]::Matches($md, '(?m)^\| \[')).Count | Should -Be 2
        }

        It 'Flags private and archived repositories' {
            $md = ConvertTo-OrgProfileMarkdown -Owner 'contoso' -Repo $script:Repos
            $md | Should -Match "alpha-tool\)\s+$($script:Tick)private$($script:Tick)"
            $md | Should -Match "beta-tool\)\s+$($script:Tick)archived$($script:Tick)"
        }

        It 'Omits language and license facts when GitHub reported none' {
            $md = ConvertTo-OrgProfileMarkdown -Owner 'contoso' -Repo @($script:Repos[1])
            $md | Should -Match '\*\*Updated:\*\* 2026-08-02'
            $md | Should -Not -Match '\*\*Language:\*\*'
            $md | Should -Not -Match '\*\*License:\*\*'
        }

        It 'Emits a quick-start block only for repositories that have one' {
            $md = ConvertTo-OrgProfileMarkdown -Owner 'contoso' -Repo $script:Repos
            ([regex]::Matches($md, '<details><summary>Quick start</summary>')).Count | Should -Be 1
        }

        It 'Balances every code fence it emits' {
            $md = ConvertTo-OrgProfileMarkdown -Owner 'contoso' -Repo $script:Repos
            $fences = ([regex]::Matches($md, "(?m)^$($script:F)")).Count
            ($fences % 2) | Should -Be 0
        }

        It 'Includes the point of contact only when one is configured' {
            $with = ConvertTo-OrgProfileMarkdown -Owner 'contoso' -Repo $script:Repos -Poc 'someone'
            $with | Should -Match '\[@someone\]\(https://github\.com/someone\)'

            $without = ConvertTo-OrgProfileMarkdown -Owner 'contoso' -Repo $script:Repos
            $without | Should -Not -Match 'Point of contact'
        }

        It 'Handles an empty repository set without throwing' {
            { ConvertTo-OrgProfileMarkdown -Owner 'contoso' -Repo @() } | Should -Not -Throw
        }
    }
}
