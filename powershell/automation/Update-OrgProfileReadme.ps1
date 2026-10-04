<#
.SYNOPSIS
    Generates a GitHub organization profile README from live repository metadata.

.DESCRIPTION
    Queries the GitHub API (via the gh CLI) for every repository in an organization,
    pulls each repository's README, and renders profile/README.md -- the path GitHub
    reads an organization profile page from. Output is a grouped index table plus one
    section per repository.

    Content rules, chosen to keep the page trustworthy:

      * The summary line is the repository's GitHub description when one is set and
        informative. Otherwise it is the first substantive paragraph of the README,
        with badges, blockquotes, bullet lists and boilerplate notices skipped.
      * A quick-start block is emitted ONLY when an Install / Quick Start / Getting
        Started / Usage section actually contains a short shell block. Nothing is
        inferred from the repository name -- a fabricated command is worse than no
        command at all.
      * Blocks containing absolute local paths or secret-shaped tokens are dropped,
        and absolute paths appearing in prose are reduced to their final segment, so
        the generated page never leaks the author's machine layout.

    The script is read-only against GitHub: it queries, it never writes.

    Dot-source the script to load its helper functions without running it, which is
    how the Pester suite exercises the extraction logic.

.PARAMETER Org
    GitHub organization (or user) to document. Required when the script is run.

.PARAMETER OutFile
    Path of the README to write. Defaults to ./profile/README.md.

.PARAMETER ConfigPath
    Optional JSON file supplying page text and repository grouping, so the same
    script serves any organization. Shape (every key optional):

        {
          "tagline":      "One line shown under the org name.",
          "poc":          "github-handle",
          "contributing": "Extra paragraph for the Contributing section.",
          "exclude":      ["some-repo"],
          "categories":   { "Group heading": ["repo-a", "repo-b"] }
        }

    Repositories missing from "categories" are listed under a trailing "Other"
    heading, so a newly created repository still reaches the page without anyone
    editing config first.

    Keep the config next to the profile it generates rather than in this repository:
    for a private organization the repository names in it are themselves not public.

.PARAMETER Exclude
    Repository names to leave out. Merged with "exclude" from the config file.

.EXAMPLE
    .\Update-OrgProfileReadme.ps1 -Org contoso-dev
    Writes ./profile/README.md for every repository in contoso-dev.

.EXAMPLE
    .\Update-OrgProfileReadme.ps1 -Org contoso-dev -ConfigPath ./profile.json -WhatIf
    Renders the page to stdout without writing a file.

.NOTES
    Requires the GitHub CLI (gh) on PATH, authenticated against an account that can
    read the target organization.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]   $Org,
    [string]   $OutFile   = (Join-Path (Get-Location) 'profile/README.md'),
    [string]   $ConfigPath,
    [string[]] $Exclude   = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A literal ``` is awkward to embed in a PowerShell string; build it from char codes.
$script:Fence = [string][char]0x60 * 3

# Lines that are repository-template boilerplate rather than a description of the project.
$script:Boilerplate = @(
    '^\*\*Portfolio Project'
    '^This repository follows'
    '^\*\*For contributors\*\*'
    '^Release History'
)

function ConvertTo-PlainText {
    <#
    .SYNOPSIS
        Reduces a line of Markdown to readable prose.
    .DESCRIPTION
        Drops badges and images, unwraps inline and reference-style links to their
        link text, and collapses whitespace.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $t = $Text
    $t = [regex]::Replace($t, '\[!\[[^\]]*\]\[[^\]]*\]\]\[[^\]]*\]', '')   # reference-style linked badge
    $t = [regex]::Replace($t, '\[!\[[^\]]*\]\([^)]*\)\]\([^)]*\)', '')     # inline linked badge
    $t = [regex]::Replace($t, '!\[[^\]]*\]\[[^\]]*\]', '')                 # reference-style image
    $t = [regex]::Replace($t, '!\[[^\]]*\]\([^)]*\)', '')                  # inline image
    $t = [regex]::Replace($t, '\[([^\]]+)\]\([^)]*\)', '$1')               # inline link -> link text
    $t = [regex]::Replace($t, '\[([^\]]+)\]\[[^\]]*\]', '$1')              # reference link -> link text
    $t = $t -replace '\*\*', ''
    $t = $t -replace [string][char]0x60, ''
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Format-PathReference {
    <#
    .SYNOPSIS
        Shortens absolute local paths to their final segment.
    .DESCRIPTION
        A path such as C:\github\owner\template-repo means nothing to a reader and
        leaks the author's machine layout, while the final segment usually names the
        thing being referred to. URLs are left untouched.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    return [regex]::Replace($Text, '(?<!/)\b[A-Za-z]:[\\/][^\s,;:)]*[\\/]([^\s,;:)\\/]+)', '$1')
}

function Test-UsableSummary {
    <#
    .SYNOPSIS
        Returns $true when a candidate paragraph is fit to publish as a summary.
    .DESCRIPTION
        Rejects fragments, leftover badge rows, dangling list lead-ins, license
        boilerplate, and anything still carrying an absolute local path.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowEmptyString()][AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text))     { return $false }
    if ($Text.Length -lt 40)                     { return $false }
    if ($Text -match '^[\W\d\s]+$')              { return $false }   # only punctuation survived stripping
    if ($Text.TrimEnd().EndsWith(':'))           { return $false }   # dangling lead-in to a list
    if ($Text -match '^This project is licensed'){ return $false }
    if ($Text -match '\b[A-Za-z]:[\\/]')         { return $false }
    return $true
}

function Format-Summary {
    <#
    .SYNOPSIS
        Joins paragraph lines into one clean sentence run, truncated at 400 characters.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Part)

    $text = Format-PathReference (ConvertTo-PlainText ($Part -join ' '))
    if ($text.Length -gt 400) {
        $cut = $text.Substring(0, 400)
        $dot = $cut.LastIndexOf('. ')
        $text = if ($dot -gt 200) { $cut.Substring(0, $dot + 1) } else { $cut.TrimEnd() + '...' }
    }
    return $text
}

function Get-ReadmeSummary {
    <#
    .SYNOPSIS
        Extracts a one-paragraph summary from README content.
    .DESCRIPTION
        Prefers an explicit Overview / About section, then the prose above the first
        section heading. Each candidate is bounded by its own section, so a scan
        cannot wander into, say, the License section and report
        "This project is licensed under...".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyCollection()][AllowNull()][string[]]$Line)

    if (-not $Line) { return $null }

    # Drop fenced code so a leading example block is never mistaken for prose.
    $inFence = $false
    $clean = foreach ($l in $Line) {
        if ($l -match "^\s*$script:Fence") { $inFence = -not $inFence; continue }
        if ($inFence) { continue }
        $l
    }
    $clean = @($clean)

    $anchors = [System.Collections.Generic.List[int[]]]::new()
    for ($i = 0; $i -lt $clean.Count; $i++) {
        if ($clean[$i] -match '^(#{2,3})\s.*(Project Overview|Overview|About|What is)') {
            $level = $Matches[1].Length
            $end = $clean.Count
            for ($k = $i + 1; $k -lt $clean.Count; $k++) {
                if ($clean[$k] -match "^#{1,$level}\s") { $end = $k; break }
            }
            $anchors.Add(@(($i + 1), $end))   # parens required: ',' binds tighter than '+'
        }
    }
    $firstSection = $clean.Count
    for ($k = 0; $k -lt $clean.Count; $k++) { if ($clean[$k] -match '^##\s') { $firstSection = $k; break } }
    $anchors.Add(@(0, $firstSection))         # fall back to the prose above the first section

    foreach ($anchor in $anchors) {
        $start = $anchor[0]
        $stop = $anchor[1]
        $para = @()
        for ($i = $start; $i -lt $stop; $i++) {
            $text = $clean[$i]
            $skip = ($text -match '^#') -or
                    ($text -match '^\s*[-*+]\s') -or
                    ($text -match '^\s*\d+\.\s') -or
                    ($text -match '^\s*[>|<]') -or
                    ($text -match '^\s*-{3,}\s*$') -or
                    ($text -match '^\s*\[[^\]]+\]:\s') -or          # link reference definition
                    ($text -match '^\s*$') -or
                    (@($script:Boilerplate | Where-Object { $text -match $_ }).Count -gt 0)

            if (-not $skip) { $para += $text.Trim(); continue }
            if (-not $para.Count) { continue }

            $candidate = Format-Summary -Part $para
            if (Test-UsableSummary $candidate) { return $candidate }
            $para = @()                                            # not usable: try the next paragraph
        }
        if ($para.Count) {
            $candidate = Format-Summary -Part $para
            if (Test-UsableSummary $candidate) { return $candidate }
        }
    }
    return $null
}

function Get-ReadmeQuickStart {
    <#
    .SYNOPSIS
        Extracts one short shell block from a README's install or usage section.
    .DESCRIPTION
        Two passes, so an Install block always beats a Usage block. Returns $null
        rather than guessing when no suitable block exists. Blocks longer than ten
        lines, blocks that are only comments, and blocks carrying absolute paths or
        secret-shaped tokens are all rejected.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowEmptyCollection()][AllowNull()][string[]]$Line)

    if (-not $Line) { return $null }

    $okLang = 'bash|sh|shell|console|powershell|pwsh|cmd|batch'
    $isNoise = { param($l) (-not $l.Trim()) -or ($l.TrimStart() -match '^(#|//|<#)') }

    foreach ($headingPattern in @('(Install|Quick ?Start|Getting Started)', '(Usage|Running)')) {
        $inScope = $false
        for ($i = 0; $i -lt $Line.Count; $i++) {
            $text = $Line[$i]

            if ($text -match '^#{2,4}\s') {
                $inScope = $text -match $headingPattern
                continue
            }
            if (-not $inScope) { continue }
            if ($text -notmatch "^\s*$script:Fence($okLang)\s*$") { continue }

            $lang = $Matches[1]
            $body = @()
            $j = $i + 1
            while ($j -lt $Line.Count -and $Line[$j] -notmatch "^\s*$script:Fence") {
                $body += $Line[$j]
                $j++
            }
            $i = $j
            if ($body.Count -eq 0 -or $body.Count -gt 10) { continue }

            # Strip the common indent left by blocks nested inside numbered lists.
            $indents = @($body | Where-Object { $_.Trim() } | ForEach-Object { $_.Length - $_.TrimStart().Length })
            if ($indents) {
                $pad = ($indents | Measure-Object -Minimum).Minimum
                if ($pad -gt 0) {
                    $body = @($body | ForEach-Object { if ($_.Length -ge $pad) { $_.Substring($pad) } else { $_.TrimStart() } })
                }
            }

            # A block that is nothing but comments teaches the reader nothing;
            # comments wrapped around a command are just noise, so trim the ends.
            $list = [System.Collections.Generic.List[string]]::new()
            $body | ForEach-Object { $list.Add($_) }
            while ($list.Count -gt 0 -and (& $isNoise $list[0])) { $list.RemoveAt(0) }
            while ($list.Count -gt 0 -and (& $isNoise $list[$list.Count - 1])) { $list.RemoveAt($list.Count - 1) }
            if ($list.Count -eq 0) { continue }

            $joined = (@($list) -join "`n").TrimEnd()
            if ($joined -match '\b[A-Za-z]:[\\/]') { continue }
            if ($joined -match 'sk-ant-|gh[pousr]_|Bearer\s') { continue }

            return @{ Lang = $lang; Body = $joined }
        }
    }
    return $null
}

function Get-RepoSummaryText {
    <#
    .SYNOPSIS
        Chooses between a repository's GitHub description and its README paragraph.
    .DESCRIPTION
        Prefers the GitHub description, but falls back to the README when the
        description merely restates the repository name ("Index Server", "Squad
        Skills repository") and the README actually says what the thing does.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$RepoName,
        [AllowEmptyString()][AllowNull()][string]$Description,
        [AllowEmptyString()][AllowNull()][string]$ReadmeSummary
    )

    $desc = if ([string]::IsNullOrWhiteSpace($Description)) { $null } else { $Description.Trim() }
    if (-not $desc) { return $ReadmeSummary }

    $squashedName = $RepoName -replace '[^a-zA-Z0-9]', ''
    $squashedDesc = $desc -replace '[^a-zA-Z0-9]', ''
    $thin = ($desc.Length -lt 50) -or ($squashedDesc -like "*$squashedName*")

    if ($thin -and $ReadmeSummary -and $ReadmeSummary.Length -gt [Math]::Max(60, $desc.Length)) {
        return $ReadmeSummary
    }
    return $desc
}

function Get-RepoReadmeContent {
    <#
    .SYNOPSIS
        Fetches a repository's README as raw text, or $null when it has none.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Repo
    )

    try { return (gh api "repos/$Owner/$Repo/readme" -H 'Accept: application/vnd.github.raw' 2>$null) -join "`n" }
    catch { return $null }
}

function ConvertTo-OrgProfileMarkdown {
    <#
    .SYNOPSIS
        Renders repository metadata as the organization profile page.
    .DESCRIPTION
        Pure function: takes the assembled metadata and page settings and returns
        Markdown. Performs no network or file access, which is what makes the
        rendering testable.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Repo,
        [System.Collections.Specialized.OrderedDictionary]$Category = ([ordered]@{}),
        [AllowNull()][string]$Tagline,
        [AllowNull()][string]$Poc,
        [AllowNull()][string]$Contributing,
        [datetime]$GeneratedOn = (Get-Date)
    )

    $byName = @{}
    foreach ($r in $Repo) { $byName[$r.Name] = $r }

    $grouped = [ordered]@{}
    foreach ($cat in $Category.Keys) {
        $members = foreach ($n in $Category[$cat]) { if ($byName.ContainsKey($n)) { $byName[$n] } }
        if ($members) { $grouped[$cat] = @($members | Sort-Object Name) }
    }
    $claimed = @($Category.Values | ForEach-Object { $_ })
    $other = @($Repo | Where-Object { $_.Name -notin $claimed })
    if ($other) { $grouped[$(if ($grouped.Count) { 'Other' } else { 'Repositories' })] = @($other | Sort-Object Name) }

    $publicCount = @($Repo | Where-Object { -not $_.Private }).Count
    $privateCount = @($Repo | Where-Object { $_.Private }).Count

    $sb = [System.Text.StringBuilder]::new()
    $add = { param([string]$Text = '') [void]$sb.AppendLine($Text) }

    & $add "# $Owner"
    & $add
    if ($Tagline) { & $add $Tagline ; & $add }
    & $add ("> {0} repositories ({1} public, {2} private) - generated {3} by ``Update-OrgProfileReadme.ps1``." -f `
            $Repo.Count, $publicCount, $privateCount, $GeneratedOn.ToString('yyyy-MM-dd'))
    & $add
    & $add '---'
    & $add
    & $add '## Index'
    & $add

    foreach ($cat in $grouped.Keys) {
        & $add "**$cat**"
        & $add
        & $add '| Repository | Language | Updated |'
        & $add '| --- | --- | --- |'
        foreach ($m in $grouped[$cat]) {
            $anchor = $m.Name.ToLower() -replace '[^a-z0-9-]', ''
            $lang = if ($m.Language) { $m.Language } else { '-' }
            & $add "| [$($m.Name)](#$anchor) | $lang | $($m.Updated) |"
        }
        & $add
    }

    & $add '---'
    & $add
    & $add '## Repositories'

    foreach ($cat in $grouped.Keys) {
        & $add
        & $add "### $cat"
        foreach ($m in $grouped[$cat]) {
            & $add
            $flags = @()
            if ($m.Private) { $flags += '`private`' }
            if ($m.Archived) { $flags += '`archived`' }
            $suffix = if ($flags) { ' ' + ($flags -join ' ') } else { '' }
            & $add "#### [$($m.Name)]($($m.Url))$suffix"
            & $add
            if ($m.Summary) { & $add $m.Summary ; & $add }

            $facts = @()
            if ($m.Language) { $facts += "**Language:** $($m.Language)" }
            if ($m.License) { $facts += "**License:** $($m.License)" }
            $facts += "**Updated:** $($m.Updated)"
            & $add ($facts -join ' - ')

            if ($m.QuickStart) {
                & $add
                & $add '<details><summary>Quick start</summary>'
                & $add
                & $add ($script:Fence + $m.QuickStart.Lang)
                & $add $m.QuickStart.Body
                & $add $script:Fence
                & $add
                & $add '</details>'
            }
        }
    }

    & $add
    & $add '---'
    & $add
    if ($Poc) {
        & $add '## Point of contact'
        & $add
        & $add "**POC:** [@$Poc](https://github.com/$Poc)"
        & $add
    }
    & $add '## Contributing'
    & $add
    & $add 'See each repository''s `CONTRIBUTING.md`.'
    if ($Contributing) { & $add ; & $add $Contributing }

    return $sb.ToString()
}

function Invoke-OrgProfileUpdate {
    <#
    .SYNOPSIS
        Gathers repository metadata from GitHub and writes the profile README.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][string]$Path,
        [string]$Config,
        [string[]]$Skip = @()
    )

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw 'The GitHub CLI (gh) is required and was not found on PATH.'
    }

    $settings = if ($Config) {
        if (-not (Test-Path $Config)) { throw "Config file not found: $Config" }
        Get-Content -Path $Config -Raw | ConvertFrom-Json
    }
    else { $null }

    $categories = [ordered]@{}
    $tagline = $null
    $poc = $null
    $contributing = $null
    if ($settings) {
        if ($settings.PSObject.Properties.Name -contains 'tagline') { $tagline = $settings.tagline }
        if ($settings.PSObject.Properties.Name -contains 'poc') { $poc = $settings.poc }
        if ($settings.PSObject.Properties.Name -contains 'contributing') { $contributing = $settings.contributing }
        if ($settings.PSObject.Properties.Name -contains 'exclude') { $Skip = @($Skip) + @($settings.exclude) }
        if ($settings.PSObject.Properties.Name -contains 'categories') {
            foreach ($p in $settings.categories.PSObject.Properties) { $categories[$p.Name] = @($p.Value) }
        }
    }
    $Skip = @($Skip | Where-Object { $_ } | Select-Object -Unique)

    Write-Verbose "Querying $Owner ..."
    # Quoted as one token: unquoted commas would split into separate gh arguments.
    $fields = 'name,description,isPrivate,isArchived,primaryLanguage,licenseInfo,updatedAt,url'
    $repos = gh repo list $Owner --limit 200 --json $fields |
        ConvertFrom-Json |
        Where-Object { $_.name -notin $Skip } |
        Sort-Object name

    if (-not $repos) { throw "No repositories returned for $Owner." }

    $meta = foreach ($r in $repos) {
        Write-Verbose "  $($r.name)"
        $readme = Get-RepoReadmeContent -Owner $Owner -Repo $r.name
        $lines = if ($readme) { @($readme -split "`r?`n") } else { @() }

        # gh returns null for primaryLanguage / licenseInfo when GitHub detected neither,
        # and StrictMode makes chained access on those throw -- unwrap them explicitly.
        $language = if ($r.primaryLanguage) { $r.primaryLanguage.name } else { $null }
        $licenseKey = if ($r.licenseInfo) { $r.licenseInfo.key } else { $null }

        [pscustomobject]@{
            Name       = $r.name
            Url        = $r.url
            Private    = $r.isPrivate
            Archived   = $r.isArchived
            Language   = $language
            # 'other' means GitHub could not identify the license -- naming it would mislead.
            License    = if ($licenseKey -and $licenseKey -ne 'other') { $licenseKey.ToUpper() } else { $null }
            Updated    = ([datetime]$r.updatedAt).ToString('yyyy-MM-dd')
            Summary    = Get-RepoSummaryText -RepoName $r.name -Description $r.description -ReadmeSummary (Get-ReadmeSummary -Line $lines)
            QuickStart = Get-ReadmeQuickStart -Line $lines
        }
    }

    $content = ConvertTo-OrgProfileMarkdown -Owner $Owner -Repo @($meta) -Category $categories `
        -Tagline $tagline -Poc $poc -Contributing $contributing

    if (-not $PSCmdlet.ShouldProcess($Path, "Write profile README for $Owner")) {
        Write-Output $content
        return
    }

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -Path $Path -Value $content -Encoding utf8NoBOM
    Write-Verbose "Wrote $Path - $($meta.Count) repositories."
    return $Path
}

# Dot-sourcing loads the helpers for testing without running the update.
if ($MyInvocation.InvocationName -ne '.') {
    if (-not $Org) { throw 'The -Org parameter is required. See: Get-Help .\Update-OrgProfileReadme.ps1 -Full' }
    Invoke-OrgProfileUpdate -Owner $Org -Path $OutFile -Config $ConfigPath -Skip $Exclude
}
