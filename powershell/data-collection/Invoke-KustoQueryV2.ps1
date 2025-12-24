<#
.SYNOPSIS
script to query kusto with AAD authorization or token using kusto rest api
script gives ability to import, export, execute query and commands, and removing empty columns

.DESCRIPTION
this script will setup Microsoft.IdentityModel.Clients Msal for use with powershell 5.1, 6, and 7
KustoObj will be created as $global:kusto to hold properties and run methods from

When run on PowerShell Core, the script now defaults to using Microsoft.Azure.Kusto.Data for token acquisition and falls back to the legacy MSAL flow automatically if the SDK assemblies are unavailable. Windows PowerShell (.NET 4.6.2) continues using the legacy MSAL path by default.

The Kusto SDK path honors service principal credentials, managed identities, and the Azure CLI token cache (when the `az` executable is available). When no supported SDK credential source is detected, the script transparently reverts to the legacy MSAL flow and emits a single warning.

use the following to save and pass arguments:
[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/kusto-rest.ps1" -outFile "$pwd/kusto-rest.ps1";
.\kusto-rest.ps1 -cluster %kusto cluster% -database %kusto database%

.NOTES
Author : jagilber
File Name  : kusto-rest.ps1
Version    : 240521
History    : resolve cluster and database on first run
            When running troubleshooting commands from the established session, avoid prefixing with 'pwsh' or 'powershell'; reuse the existing shell so the loaded types remain available.
            Azure CLI authentication requires the `az` executable in PATH; otherwise the script will fall back to the MSAL flow.

.EXAMPLE
.\kusto-rest.ps1 -cluster kustocluster -database kustodatabase

.EXAMPLE
.\kusto-rest.ps1 -cluster kustocluster -database kustodatabase
$kusto.Exec('.show tables')

.EXAMPLE
$kusto.viewresults = $true
$kusto.SetTable($table)
$kusto.SetDatabase($database)
$kusto.SetCluster($cluster)
$kusto.parameters = @{'T'= $table}
$kusto.ExecScript("..\KustoFunctions\sflogs\TraceKnownIssueSummary.csl", $kusto.parameters)

.EXAMPLE
$kusto.SetTable("test_$env:USERNAME").Import()

.EXAMPLE
$kusto.SetPipe($true).SetCluster('azure').SetDatabase('azure').Exec("EventEtwTable | where TIMESTAMP > ago(1d) | where TenantName == $tenantId")

.EXAMPLE
.\kusto-rest.ps1 -cluster kustocluster -database kustodatabase
$kusto.Exec('.show tables')
$kusto.ExportCsv("$env:temp\test.csv")
type $env:temp\test.csv

.EXAMPLE
pwsh ./kusto-rest.ps1 -cluster kustocluster -database kustodatabase -AuthMode KustoSdk

Demonstrates the default Kusto SDK authentication path on PowerShell Core using Azure CLI cached credentials when available.

.PARAMETER query
query string or command to execute against a kusto database

.PARAMETER cluster
[string]kusto cluster name. (host name not fqdn)
    example: kustocluster
    example: azurekusto.eastus

.PARAMETER database
[string]kusto database name

.PARAMETER table
[string]optional kusto table for import

.PARAMETER headers
[string]optional kusto table headers for import ['columnname']:columntype,

.PARAMETER resultFile
[string]optional json file name and path to store raw result content

.PARAMETER viewResults
[bool]option if enabled will display results in console output

.PARAMETER token
[string]optional token to connect to kusto. if not provided, script will attempt to authorize user to given cluster and database

.PARAMETER limit
[int]optional result limit. default 10,000

.PARAMETER script
[string]optional path and name of kusto script file (.csl|.kusto) to execute

.PARAMETER clientSecret
[string]optional azure client secret to connect to kusto. if not provided, script will attempt to authorize user to given cluster and database
requires clientId

.PARAMETER clientId
[string]optional azure client id to connect to kusto. if not provided, script will attempt to authorize user to given cluster and database
requires clientSecret

.PARAMETER tenantId
[guid]optional tenantId to use for authorization. default is 'common'

.PARAMETER subscriptionId
[string]optional subscription id that should own the Azure CLI token when the SDK path is used. When provided, CLI tokens tied to other subscriptions are ignored.

.PARAMETER accountId
[string]optional user principal name (UPN) that should own the Azure CLI token when the SDK path is used. When provided, CLI tokens issued for other identities are ignored.

.PARAMETER force
[bool]enable to force authentication regardless if token is valid

.PARAMETER serverTimeout
[timespan]optional override default 4 minute kusto server side timeout. max 60 minutes.

.PARAMETER updateScript
[switch]optional enable to download latest version of script

.PARAMETER parameters
[hashtable]optional hashtable of parameters to pass to kusto script (.csl|kusto) file

.PARAMETER authMode
[ValidateSet("Auto","KustoSdk","Legacy")] optional authentication mode selector. Auto chooses the Kusto SDK on PowerShell Core and falls back to the legacy MSAL flow elsewhere.

.PARAMETER managedIdentityClientId
[string]optional managed identity client id to use with the Kusto SDK authentication path. Supported on PowerShell Core where the Kusto SDK assemblies can be loaded.

.PARAMETER useAzCliCache
[switch]optional enables reuse of Azure CLI cached credentials when using the Kusto SDK authentication path. Enabled by default on supported platforms; requires the Azure CLI (`az`) to be installed and available in PATH.

.PARAMETER skipPackageRestore
[switch]optional skip automatic NuGet restore attempts for additional client libraries. When set, existing assemblies must already be available.

.OUTPUTS
KustoObj

.LINK
https://raw.githubusercontent.com/jagilber/powershellScripts/master/kusto-rest.ps1
#>

[cmdletbinding()]
param(
    [string]$cluster,
    [string]$database,
    [string]$query = '.show tables',
    [bool]$fixDuplicateColumns,
    [bool]$removeEmptyColumns = $true,
    [string]$table,
    [string]$headers,
    [string]$identityPackageLocation,
    [string]$resultFile, # = ".\result.json",
    [bool]$createResults = $true,
    [bool]$viewResults = $true,
    [string]$token,
    [int]$limit,
    [string]$script,
    [string]$clientSecret,
    [string]$clientId = "1950a258-227b-4e31-a9cf-717495945fc2",
    [string]$tenantId = "common",
    [string]$subscriptionId,
    [string]$accountId,
    [bool]$pipeLine,
    [string]$redirectUri = "http://localhost", # "urn:ietf:wg:oauth:2.0:oob", #$null
    [bool]$force,
    [timespan]$serverTimeout = (new-Object timespan (0, 4, 0)),
    [switch]$updateScript,
    [hashtable]$parameters = @{ },
    [ValidateSet('Auto','KustoSdk','Legacy')]
    [string]$authMode = 'Auto',
    [string]$managedIdentityClientId,
    [switch]$useAzCliCache,
    [switch]$skipPackageRestore
)

$PSModuleAutoLoadingPreference = 2
$ErrorActionPreference = "continue"
$global:kusto = $null
$global:identityPackageLocation = $null
$script:DefaultPackageVersion = "4.28.0"
$script:PackageVersionOverrides = @{
    'Microsoft.Identity.Client'          = '4.60.3'
    'Microsoft.IdentityModel.Abstractions' = '6.35.0'
}
$global:kustoSdkAssemblyLoaded = $false
$global:kustoSdkPackageLocation = $null
$kustoSdkPreferredVersion = "12.0.0"
$kustoSdkMinimumVersion = [version]::new(12, 0)
$script:MsalDependencyStatus = $null

[string]$resolvedAuthMode = $authMode
if ($resolvedAuthMode -eq 'Auto') {
    if ($PSVersionTable.PSEdition -eq 'Core') {
        $resolvedAuthMode = 'KustoSdk'
    }
    else {
        $resolvedAuthMode = 'Legacy'
    }
}

if ($resolvedAuthMode -eq 'KustoSdk' -and $PSVersionTable.PSEdition -ne 'Core') {
    Write-Warning "Kusto SDK authentication is only supported on PowerShell Core. Falling back to Legacy authentication."
    $resolvedAuthMode = 'Legacy'
}

[bool]$resolvedUseAzCliCache = if ($PSBoundParameters.ContainsKey('useAzCliCache')) {
    [bool]$useAzCliCache
}
else {
    $resolvedAuthMode -eq 'KustoSdk'
}

[bool]$resolvedSkipPackageRestore = [bool]$skipPackageRestore
$authModeSummary = "AuthMode=$resolvedAuthMode; UseAzCliCache=$resolvedUseAzCliCache; SkipPackageRestore=$resolvedSkipPackageRestore"
Write-Verbose "kusto-rest.v2 authentication configuration: $authModeSummary"
$authMode = $resolvedAuthMode

if ($updateScript) {
    invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/kusto-rest.ps1" -outFile  "$psscriptroot/kusto-rest.ps1";
    write-warning "script updated. restart script"
    return
}

function Get-KustoSdkType {
    param(
        [string[]]$TypeNames
    )

    foreach ($candidate in ($TypeNames | Where-Object { $_ })) {
        $type = [System.Type]::GetType($candidate, $false)
        if ($type) {
            return $type
        }

        if ($PSVersionTable.PSEdition -eq 'Core') {
            foreach ($assembly in [System.Runtime.Loader.AssemblyLoadContext]::Default.Assemblies) {
                try {
                    $type = $assembly.GetType($candidate, $false)
                }
                catch {
                    continue
                }

                if ($type) {
                    return $type
                }
            }
        }
    }

    return $null
}

function main() {
    try {
        $error.Clear()
        $context = Get-KustoInitializationContext
        $global:kusto = [KustoObj]::Create($context)
        $kusto.SetTables()
        $kusto.SetFunctions()
        $kusto.Exec()
        $kusto.ClearResults()

        write-host ($PSBoundParameters | out-string)

        if ($error) {
            write-warning ($error | out-string)
        }
        else {
            write-host ($kusto | Get-Member | out-string)
            write-host "use `$kusto object to set properties and run queries. example: `$kusto.Exec('.show operations')" -ForegroundColor Green
            write-host "set `$kusto.viewresults=`$true to see results." -ForegroundColor Green
        }
    }
    catch {
        write-host "exception::$($psitem.Exception.Message)`r`n$($psitem.scriptStackTrace)" -ForegroundColor Red
    }
}

function Get-KustoInitializationContext {
    return @{
        identityPackageLocation = $identityPackageLocation
        AuthMode                 = $authMode
        clientId                 = $clientId
        clientSecret             = $clientSecret
        Cluster                  = $cluster
        Database                 = $database
        FixDuplicateColumns      = $fixDuplicateColumns
        Force                    = $force
        Headers                  = $headers
        Limit                    = $limit
        ManagedIdentityClientId  = $managedIdentityClientId
        Parameters               = $parameters
        PipeLine                 = $pipeLine
        Query                    = $query
        redirectUri              = $redirectUri
        RemoveEmptyColumns       = $removeEmptyColumns
        ResultFile               = $resultFile
        Script                   = $script
        Table                    = $table
        tenantId                 = $tenantId
        SubscriptionId           = $subscriptionId
        AccountId                = $accountId
        ServerTimeout            = $serverTimeout
        UseAzCliCache            = $resolvedUseAzCliCache
        SkipPackageRestore       = $resolvedSkipPackageRestore
        CreateResults            = $createResults
        ViewResults              = $viewResults
    }
}

function AddIdentityPackageType {
    param(
        [string]$packageName,
        [string]$edition,
        [string]$Version
    )

    # support ps core on linux
    if ($IsLinux) {
        $env:USERPROFILE = $env:HOME
    }
    [string]$nugetPackageDirectory = "$($env:USERPROFILE)/.nuget/packages"
    [string]$nugetSource = "https://api.nuget.org/v3/index.json"
    [string]$nugetDownloadUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
    [io.directory]::createDirectory($nugetPackageDirectory)
    [string]$packageDirectory = "$nugetPackageDirectory/$packageName"

    [string]$preferredVersion = if ($PSBoundParameters.ContainsKey('Version') -and $Version) {
        $Version
    }
    elseif ($script:PackageVersionOverrides.ContainsKey($packageName)) {
        $script:PackageVersionOverrides[$packageName]
    }
    else {
        $script:DefaultPackageVersion
    }

    $global:identityPackageLocation = get-identityPackageLocation -PackageDirectory $packageDirectory -PackageName $packageName -Edition $edition -MinimumVersion $preferredVersion -PreferredVersion $preferredVersion

    if (!$global:identityPackageLocation) {
        if ($psedition -ieq 'core') {
            $tempProjectFile = './temp.csproj'

            #dotnet new console
            $csproj = "<Project Sdk=`"Microsoft.NET.Sdk`">
                    <PropertyGroup>
                        <OutputType>Exe</OutputType>
                        <TargetFramework>$edition</TargetFramework>
                    </PropertyGroup>
                    <ItemGroup>
                        <PackageReference Include=`"$packageName`" Version=`"$preferredVersion`" />
                    </ItemGroup>
                </Project>
            "

            out-file -InputObject $csproj -FilePath $tempProjectFile
            write-host "dotnet restore --packages $packageDirectory --no-cache --no-dependencies $tempProjectFile"
            dotnet restore --packages $packageDirectory --no-cache --no-dependencies $tempProjectFile

            remove-item "$pwd/obj" -re -fo
            remove-item -path $tempProjectFile
        }
        else {
            $nuget = "nuget.exe"
            if (!(test-path $nuget)) {
                $nuget = "$env:temp/nuget.exe"
                if (!(test-path $nuget)) {
                    [net.webclient]::new().DownloadFile($nugetDownloadUrl, $nuget)
                }
            }
            [string]$localPackages = . $nuget list -Source $nugetPackageDirectory
            $packageSignature = if ($preferredVersion) { "$packageName $preferredVersion" } else { "$edition.$packageName" }

            if ($force -or !($localPackages -imatch [regex]::Escape($packageSignature))) {
                $installArgs = @('install', $packageName, '-Source', $nugetSource, '-outputdirectory', $nugetPackageDirectory, '-verbosity', 'detailed')
                if ($preferredVersion) {
                    $installArgs += @('-Version', $preferredVersion)
                }
                write-host "$nuget $($installArgs -join ' ')"
                . $nuget @installArgs
            }
            else {
                write-host "$packageName already installed" -ForegroundColor green
            }
        }
    }

    $global:identityPackageLocation = get-identityPackageLocation -PackageDirectory $packageDirectory -PackageName $packageName -Edition $edition -MinimumVersion $preferredVersion -PreferredVersion $preferredVersion

    if (!$global:identityPackageLocation) {
        write-warning "AddIdentityPackageType: unable to locate $packageName (edition $edition, minimum version $preferredVersion) in $packageDirectory"
        return $false
    }

    write-host "identityDll: $($global:identityPackageLocation)" -ForegroundColor Green
    add-type -literalPath $global:identityPackageLocation
    return $true
}

function get-identityPackageLocation {
    param(
        [string]$PackageDirectory,
        [string]$PackageName,
        [string]$Edition,
        [string]$MinimumVersion,
        [string]$PreferredVersion
    )

    if (!(Test-Path $PackageDirectory)) {
        return $null
    }

    [version]$minimumVersionObject = $null
    if ($MinimumVersion) {
        try {
            $minimumVersionObject = [version]$MinimumVersion
        }
        catch {
            Write-Verbose "get-identityPackageLocation: unable to parse minimum version '$MinimumVersion' for $PackageName"
        }
    }

    [version]$preferredVersionObject = $null
    if ($PreferredVersion) {
        try {
            $preferredVersionObject = [version]$PreferredVersion
        }
        catch {
            Write-Verbose "get-identityPackageLocation: unable to parse preferred version '$PreferredVersion' for $PackageName"
        }
    }

    $candidates = @()

    $files = get-childitem -Path $PackageDirectory -Recurse -Filter "$PackageName.dll" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "lib.$Edition." }

    if ($files) {
        $fileList = $files | Select-Object -ExpandProperty FullName
        write-host "existing identity dlls $($fileList | Out-String)"
    }
    else {
        write-host "existing identity dlls <none>"
    }

    foreach ($file in $files) {
        $versionString = [regex]::match($file.FullName, ".$PackageName.([0-9.]+?).lib.$Edition", [text.regularexpressions.regexoptions]::IgnoreCase).Groups[1].Value
        if (!$versionString) { continue }

        try {
            $version = [version]$versionString
        }
        catch {
            continue
        }

        $candidates += [pscustomobject]@{
            Path    = $file.FullName
            Version = $version
        }
    }

    if ($preferredVersionObject) {
        $exactMatch = $candidates | Where-Object { $_.Version -eq $preferredVersionObject } | Sort-Object Version -Descending | Select-Object -First 1
        if ($exactMatch) {
            write-host "selected version:$($exactMatch.Version) for package:$PackageName (exact match)"
            return $exactMatch.Path
        }
    }

    if ($minimumVersionObject) {
        $eligible = $candidates | Where-Object { $_.Version -ge $minimumVersionObject } | Sort-Object Version -Descending

        if ($eligible) {
            $sameMajor = $eligible | Where-Object { $_.Version.Major -eq $minimumVersionObject.Major }
            if ($sameMajor) {
                $selection = $sameMajor | Sort-Object Version -Descending | Select-Object -First 1
                write-host "selected version:$($selection.Version) for package:$PackageName (major $($minimumVersionObject.Major))"
                return $selection.Path
            }

            $selection = $eligible | Select-Object -First 1
            write-host "selected version:$($selection.Version) for package:$PackageName (closest eligible)"
            return $selection.Path
        }
    }

    if ($candidates) {
        $fallback = $candidates | Sort-Object Version -Descending | Select-Object -First 1
        write-host "selected version:$($fallback.Version) for package:$PackageName (fallback)"
        return $fallback.Path
    }

    return $null
}
function Resolve-KustoAssemblyPath {
    param(
        [string]$NugetPackageDirectory,
        [string]$PackageName,
        [string[]]$FrameworkCandidates,
        [string]$AssemblyFileName,
        [version]$MinimumVersion
    )

    if (!(Test-Path $NugetPackageDirectory)) {
        [void][io.directory]::CreateDirectory($NugetPackageDirectory)
    }

    $packageDirectoryName = $PackageName.ToLowerInvariant()
    $packageDirectory = Join-Path $NugetPackageDirectory $packageDirectoryName

    if (!(Test-Path $packageDirectory)) {
        return $null
    }

    if (-not $FrameworkCandidates -or $FrameworkCandidates.Count -eq 0) {
        $FrameworkCandidates = @('netstandard2.0')
    }

    if (-not $AssemblyFileName) {
        $AssemblyFileName = "$PackageName.dll"
    }

    $orderedFrameworks = $FrameworkCandidates | Where-Object { $_ -and $_.Trim() }

    foreach ($versionDirectory in (Get-ChildItem -Path $packageDirectory -Directory | Sort-Object Name -Descending)) {
        try {
            $parsedVersion = [version]$versionDirectory.Name
        }
        catch {
            continue
        }

        if ($parsedVersion -lt $MinimumVersion) {
            continue
        }

        foreach ($framework in $orderedFrameworks) {
            $candidatePath = [io.path]::Combine($versionDirectory.FullName, 'lib', $framework, $AssemblyFileName)
            if (Test-Path $candidatePath) {
                return [pscustomobject]@{
                    Path          = $candidatePath
                    Version       = $parsedVersion
                    Framework     = $framework
                    BaseDirectory = Split-Path -Parent $candidatePath
                }
            }

            $runtimeRoot = Join-Path $versionDirectory.FullName 'runtimes'
            if (Test-Path $runtimeRoot) {
                $runtimeCandidate = Get-ChildItem -Path $runtimeRoot -Filter $AssemblyFileName -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -match [regex]::Escape($framework) }

                if ($runtimeCandidate) {
                    $selected = $runtimeCandidate | Select-Object -First 1
                    return [pscustomobject]@{
                        Path          = $selected.FullName
                        Version       = $parsedVersion
                        Framework     = $framework
                        BaseDirectory = Split-Path -Parent $selected.FullName
                    }
                }
            }
        }
    }

    return $null
}

function Restore-KustoPackage {
    param(
        [string]$NugetPackageDirectory,
        [string]$PackageName,
        [string]$PreferredVersion
    )

    if ($PSVersionTable.PSEdition -ne 'Core') {
        Write-Verbose "Restore-KustoPackage: skipping restore for $PackageName on Windows PowerShell"
        return $false
    }

    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if (!$dotnet) {
        Write-Warning "dotnet command not found. Install .NET SDK to enable Kusto SDK authentication or rerun with -AuthMode Legacy."
        return $false
    }

    $attemptVersions = @()
    if ($PreferredVersion) {
        $attemptVersions += $PreferredVersion
    }
    $attemptVersions += $null

    foreach ($version in $attemptVersions) {
        $tempRoot = Join-Path $env:TEMP "kusto-rest-sdk-$([guid]::NewGuid().ToString('N'))"
        try {
            [void][io.directory]::CreateDirectory($tempRoot)
            $tempProjectFile = Join-Path $tempRoot 'kusto-rest-sdk.csproj'
            $packageReference = if ($null -ne $version) {
                "<PackageReference Include=`"$PackageName`" Version=`"$version`" />"
            }
            else {
                "<PackageReference Include=`"$PackageName`" />"
            }

            $projectContent = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net6.0</TargetFramework>
    <RestorePackagesWithLockFile>false</RestorePackagesWithLockFile>
  </PropertyGroup>
  <ItemGroup>
    $packageReference
  </ItemGroup>
</Project>
"@
            $projectContent | Out-File -FilePath $tempProjectFile -Encoding UTF8 -Force

            $restoreArgs = @('restore', '--packages', $NugetPackageDirectory, '--no-cache', '--no-dependencies', $tempProjectFile)
            Write-Verbose "dotnet $($restoreArgs -join ' ')"
            $output = & $dotnet.Source @restoreArgs 2>&1
            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0) {
                Write-Verbose "Restore-KustoPackage: successfully restored $PackageName version $version"
                return $true
            }

            Write-Verbose "Restore-KustoPackage: failed to restore $PackageName version $version`n$output"
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Warning "Unable to restore NuGet package $PackageName. Ensure network connectivity or restore the package manually."
    return $false
}

function Get-KustoSdkLibrary {
    param(
        [switch]$SkipRestore
    )

    if ($global:kustoSdkAssemblyLoaded) {
        return $true
    }

    $existingType = Get-KustoSdkType @(
        'Kusto.Data.KustoConnectionStringBuilder',
        'Microsoft.Azure.Kusto.Data.KustoConnectionStringBuilder'
    )

    if ($existingType) {
        $global:kustoSdkAssemblyLoaded = $true
        return $true
    }

    if ($PSVersionTable.PSEdition -ne 'Core') {
        Write-Verbose "Get-KustoSdkLibrary: PowerShell Core is required for Kusto SDK assemblies"
        return $false
    }

    if ($IsLinux) {
        $env:USERPROFILE = $env:HOME
    }

    $nugetPackageDirectory = Join-Path $env:USERPROFILE '.nuget/packages'
    $frameworkCandidates = @(
        'net8.0',
        'net7.0',
        'net6.0',
        'netstandard2.1',
        'netstandard2.0',
        'net5.0',
        'netcoreapp2.1'
    )
    $frameworkList = $frameworkCandidates -join ', '

    $packageSpecs = @(
        [pscustomobject]@{ Name = 'Microsoft.Azure.Kusto.Data'; Assembly = 'Kusto.Data.dll'; MinimumVersion = $kustoSdkMinimumVersion },
        [pscustomobject]@{ Name = 'Microsoft.Azure.Kusto.Cloud.Platform'; Assembly = 'Kusto.Cloud.Platform.dll'; MinimumVersion = $kustoSdkMinimumVersion },
        [pscustomobject]@{ Name = 'Microsoft.Azure.Kusto.Cloud.Platform.Msal'; Assembly = 'Kusto.Cloud.Platform.Msal.dll'; MinimumVersion = $kustoSdkMinimumVersion }
    )

    $resolvedAssemblies = @()

    foreach ($spec in $packageSpecs) {
        $assemblyInfo = Resolve-KustoAssemblyPath -NugetPackageDirectory $nugetPackageDirectory -PackageName $spec.Name -FrameworkCandidates $frameworkCandidates -AssemblyFileName $spec.Assembly -MinimumVersion $spec.MinimumVersion

        if (!$assemblyInfo -and !$SkipRestore) {
            if (Restore-KustoPackage -NugetPackageDirectory $nugetPackageDirectory -PackageName $spec.Name -PreferredVersion $kustoSdkPreferredVersion) {
                $assemblyInfo = Resolve-KustoAssemblyPath -NugetPackageDirectory $nugetPackageDirectory -PackageName $spec.Name -FrameworkCandidates $frameworkCandidates -AssemblyFileName $spec.Assembly -MinimumVersion $spec.MinimumVersion
            }
        }

        if (!$assemblyInfo) {
            $packageRoot = Join-Path $nugetPackageDirectory ($spec.Name.ToLowerInvariant())
            if (Test-Path $packageRoot) {
                $availableFrameworks = foreach ($versionDir in (Get-ChildItem -Path $packageRoot -Directory -ErrorAction SilentlyContinue)) {
                    $libRoot = Join-Path $versionDir.FullName 'lib'
                    if (Test-Path $libRoot) {
                        foreach ($frameworkDir in (Get-ChildItem -Path $libRoot -Directory -ErrorAction SilentlyContinue)) {
                            [pscustomobject]@{
                                Version   = $versionDir.Name
                                Framework = $frameworkDir.Name
                            }
                        }
                    }
                }

                if ($availableFrameworks) {
                    $summary = $availableFrameworks | Sort-Object Version, Framework | Select-Object -First 10 | ForEach-Object { "v$($_.Version):$($_.Framework)" }
                    Write-Verbose "Get-KustoSdkLibrary: available $($spec.Name) frameworks -> $($summary -join ', ')"
                }
            }

            Write-Warning "Get-KustoSdkLibrary: unable to locate $($spec.Assembly) for package $($spec.Name) (searched frameworks: $frameworkList). Falling back to legacy authentication."
            return $false
        }

        Write-Verbose "Get-KustoSdkLibrary: using $($spec.Assembly) version $($assemblyInfo.Version) (framework $($assemblyInfo.Framework)) from $($assemblyInfo.BaseDirectory)"
        $resolvedAssemblies += $assemblyInfo
    }

    $searchRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($info in $resolvedAssemblies) {
        $baseDir = $info.BaseDirectory
        $libRoot = Split-Path -Parent $baseDir
        if ($baseDir -and (Test-Path $baseDir)) {
            [void]$searchRoots.Add((Resolve-Path $baseDir).ProviderPath)
        }
        if ($libRoot -and (Test-Path $libRoot)) {
            [void]$searchRoots.Add((Resolve-Path $libRoot).ProviderPath)
        }
    }
    Register-KustoAssemblyResolver -PrimaryDirectories $searchRoots

    foreach ($info in $resolvedAssemblies) {
        try {
            Add-Type -LiteralPath $info.Path -ErrorAction Stop
        }
        catch {
            if ($_.Exception -and $_.Exception.Message -notmatch 'already exists') {
                Write-Verbose "Get-KustoSdkLibrary: unable to load $([System.IO.Path]::GetFileName($info.Path)) - $($_.Exception.Message)"
            }
        }
    }

    $global:kustoSdkPackageLocation = ($resolvedAssemblies | Select-Object -First 1).BaseDirectory
    $global:kustoSdkAssemblyLoaded = $true
    return $true
}

function Register-KustoAssemblyResolver {
    param(
        [string[]]$PrimaryDirectories
    )

    if ($PSVersionTable.PSEdition -ne 'Core') {
        return
    }

    if (-not $script:KustoAssemblySearchRoots) {
        $script:KustoAssemblySearchRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    foreach ($dir in ($PrimaryDirectories | Where-Object { $_ })) {
        try {
            if (Test-Path $dir) {
                [void]$script:KustoAssemblySearchRoots.Add((Resolve-Path $dir).ProviderPath)
            }
        }
        catch {
            Write-Verbose "Register-KustoAssemblyResolver: unable to add search root $dir. $($_.Exception.Message)"
        }
    }

    if ($script:KustoAssemblyResolverRegistered) {
        return
    }

    $script:KustoAssemblyResolverRegistered = $true
    $script:KustoAssemblyResolutionCache = @{}

    $nugetRoot = Join-Path $env:USERPROFILE '.nuget/packages'
    if (Test-Path $nugetRoot) {
        [void]$script:KustoAssemblySearchRoots.Add((Resolve-Path $nugetRoot).ProviderPath)
        $script:KustoAssemblyNugetRoot = (Resolve-Path $nugetRoot).ProviderPath
    }

    [System.Runtime.Loader.AssemblyLoadContext]::Default.add_Resolving({
            param($context, $assemblyName)

            $shortName = $assemblyName.Name
            if ($script:KustoAssemblyResolutionCache.ContainsKey($shortName)) {
                $cachedPath = $script:KustoAssemblyResolutionCache[$shortName]
                if ($cachedPath -and (Test-Path $cachedPath)) {
                    try {
                        return $context.LoadFromAssemblyPath($cachedPath)
                    }
                    catch {
                        Write-Verbose "Register-KustoAssemblyResolver: failed to load cached path $cachedPath for $shortName. $($_.Exception.Message)"
                    }
                }

                return $null
            }

            $resolvedPath = $null

            foreach ($root in $script:KustoAssemblySearchRoots) {
                try {
                    if ($root -eq $script:KustoAssemblyNugetRoot) {
                        $packageDir = Join-Path $root ($shortName.ToLowerInvariant())
                        if (Test-Path $packageDir) {
                            $candidate = Get-ChildItem -Path $packageDir -Recurse -Filter "$shortName.dll" -File -ErrorAction SilentlyContinue |
                                Sort-Object FullName -Descending |
                                Select-Object -First 1
                            if ($candidate) {
                                $resolvedPath = $candidate.FullName
                                break
                            }
                        }

                        $candidate = Get-ChildItem -Path $root -Recurse -Filter "$shortName.dll" -File -ErrorAction SilentlyContinue -Depth 3 |
                            Sort-Object FullName -Descending |
                            Select-Object -First 1
                        if ($candidate) {
                            $resolvedPath = $candidate.FullName
                            break
                        }
                    }
                    else {
                        $candidate = Get-ChildItem -Path $root -Filter "$shortName.dll" -File -ErrorAction SilentlyContinue | Select-Object -First 1
                        if (!$candidate) {
                            $candidate = Get-ChildItem -Path $root -Recurse -Filter "$shortName.dll" -File -ErrorAction SilentlyContinue -Depth 3 |
                                Select-Object -First 1
                        }

                        if ($candidate) {
                            $resolvedPath = $candidate.FullName
                            break
                        }
                    }
                }
                catch {
                    Write-Verbose "Register-KustoAssemblyResolver: assembly scan in $root failed for $shortName. $($_.Exception.Message)"
                }
            }

            $script:KustoAssemblyResolutionCache[$shortName] = $resolvedPath

            if ($resolvedPath -and (Test-Path $resolvedPath)) {
                try {
                    return $context.LoadFromAssemblyPath($resolvedPath)
                }
                catch {
                    Write-Verbose "Register-KustoAssemblyResolver: unable to load $shortName from $resolvedPath. $($_.Exception.Message)"
                }
            }

            return $null
        })
}

function Initialize-MsalDependencyAssemblies {
    param(
        [string]$Edition
    )

    $script:MsalDependencyStatus = $null

    try {
        $msalAssembly = [Microsoft.Identity.Client.ConfidentialClientApplication].Assembly
    }
    catch {
        return $false
    }

    $requiredReference = $msalAssembly.GetReferencedAssemblies() |
        Where-Object Name -eq 'Microsoft.IdentityModel.Abstractions' |
        Select-Object -First 1

    if (!$requiredReference) {
        return $true
    }

    $requiredVersion = $requiredReference.Version

    $loadedAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Microsoft.IdentityModel.Abstractions' } |
        Sort-Object { $_.GetName().Version } -Descending |
        Select-Object -First 1

    if ($loadedAssembly) {
        $currentVersion = $loadedAssembly.GetName().Version
        if ($currentVersion -ge $requiredVersion) {
            return $true
        }

        $script:MsalDependencyStatus = "Microsoft.IdentityModel.Abstractions $requiredVersion is required, but $currentVersion is already loaded in this session. Restart the PowerShell session to load the newer assembly."
        Write-Warning "Initialize-MsalDependencyAssemblies: Microsoft.IdentityModel.Abstractions $currentVersion already loaded, but version $requiredVersion is required. Restart the PowerShell session to load the newer assembly."
        return $false
    }

    if ($msalAssembly.Location) {
        $localDependencyPath = Join-Path (Split-Path $msalAssembly.Location -Parent) 'Microsoft.IdentityModel.Abstractions.dll'
        if (Test-Path $localDependencyPath) {
            try {
                Add-Type -LiteralPath $localDependencyPath -ErrorAction Stop
                return $true
            }
            catch {
                Write-Verbose "Initialize-MsalDependencyAssemblies: failed to load dependency from $localDependencyPath. $($_.Exception.Message)"
            }
        }
    }

    $targetVersion = "{0}.{1}.{2}" -f $requiredVersion.Major, $requiredVersion.Minor, $requiredVersion.Build
    if (!(AddIdentityPackageType -packageName 'Microsoft.IdentityModel.Abstractions' -edition $Edition -Version $targetVersion)) {
        $script:MsalDependencyStatus = "Unable to load Microsoft.IdentityModel.Abstractions $requiredVersion from NuGet. Verify connectivity or pre-install the package."
        Write-Warning "Initialize-MsalDependencyAssemblies: unable to add Microsoft.IdentityModel.Abstractions version $requiredVersion."
        return $false
    }

    $loadedAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'Microsoft.IdentityModel.Abstractions' } |
        Sort-Object { $_.GetName().Version } -Descending |
        Select-Object -First 1

    if ($loadedAssembly -and $loadedAssembly.GetName().Version -ge $requiredVersion) {
        return $true
    }

    if (-not $script:MsalDependencyStatus) {
        $script:MsalDependencyStatus = "Microsoft.IdentityModel.Abstractions $requiredVersion could not be loaded."
    }
    Write-Warning "Initialize-MsalDependencyAssemblies: Microsoft.IdentityModel.Abstractions $requiredVersion still not loaded."
    return $false
}

function get-msalLibrary() {
    # Install latest AD client library
    $msalEdition = if ($global:PSVersionTable.PSEdition -eq "Core") { "net6.0" } else { "net461" }
    $abstractionsEdition = if ($global:PSVersionTable.PSEdition -eq "Core") { "net6.0" } else { "net6.0" }

    try {
        if (([Microsoft.Identity.Client.ConfidentialClientApplication]) -and !$force) {
            write-host "[Microsoft.Identity.Client.AzureCloudInstance] already loaded. skipping" -ForegroundColor Cyan
            if (!(Initialize-MsalDependencyAssemblies -Edition $abstractionsEdition)) {
                if ($script:MsalDependencyStatus) {
                    Write-Error $script:MsalDependencyStatus
                }
                return $false
            }
            return $true
        }
    }
    catch {
        write-verbose "exception checking for identity client:$($error|out-string)"
        $error.Clear()
    }

    if ($global:PSVersionTable.PSEdition -eq "Core") {
        write-host "setting up microsoft.identity.client for .net core"
    }
    else {
        write-host "setting up microsoft.identity.client for .net framework"
    }

    $msalPreferredVersion = $script:PackageVersionOverrides['Microsoft.Identity.Client']
    if (!(AddIdentityPackageType -packageName "Microsoft.Identity.Client" -edition $msalEdition -Version $msalPreferredVersion)) {
        write-error "unable to add package"
        return $false
    }
    $abstractionsPreferredVersion = $script:PackageVersionOverrides['Microsoft.IdentityModel.Abstractions']
    if (!(AddIdentityPackageType -packageName "Microsoft.IdentityModel.Abstractions" -edition $abstractionsEdition -Version $abstractionsPreferredVersion)) {
        write-error "unable to add package"
        return $false
    }

    if (!(Initialize-MsalDependencyAssemblies -Edition $abstractionsEdition)) {
        if ($script:MsalDependencyStatus) {
            Write-Error $script:MsalDependencyStatus
        }
        return $false
    }

    return $true
}

get-msalLibrary

# IMPORTANT: On first run, leave the following Invoke-Expression uncommented so the KustoObj class definition loads into the session.
# After Microsoft.Identity.Client types are available, you may comment it out temporarily for static analysis/linting.
# When troubleshooting, always re-enable it before rerunning the script. (toggle partner: line below marked 2 of 2.)
# comment next line after microsoft.identity.client type has been imported into powershell session to troubleshoot 1 of 2
invoke-expression @'

class KustoObj {
    hidden [string]$identityPackageLocation
    hidden [object]$authenticationResult
    [string]$AuthMode
    hidden [string]$PreferredAuthMode
    hidden [Microsoft.Identity.Client.ConfidentialClientApplication] $confidentialClientApplication = $null
    [string]$clientId
    hidden [string]$clientSecret
    [string]$Cluster
    [bool]$ClusterResolved = $false
    [string]$Database
    [bool]$FixDuplicateColumns
    [bool]$Force
    [string]$Headers
    [int]$Limit
    [string]$ManagedIdentityClientId
    [hashtable]$parameters
    hidden [Microsoft.Identity.Client.PublicClientApplication] $publicClientApplication = $null
    [bool]$PipeLine
    [string]$Query
    hidden [string]$redirectUri
    [bool]$RemoveEmptyColumns
    hidden [object]$Result = $null
    [object]$ResultObject = $null
    [object]$ResultTable = $null
    [string]$ResultFile
    [string]$Script
    [string]$Table
    [string]$tenantId
    [string]$SubscriptionId
    [string]$AccountId
    [timespan]$ServerTimeout
    hidden [string]$Token
    [bool]$UseAzCliCache
    [bool]$SkipPackageRestore
    hidden [bool]$LegacyFallbackWarned = $false
    hidden [bool]$LegacyRetryAttempted = $false
    [bool]$CreateResults
    [bool]$ViewResults
    [hashtable]$Tables = @{}
    [hashtable]$Functions = @{}
    hidden [hashtable]$FunctionObjs = @{}

    KustoObj() { }
    static KustoObj() { }

    static [KustoObj] Create([hashtable]$context) {
        $instance = [KustoObj]::new()
        $instance.ApplyScriptDefaults($context)
        return $instance
    }

    hidden [void] ApplyScriptDefaults([hashtable]$context) {
        if ($null -eq $context) {
            return
        }

        $this.identityPackageLocation = $context.identityPackageLocation
        $this.AuthMode = $context.AuthMode
        $this.PreferredAuthMode = $context.AuthMode
        $this.clientId = $context.clientId
        $this.clientSecret = $context.clientSecret
        $this.Cluster = $context.Cluster
        $this.Database = $context.Database
        $this.FixDuplicateColumns = [bool]$context.FixDuplicateColumns
        $this.Force = [bool]$context.Force
        $this.Headers = $context.Headers
        $this.Limit = $context.Limit
        $this.ManagedIdentityClientId = $context.ManagedIdentityClientId
        $this.parameters = if ($null -ne $context.Parameters) { $context.Parameters } else { @{} }
        $this.PipeLine = [bool]$context.PipeLine
        $this.Query = $context.Query
        $this.redirectUri = $context.redirectUri
        $this.RemoveEmptyColumns = [bool]$context.RemoveEmptyColumns
        $this.ResultFile = $context.ResultFile
        $this.Script = $context.Script
        $this.Table = $context.Table
        $this.tenantId = $context.tenantId
    $this.SubscriptionId = $context.SubscriptionId
    $this.AccountId = $context.AccountId
        $this.ServerTimeout = $context.ServerTimeout
        $this.UseAzCliCache = [bool]$context.UseAzCliCache
        $this.SkipPackageRestore = [bool]$context.SkipPackageRestore
        $this.CreateResults = [bool]$context.CreateResults
        $this.ViewResults = [bool]$context.ViewResults

        if ($null -eq $this.parameters) {
            $this.parameters = @{}
        }
    }

    [void] ClearResults() {
        $this.ResultObject = $null
        $this.ResultTable = $null
    }

    [KustoObj] CreateResultTable() {
        $this.ResultTable = [collections.arraylist]@()
        $columns = @{ }

        if (!$this.ResultObject.tables) {
            write-warning "run query first"
            return $this.Pipe()
        }

        foreach ($column in ($this.ResultObject.tables[0].columns)) {
            try {
                [void]$columns.Add($column.ColumnName, $null)
            }
            catch {
                write-warning "$($column.ColumnName) already added"
            }
        }

        $resultModel = New-Object -TypeName PsObject -Property $columns
        $rowCount = 0

        foreach ($row in ($this.ResultObject.tables[0].rows)) {
            $count = 0
            $resultCopy = $resultModel.PsObject.Copy()

            foreach ($column in ($this.ResultObject.tables[0].columns)) {
                #write-verbose "createResultTable: procesing column $count"
                $resultCopy.($column.ColumnName) = $row[$count++]
            }

            write-verbose "createResultTable: processing row $rowCount columns $count"
            $rowCount++

            [void]$this.ResultTable.add($resultCopy)
        }
        $this.ResultTable = $this.RemoveEmptyResults($this.ResultTable)
        return $this.Pipe()
    }

    [KustoObj] Exec([string]$query) {
        $this.Query = $query
        $this.Exec()
        $this.Query = $null
        return $this.Pipe()
    }

    [KustoObj] Exec() {
        $startTime = get-date
        $this

        if (!$this.Limit) {
            $this.Limit = 10000
        }

        if (!$this.Script -and !$this.Query) {
            Write-Warning "-script and / or -query should be set. exiting"
            return $this.Pipe()
        }

        if (!$this.Cluster -or !$this.Database) {
            Write-Warning "-cluster and -database have to be set once. exiting"
            return $this.Pipe()
        }

        if ($this.Query) {
            write-host "table:$($this.Table) query:$($this.Query.substring(0, [math]::min($this.Query.length,512)))" -ForegroundColor Cyan
        }

        if ($this.Script) {
            write-host "script:$($this.Script)" -ForegroundColor Cyan
        }

        if ($this.Table -and $this.Query.startswith("|")) {
            $this.Query = $this.Table + $this.Query
        }

        $this.ResultObject = $this.Post($null)

        if ($this.ResultObject.Exceptions) {
            write-warning ($this.ResultObject.Exceptions | out-string)
            $this.ResultObject.Exceptions = $null
        }

        if ($this.ViewResults -or $this.CreateResults) {
            $this.CreateResultTable()
            if ($this.ViewResults) {
                write-host ($this.ResultTable | out-string)
            }
        }

        if ($this.ResultFile) {
            out-file -FilePath $this.ResultFile -InputObject  ($this.ResultObject | convertto-json -Depth 99)
        }

        $primaryResult = $this.ResultObject | where-object TableKind -eq PrimaryResult

        if ($primaryResult) {
            write-host ($primaryResult.columns | out-string)
            write-host ($primaryResult.Rows | out-string)
        }

        if ($this.ResultObject.tables) {
            write-host "results: $($this.ResultObject.tables[0].rows.count) / $(((get-date) - $startTime).TotalSeconds) seconds to execute" -ForegroundColor DarkCyan
            if ($this.ResultObject.tables[0].rows.count -eq $this.limit) {
                write-warning "results count equals limit $($this.limit). results may be incomplete"
            }
        }
        else {
            write-warning "bad result: error:"#$($error)"
        }
        return $this.Pipe()
    }

    [KustoObj] ExecFunctionWithTableName([string]$function) {
        $functionObj = ($this.FunctionObjs.getEnumerator() | where-object Name -imatch $function).Value

        if (!$function -or !$functionObj -or $functionObj.parameters.length -lt 1) {
            write-warning "verify function '$function' and number of parameters '$($functionObj.parameters)'"
        }
        else {
            write-host "function:$function$($functionObj.parameters)" -foregroundcolor cyan
        }

        if ($this.Table) {
            $this.Exec([string]::Format("{0}('{1}')", $function, $this.Table))
        }
        else {
            write-warning "table not set"
        }
        return $this.Pipe()
    }

    [KustoObj] ExecFunction([string]$function, [array]$parameters) {
        if ($parameters) {
            $this.Exec([string]::Format("{0}('{1}')", $function, $parameters -join "','"))
        }
        else {
            $this.Exec([string]::Format("{0}()", $function))
        }
        return $this.Pipe()
    }

    [KustoObj] ExecScript([string]$script, [hashtable]$parameters) {
        $this.Script = $script
        $this.parameters = $parameters
        $this.ExecScript()
        $this.Script = $null
        return $this.Pipe()
    }

    [KustoObj] ExecScript([string]$script) {
        $this.Script = $script
        $this.ExecScript()
        $this.Script = $null
        return $this.Pipe()
    }

    [KustoObj] ExecScript() {
        if ($this.Script.startswith('http')) {
            $destFile = "$pwd\$([io.path]::GetFileName($this.Script))" -replace '\?.*', ''

            if (!(test-path $destFile)) {
                Write-host "downloading $($this.Script)" -foregroundcolor green
                invoke-webRequest $this.Script -outFile  $destFile
            }
            else {
                Write-host "using cached script $($this.Script)"
            }

            $this.Script = $destFile
        }

        if ((test-path $this.Script)) {
            $this.Query = (Get-Content -raw -Path $this.Script)
        }
        else {
            write-error "unknown script:$($this.Script)"
            return $this.Pipe()
        }

        $this.Exec()
        return $this.Pipe()
    }

    [void] ExportCsv([string]$exportFile) {
        $this.CreateResultTable()
        [io.directory]::createDirectory([io.path]::getDirectoryName($exportFile))
        $this.ResultTable | export-csv -notypeinformation $exportFile
    }

    [void] ExportJson([string]$exportFile) {
        $this.CreateResultTable()
        [io.directory]::createDirectory([io.path]::getDirectoryName($exportFile))
        $this.ResultTable | convertto-json -depth 99 | out-file $exportFile
    }

    [string] FixColumns([string]$sourceContent) {
        if (!($this.fixDuplicateColumns)) {
            return $sourceContent
        }

    [hashtable]$tempTable = @{ }
    $columnMatches = [regex]::Matches($sourceContent, '"ColumnName":"(?<columnName>.+?)"', 1)

    foreach ($match in $columnMatches) {
            $matchInfo = $match.Captures[0].Groups['columnName']
            $column = $match.Captures[0].Groups['columnName'].Value
            $newColumn = $column
            $increment = $true
            $count = 0

            while ($increment) {
                try {
                    [void]$tempTable.Add($newColumn, $null)
                    $increment = $false

                    if ($newColumn -ne $column) {
                        write-warning "replacing $column with $newColumn"
                        return $this.FixColumns($sourceContent.Substring(0, $matchInfo.index) `
                                + $newColumn `
                                + $sourceContent.Substring($matchInfo.index + $matchinfo.Length))
                    }

                }
                catch {
                    $count++
                    $newColumn = "$($column)_$($count)"
                    $error.Clear()
                }
            }
        }
        return $sourceContent
    }

    [void] Import() {
        if ($this.Table) {
            $this.Import($this.Table)
        }
        else {
            write-warning "set table name first"
            return
        }
    }

    [KustoObj] Import([string]$table) {
        if (!$this.ResultObject.Tables) {
            write-warning 'no results to import'
            return $this.Pipe()
        }

        [object]$results = $this.ResultObject.Tables[0]
        [string]$formattedHeaders = "("

        foreach ($column in ($results.Columns)) {
            $formattedHeaders += "['$($column.ColumnName)']:$($column.DataType.tolower()), "
        }

        $formattedHeaders = $formattedHeaders.trimend(', ')
        $formattedHeaders += ")"

        [text.StringBuilder]$csv = New-Object text.StringBuilder

        foreach ($row in ($results.rows)) {
            $csv.AppendLine($row -join ',')
        }

        $this.Exec(".drop table ['$table'] ifexists")
        $this.Exec(".create table ['$table'] $formattedHeaders")
        $this.Exec(".ingest inline into table ['$table'] <| $($csv.tostring())")
        return $this.Pipe()
    }

    [KustoObj] ImportCsv([string]$csvFile, [string]$table, [string]$headers) {
        $this.Headers = $headers
        $this.Table = $table
        $this.ImportCsv($csvFile)
        return $this.Pipe()
    }

    [KustoObj] ImportCsv([string]$csvFile, [string]$table) {
        $this.Table = $table
        $this.ImportCsv($csvFile)
        return $this.Pipe()
    }

    [KustoObj] ImportCsv([string]$csvFile) {
        if (!(test-path $csvFile) -or !$this.Table) {
            write-warning "verify importfile: $csvFile and import table: $($this.Table)"
            return $this.Pipe()
        }

        # not working
        #POST https://help.kusto.windows.net/v1/rest/ingest/Test/Logs?streamFormat=Csv HTTP/1.1
        #[string]$csv = Get-Content -Raw $csvFile -encoding utf8
        #$this.Post($csv)

        $sr = new-object io.streamreader($csvFile)
        [string]$tempHeaders = $sr.ReadLine()
        [text.StringBuilder]$csv = New-Object text.StringBuilder

        while ($sr.peek() -ge 0) {
            $csv.AppendLine($sr.ReadLine())
        }

        $sr.close()
        $formattedHeaderList = @{ }
        [string]$formattedHeaders = "("

        foreach ($header in ($tempHeaders.Split(',').trim())) {
            $columnCount = 0
            if (!$header) { $header = 'column' }
            [string]$normalizedHeader = $header.trim('`"').Replace(" ", "_")
            $normalizedHeader = [regex]::Replace($normalizedHeader, "\W", "")
            $uniqueHeader = $normalizedHeader

            while ($formattedHeaderList.ContainsKey($uniqueHeader)) {
                $uniqueHeader = $normalizedHeader + ++$columnCount
            }

            $formattedHeaderList.Add($uniqueHeader, "")
            $formattedHeaders += "['$($uniqueHeader)']:string, "
        }

        $this.Headers = $formattedHeaders
        $formattedHeaders = $formattedHeaders.trimend(', ')
        $formattedHeaders += ")"

        #$this.Exec(".drop table ['$($this.Table)'] ifexists")
        $this.Exec(".create table ['$($this.Table)'] $formattedHeaders")
        $this.Exec(".ingest inline into table ['$($this.Table)'] <| $($csv.tostring())")
        return $this.Pipe()
    }

    [KustoObj] ImportJson([string]$jsonFile) {
        [string]$csvFile = [io.path]::GetTempFileName()
        try {
            ((Get-Content -Path $jsonFile) | ConvertFrom-Json) | Export-CSV $csvFile -NoTypeInformation
            write-host "using $csvFile"

            if (!(test-path $jsonFile) -or !$this.Table) {
                write-warning "verify importfile: $csvFile and import table: $($this.Table)"
                return $this.Pipe()
            }
            $this.ImportCsv($csvFile)
            return $this.Pipe()
        }
        finally {
            write-host "deleting $csvFile"
            [io.file]::Delete($csvFile)
        }
    }

    [KustoObj] ImportJson([string]$jsonFile, [string]$table) {
        $this.Table = $table
        $this.ImportJson($jsonFile)
        return $this.Pipe()
    }

    [bool] Logon([string]$resourceUrl) {
        [int]$expirationRefreshMinutes = 15
        [int]$expirationMinutes = 0
        write-host "logon($resourceUrl)" -foregroundcolor green

        if (!$resourceUrl) {
            write-warning "-resourceUrl required. example: https://{{ kusto cluster }}.kusto.windows.net"
            return $false
        }

        if ($this.authenticationResult) {
            try {
                $expirationMinutes = $this.authenticationResult.ExpiresOn.Subtract((get-date)).TotalMinutes
            }
            catch {
                $expirationMinutes = 0
            }
        }
        write-verbose "token expires in: $expirationMinutes minutes"

        if (!$this.Force -and ($expirationMinutes -gt $expirationRefreshMinutes)) {
            write-verbose "token valid: $($this.authenticationResult.ExpiresOn). use -force to force logon"
            return $true
        }

        if ($this.AuthMode -eq 'KustoSdk') {
            if ($this.LogonKustoSdk($resourceUrl)) {
                return $true
            }

            if (!$this.LegacyFallbackWarned -and $this.PreferredAuthMode -eq 'KustoSdk') {
                write-warning "Kusto SDK authentication unavailable. Falling back to legacy MSAL authentication for this session."
                $this.LegacyFallbackWarned = $true
            }

            $this.AuthMode = 'Legacy'
        }

        #return $this.LogonMsal($resourceUrl, @("$resourceUrl/kusto.read", "$resourceUrl/kusto.write"))
        return $this.LogonMsal($resourceUrl, @("$resourceUrl/user_impersonation"))
    }

    hidden [bool] LogonKustoSdk([string]$resourceUrl) {
        try {
            if (!(Get-KustoSdkLibrary -SkipRestore:$this.SkipPackageRestore)) {
                return $false
            }

            $builderType = Get-KustoSdkType @('Kusto.Data.KustoConnectionStringBuilder', 'Microsoft.Azure.Kusto.Data.KustoConnectionStringBuilder')

            if (!$builderType) {
                write-warning 'LogonKustoSdk: unable to resolve KustoConnectionStringBuilder type. Ensure the Kusto SDK assemblies are accessible.'
                return $false
            }

            try {
                $builder = [Activator]::CreateInstance($builderType, $resourceUrl)
            }
            catch {
                write-warning "LogonKustoSdk: failed to create KustoConnectionStringBuilder. $($_.Exception.Message)"
                return $false
            }

            if ($this.Database) {
                try {
                    $builder['Initial Catalog'] = $this.Database
                }
                catch {
                    write-warning "LogonKustoSdk: unable to set Initial Catalog on builder. $($_.Exception.Message)"
                }
            }

            try {
                $builder['Application Name for Tracing'] = 'kusto-rest.ps1'
            }
            catch {
                write-verbose "LogonKustoSdk: unable to set Application Name for Tracing. $($_.Exception.Message)"
            }

            $tokenCredentials = $null
            $tokenSource = $null

            $normalizedTenantId = if ([string]::IsNullOrWhiteSpace($this.tenantId) -or $this.tenantId -eq 'common') {
                $null
            }
            else {
                $this.tenantId
            }

            if ($this.clientId -and $this.clientSecret -and $this.tenantId) {
                $providerType = Get-KustoSdkType @('Kusto.Cloud.Platform.Msal.AadApplicationKeyCredentialsProvider')
                if (!$providerType) {
                    write-warning 'LogonKustoSdk: unable to resolve AadApplicationKeyCredentialsProvider type.'
                    return $false
                }

                try {
                    $authorityBaseUrl = 'https://login.microsoftonline.com'
                    $provider = [Activator]::CreateInstance($providerType, 'kusto-rest-appkey', $this.clientId, $this.clientSecret, $authorityBaseUrl, $this.tenantId)
                    $tokenTask = if ($normalizedTenantId) {
                        $provider.GetCredentialsAsync($resourceUrl, $normalizedTenantId)
                    }
                    else {
                        $provider.GetCredentialsAsync($resourceUrl)
                    }
                    $tokenCredentials = $tokenTask.GetAwaiter().GetResult()
                    $tokenSource = 'ServicePrincipal'
                }
                catch {
                    write-warning "LogonKustoSdk: service principal authentication failed. $($_.Exception.Message)"
                    return $false
                }
            }
            elseif ($this.ManagedIdentityClientId) {
                $providerType = Get-KustoSdkType @('Kusto.Cloud.Platform.Msal.AadManagedIdentityTokenCredentialsProvider')
                if (!$providerType) {
                    write-warning 'LogonKustoSdk: unable to resolve AadManagedIdentityTokenCredentialsProvider type.'
                    return $false
                }

                try {
                    $provider = [Activator]::CreateInstance($providerType, $this.ManagedIdentityClientId, 'kusto-rest-managed-identity')
                    $tokenTask = if ($normalizedTenantId) {
                        $provider.GetCredentialsAsync($resourceUrl, $normalizedTenantId)
                    }
                    else {
                        $provider.GetCredentialsAsync($resourceUrl)
                    }
                    $tokenCredentials = $tokenTask.GetAwaiter().GetResult()
                    $tokenSource = 'ManagedIdentity'
                }
                catch {
                    write-warning "LogonKustoSdk: managed identity authentication failed. $($_.Exception.Message)"
                    return $false
                }
            }
            elseif ($env:IDENTITY_ENDPOINT -or $env:MSI_ENDPOINT) {
                $providerType = Get-KustoSdkType @('Kusto.Cloud.Platform.Msal.AadManagedIdentityTokenCredentialsProvider')
                if (!$providerType) {
                    write-warning 'LogonKustoSdk: unable to resolve system managed identity provider type.'
                    return $false
                }

                try {
                    $provider = [Activator]::CreateInstance($providerType, 'kusto-rest-system-mi')
                    $tokenTask = if ($normalizedTenantId) {
                        $provider.GetCredentialsAsync($resourceUrl, $normalizedTenantId)
                    }
                    else {
                        $provider.GetCredentialsAsync($resourceUrl)
                    }
                    $tokenCredentials = $tokenTask.GetAwaiter().GetResult()
                    $tokenSource = 'SystemManagedIdentity'
                }
                catch {
                    write-warning "LogonKustoSdk: system managed identity authentication failed. $($_.Exception.Message)"
                    return $false
                }
            }

            $azCli = $null
            if (-not $tokenCredentials -or $this.UseAzCliCache) {
                $azCli = Get-Command az -ErrorAction SilentlyContinue
            }

            if (-not $tokenCredentials) {
                if ($azCli) {
                    write-verbose 'LogonKustoSdk: applying Azure CLI token cache authentication.'
                    $providerType = Get-KustoSdkType @('Kusto.Cloud.Platform.Security.AzCliTokenProvider')
                    if ($providerType) {
                        try {
                            $provider = [Activator]::CreateInstance($providerType, @($false))
                            $tokenTask = if ($normalizedTenantId) {
                                $provider.GetCredentialsAsync($resourceUrl, $normalizedTenantId)
                            }
                            else {
                                $provider.GetCredentialsAsync($resourceUrl)
                            }
                            $tokenCredentials = $tokenTask.GetAwaiter().GetResult()
                            if ($tokenCredentials -and $tokenCredentials.TokenValue) {
                                if ($this.ValidateTokenClaims($tokenCredentials.TokenValue, $normalizedTenantId, $this.AccountId, 'AzureCliCache')) {
                                    $tokenSource = 'AzureCliCache'
                                }
                                else {
                                    $tokenCredentials = $null
                                }
                            }
                        }
                        catch {
                            write-warning "LogonKustoSdk: Azure CLI cached-token provider failed. $($_.Exception.Message)"
                            $tokenCredentials = $null
                        }
                    }
                    else {
                        write-verbose 'LogonKustoSdk: AzCliTokenProvider type not available; falling back to direct az invocation.'
                    }

                    if (-not $tokenCredentials) {
                        $cliToken = $this.AcquireAzCliAccessToken($azCli.Source, $resourceUrl, $normalizedTenantId, $this.SubscriptionId, $this.AccountId)
                        if ($cliToken -and $cliToken.TokenValue) {
                            if ($this.ValidateTokenClaims($cliToken.TokenValue, $normalizedTenantId, $this.AccountId, 'AzureCliProcess')) {
                                $tokenCredentials = $cliToken
                                $tokenSource = 'AzureCliProcess'
                            }
                        }
                    }

                    if (-not $tokenCredentials) {
                        write-warning 'LogonKustoSdk: Azure CLI authentication did not return a valid token.'
                    }
                }
                elseif ($this.UseAzCliCache) {
                    write-warning 'LogonKustoSdk: Azure CLI not found on PATH. Attempting legacy fallback.'
                }
                else {
                    write-warning 'LogonKustoSdk: Azure CLI executable not found; skipping CLI authentication.'
                }
            }

            if (-not $tokenCredentials) {
                write-warning 'LogonKustoSdk: no compatible Kusto SDK authentication method was applied.'
                return $false
            }

            if ($this.Database) {
                try {
                    $builder['Initial Catalog'] = $this.Database
                }
                catch {
                    write-warning "LogonKustoSdk: unable to apply Initial Catalog '$($this.Database)'. $($_.Exception.Message)"
                    return $false
                }
            }

            if ($tokenCredentials -and $tokenCredentials.TokenValue) {
                $expiresOn = $null
                try {
                    if ($tokenCredentials.PSObject.Properties.Match('ExpiresOn').Count -gt 0) {
                        $rawExpiration = $tokenCredentials.ExpiresOn
                        if ($null -ne $rawExpiration) {
                            if ($rawExpiration.GetType().Name -eq 'Nullable`1' -and $rawExpiration.PSObject.Properties.Match('HasValue').Count -gt 0) {
                                if ($rawExpiration.HasValue) {
                                    $value = $rawExpiration.Value
                                    if ($value -is [datetimeoffset]) {
                                        $expiresOn = $value.UtcDateTime
                                    }
                                    elseif ($value -is [datetime]) {
                                        $expiresOn = $value.ToUniversalTime()
                                    }
                                }
                            }
                            elseif ($rawExpiration -is [datetimeoffset]) {
                                $expiresOn = $rawExpiration.UtcDateTime
                            }
                            elseif ($rawExpiration -is [datetime]) {
                                $expiresOn = $rawExpiration.ToUniversalTime()
                            }
                            elseif ($rawExpiration -is [string]) {
                                $parseCandidate = $null
                                if ([datetime]::TryParse($rawExpiration, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parseCandidate)) {
                                    $expiresOn = $parseCandidate.ToUniversalTime()
                                }
                            }
                        }
                    }
                }
                catch {
                    write-verbose "LogonKustoSdk: unable to parse token expiration from provider. $($_.Exception.Message)"
                }

                if (-not $expiresOn) {
                    $expiresOn = $this.ResolveTokenExpiration($tokenCredentials.TokenValue)
                }

                $this.authenticationResult = [pscustomobject]@{
                    AccessToken = $tokenCredentials.TokenValue
                    ExpiresOn   = $expiresOn
                    Source      = "KustoSdk::$tokenSource"
                }
                $this.Token = $tokenCredentials.TokenValue
                $this.LegacyRetryAttempted = $false
                return $true
            }

            write-warning 'LogonKustoSdk: token acquisition returned an empty token.'
            return $false
        }
        catch {
            write-warning "LogonKustoSdk: $($_.Exception.Message)"
            $error.Clear()
            return $false
        }
    }

    hidden [pscustomobject] DecodeJwtPayload([string]$token) {
        if ([string]::IsNullOrWhiteSpace($token)) {
            return $null
        }

        try {
            $parts = $token.Split('.')
            if ($parts.Length -lt 2) {
                return $null
            }

            $payload = $parts[1].Replace('-', '+').Replace('_', '/')
            switch ($payload.Length % 4) {
                2 { $payload += '==' }
                3 { $payload += '=' }
                1 { $payload += '===' }
            }

            $bytes = [Convert]::FromBase64String($payload)
            $json = [System.Text.Encoding]::UTF8.GetString($bytes)
            return $json | ConvertFrom-Json
        }
        catch {
            write-verbose "DecodeJwtPayload: unable to parse token payload. $_"
            return $null
        }
    }

    hidden [bool] CompareGuidString([string]$left, [string]$right) {
        try {
            return ([guid]$left).Equals([guid]$right)
        }
        catch {
            return $this.CompareStringInvariant($left, $right)
        }
    }

    hidden [bool] CompareStringInvariant([string]$left, [string]$right) {
        return [string]::Equals($left, $right, [System.StringComparison]::OrdinalIgnoreCase)
    }

    hidden [bool] ValidateTokenClaims([string]$token, [string]$preferredTenantId, [string]$expectedAccountId, [string]$source) {
        $claims = $this.DecodeJwtPayload($token)
        if (!$claims) {
            return $true
        }

        $effectiveTenant = if (![string]::IsNullOrWhiteSpace($preferredTenantId)) {
            $preferredTenantId
        }
        elseif (![string]::IsNullOrWhiteSpace($this.tenantId) -and $this.tenantId -ne 'common') {
            $this.tenantId
        }
        else {
            $null
        }

        if ($effectiveTenant -and $claims.PSObject.Properties.Match('tid').Count -gt 0 -and $claims.tid) {
            if (-not $this.CompareGuidString($claims.tid, $effectiveTenant)) {
                write-warning "ValidateTokenClaims: rejecting $source token because tenant '$($claims.tid)' does not match expected '$effectiveTenant'."
                return $false
            }
        }
        elseif ($effectiveTenant -and -not $claims.PSObject.Properties.Match('tid').Count) {
            write-verbose "ValidateTokenClaims: $source token missing 'tid' claim; skipping tenant validation."
        }

        if ($expectedAccountId) {
            $candidateUpn = @($claims.upn, $claims.preferred_username, $claims.unique_name, $claims.email)
            $candidateUpn = $candidateUpn | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

            if ($candidateUpn -and -not ($candidateUpn | Where-Object { $this.CompareStringInvariant($_, $expectedAccountId) })) {
                $accountSummary = $candidateUpn -join ', '
                write-warning "ValidateTokenClaims: rejecting $source token because account '$accountSummary' does not match expected '$expectedAccountId'."
                return $false
            }
            elseif (-not $candidateUpn) {
                write-verbose "ValidateTokenClaims: $source token missing UPN-related claims; skipping account validation."
            }
        }

        return $true
    }

    hidden [datetime] ResolveTokenExpiration([string]$token) {
        try {
            $claims = $this.DecodeJwtPayload($token)
            if ($claims -and $claims.PSObject.Properties.Match('exp').Count -gt 0 -and $claims.exp) {
                return ([datetimeoffset]::FromUnixTimeSeconds([long]$claims.exp)).UtcDateTime
            }
        }
        catch {
            write-verbose "ResolveTokenExpiration: unable to parse token expiration. $_"
        }

        return (Get-Date).ToUniversalTime().AddMinutes(30)
    }

    hidden [pscustomobject] AcquireAzCliAccessToken([string]$azCliPath, [string]$resourceUrl, [string]$tenantId, [string]$subscriptionId, [string]$accountId) {
        if ([string]::IsNullOrWhiteSpace($azCliPath)) {
            return $null
        }

        $resourceCandidates = @($resourceUrl)
        if ($resourceUrl -notmatch 'https://kusto\.windows\.net') {
            $resourceCandidates += 'https://kusto.kusto.windows.net'
            $resourceCandidates += 'https://kusto.windows.net'
        }

        foreach ($candidate in $resourceCandidates | Where-Object { $_ }) {
            $baseArgs = @('account', 'get-access-token', '--resource', $candidate, '--output', 'json')
            [System.Collections.ArrayList]$argumentSets = @()

            if ($subscriptionId) {
                [void]$argumentSets.Add($baseArgs + @('--subscription', $subscriptionId))
            }
            if ($tenantId) {
                [void]$argumentSets.Add($baseArgs + @('--tenant', $tenantId))
            }
            if ($argumentSets.Count -eq 0) {
                [void]$argumentSets.Add($baseArgs)
            }

            foreach ($args in $argumentSets) {
                try {
                    write-verbose "AcquireAzCliAccessToken: invoking az $($args -join ' ')"
                    $raw = & $azCliPath @args 2>&1
                    $exitCode = $LASTEXITCODE

                    if ($exitCode -ne 0) {
                        write-verbose "AcquireAzCliAccessToken: az exited with code $exitCode for resource $candidate. Output:`n$raw"
                        continue
                    }

                    if ([string]::IsNullOrWhiteSpace($raw)) {
                        continue
                    }

                    $tokenPayload = $raw | ConvertFrom-Json -ErrorAction Stop
                    if (!$tokenPayload) {
                        continue
                    }

                    $accessToken = $tokenPayload.accessToken
                    if ([string]::IsNullOrWhiteSpace($accessToken)) {
                        continue
                    }

                    $effectiveTenant = if (![string]::IsNullOrWhiteSpace($tenantId)) {
                        $tenantId
                    }
                    elseif (![string]::IsNullOrWhiteSpace($this.tenantId) -and $this.tenantId -ne 'common') {
                        $this.tenantId
                    }
                    else {
                        $null
                    }

                    if ($effectiveTenant -and $tokenPayload.PSObject.Properties.Match('tenant').Count -gt 0 -and $tokenPayload.tenant) {
                        if (-not $this.CompareGuidString($tokenPayload.tenant, $effectiveTenant)) {
                            write-warning "AcquireAzCliAccessToken: ignoring token for tenant '$($tokenPayload.tenant)' because it does not match expected tenant '$effectiveTenant'."
                            continue
                        }
                    }

                    if ($subscriptionId -and $tokenPayload.PSObject.Properties.Match('subscription').Count -gt 0 -and $tokenPayload.subscription) {
                        if (-not $this.CompareGuidString($tokenPayload.subscription, $subscriptionId)) {
                            write-warning "AcquireAzCliAccessToken: ignoring token for subscription '$($tokenPayload.subscription)' because it does not match expected '$subscriptionId'."
                            continue
                        }
                    }

                    $expiresOn = $null
                    if ($tokenPayload.PSObject.Properties.Match('expiresOn').Count -gt 0) {
                        $expiresRaw = $tokenPayload.expiresOn
                        if ($expiresRaw) {
                            $parseResult = $null
                            if ([datetime]::TryParse($expiresRaw, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parseResult)) {
                                $expiresOn = $parseResult.ToUniversalTime()
                            }
                            else {
                                try {
                                    $offsetValue = [datetimeoffset]::Parse($expiresRaw, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
                                    $expiresOn = $offsetValue.UtcDateTime
                                }
                                catch {
                                    write-verbose "AcquireAzCliAccessToken: unable to parse expiresOn '$expiresRaw' as DateTimeOffset."
                                }
                            }
                        }
                    }

                    if (-not $expiresOn -and $tokenPayload.PSObject.Properties.Match('expiresIn').Count -gt 0) {
                        $expiresInRaw = $tokenPayload.expiresIn
                        if ($expiresInRaw) {
                            $expiresInValue = 0
                            if ([int]::TryParse($expiresInRaw.ToString(), [ref]$expiresInValue)) {
                                $expiresOn = (Get-Date).ToUniversalTime().AddSeconds($expiresInValue)
                            }
                        }
                    }

                    if (-not $expiresOn) {
                        $expiresOn = $this.ResolveTokenExpiration($accessToken)
                    }

                    if (-not $this.ValidateTokenClaims($accessToken, $effectiveTenant, $accountId, 'AzureCliProcess')) {
                        continue
                    }

                    return [pscustomobject]@{
                        TokenValue = $accessToken
                        ExpiresOn  = $expiresOn
                    }
                }
                catch {
                    write-warning "AcquireAzCliAccessToken: failed to parse Azure CLI response for resource $candidate using args '$($args -join ' ')'. $($_.Exception.Message)"
                }
            }
        }

        return $null
    }

    hidden [bool] LogonMsal([string]$resourceUrl, [string[]]$scopes) {
        try {
            $error.Clear()
            [string[]]$defaultScope = @(".default")
            write-host "logonMsal($resourceUrl,$($scopes | out-string))" -foregroundcolor green

            if ($this.clientId -and $this.clientSecret) {
                [string[]]$defaultScope = @("$resourceUrl/.default")
                [Microsoft.Identity.Client.ConfidentialClientApplicationOptions] $cAppOptions = new-Object Microsoft.Identity.Client.ConfidentialClientApplicationOptions
                $cAppOptions.ClientId = $this.clientId
                $cAppOptions.RedirectUri = $this.redirectUri
                $cAppOptions.ClientSecret = $this.clientSecret
                $cAppOptions.TenantId = $this.tenantId

                [Microsoft.Identity.Client.ConfidentialClientApplicationBuilder]$cAppBuilder = [Microsoft.Identity.Client.ConfidentialClientApplicationBuilder]::CreateWithApplicationOptions($cAppOptions)
                $cAppBuilder = $cAppBuilder.WithAuthority([microsoft.identity.client.azureCloudInstance]::AzurePublic, $this.tenantId)

                if ($global:PSVersionTable.PSEdition -eq "Core") {
                    $cAppBuilder = $cAppBuilder.WithLogging($this.MsalLoggingCallback, [Microsoft.Identity.Client.LogLevel]::Verbose, $true, $true )
                }

                $this.confidentialClientApplication = $cAppBuilder.Build()
                write-verbose ($this.confidentialClientApplication | convertto-json)

                try {
                    write-host "acquire token for client" -foregroundcolor green
                    $this.authenticationResult = $this.confidentialClientApplication.AcquireTokenForClient($defaultScope).ExecuteAsync().Result
                }
                catch [Exception] {
                    write-host "error client acquire error: $_`r`n$($error | out-string)" -foregroundColor red
                    $error.clear()
                }
            }
            else {
                # user creds
                [Microsoft.Identity.Client.PublicClientApplicationBuilder]$pAppBuilder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($this.clientId)
                $pAppBuilder = $pAppBuilder.WithAuthority([microsoft.identity.client.azureCloudInstance]::AzurePublic, $this.tenantId)

                if (!($this.publicClientApplication)) {
                    if ($global:PSVersionTable.PSEdition -eq "Core") {
                        $pAppBuilder = $pAppBuilder.WithDefaultRedirectUri()
                        $pAppBuilder = $pAppBuilder.WithLogging($this.MsalLoggingCallback, [Microsoft.Identity.Client.LogLevel]::Verbose, $true, $true )
                    }
                    else {
                        $pAppBuilder = $pAppBuilder.WithRedirectUri($this.redirectUri)
                    }
                    $this.publicClientApplication = $pAppBuilder.Build()
                }

                write-verbose ($this.publicClientApplication | convertto-json)

                [Microsoft.Identity.Client.IAccount]$account = $this.publicClientApplication.GetAccountsAsync().Result[0]
                #preauth with .default scope
                try {
                    write-host "preauth acquire token silent for account: $account" -foregroundcolor green
                    $this.authenticationResult = $this.publicClientApplication.AcquireTokenSilent($defaultScope, $account).ExecuteAsync().Result
                    if (!$this.authenticationResult) { throw }
                }
                catch [Exception] {
                    write-host "preauth acquire error: $_`r`n$($error | out-string)" -foregroundColor yellow
                    $error.clear()
                    try {
                        write-host "preauth acquire token interactive" -foregroundcolor yellow
                        $this.authenticationResult = $this.publicClientApplication.AcquireTokenInteractive($defaultScope).ExecuteAsync().Result
                        if (!$this.authenticationResult) { throw }
                    }
                    catch [Exception] {
                        write-host "preauth acquire token device" -foregroundcolor yellow
                        $this.authenticationResult = $this.publicClientApplication.AcquireTokenWithDeviceCode($defaultScope, $this.MsalDeviceCodeCallback).ExecuteAsync().Result
                        if (!$this.authenticationResult) { throw }
                    }
                }

                write-host "authentication result: $($this.authenticationResult)"
                $account = $this.publicClientApplication.GetAccountsAsync().Result[0]

                #add kusto scopes after preauth
                if ($scopes) {
                    try {
                        write-host "kusto acquire token silent" -foregroundcolor green
                        $this.authenticationResult = $this.publicClientApplication.AcquireTokenSilent($scopes, $account).ExecuteAsync().Result
                    }
                    catch [Exception] {
                        write-host "kusto acquire error: $_`r`n$($error | out-string)" -foregroundColor red
                        $error.clear()
                    }
                }
            }

            if ($this.authenticationResult) {
                write-host "authenticationResult:$($this.authenticationResult | convertto-json)"
                $this.Token = $this.authenticationResult.AccessToken
                return $true
            }
            return $false
        }
        catch {
            Write-Error "$($error | out-string)"
            return $false
        }
    }

    [Threading.Tasks.Task] MsalDeviceCodeCallback([Microsoft.Identity.Client.DeviceCodeResult] $result) {
        write-host "MSAL Device code result: $($result | convertto-json)"
        return [threading.tasks.task]::FromResult(0)
    }

    [void] MsalLoggingCallback([Microsoft.Identity.Client.LogLevel] $level, [string]$message, [bool]$containsPII) {
        write-verbose "MSAL: $level $containsPII $message"
    }

    [KustoObj] Pipe() {
        if ($this.pipeLine) {
            return $this
        }
        return $null
    }

    hidden [object] Post([string]$body = "") {
        # authorize aad to get token
        if(!($this.ClusterResolved)){
            $this.ClusterResolved = $this.ResolveCluster()
        }

        [string]$kustoHost = $this.cluster
        [string]$kustoResource = 'https://' + $kustoHost
        [string]$csl = "$($this.Query)"

        $this.Result = $null
        $this.ResultObject = $null
        $this.ResultTable = $null
        $this.Query = $this.Query.trim()

        if ($body -and ($this.Table)) {
            $uri = "$kustoResource/v1/rest/ingest/$($this.Database)/$($this.Table)?streamFormat=Csv&mappingName=CsvMapping"
        }
        elseif ($this.Query.startswith('.show') -or !$this.Query.startswith('.')) {
            $uri = "$kustoResource/v1/rest/query"
            $csl = "$($this.Query) | limit $($this.Limit)"
        }
        else {
            $uri = "$kustoResource/v1/rest/mgmt"
        }

        if (!$this.Token -or $this.authenticationResult) {
            if (!($this.Logon($kustoResource))) {
                write-error "unable to acquire token."
                return $error
            }
        }

        $requestId = [guid]::NewGuid().ToString()
        write-verbose "request id: $requestId"

        $header = @{
            'accept'                 = 'application/json'
            'authorization'          = "Bearer $($this.Token)"
            'content-type'           = 'application/json'
            'host'                   = $kustoHost
            'x-ms-app'               = 'kusto-rest.ps1'
            'x-ms-user'              = $env:USERNAME
            'x-ms-client-request-id' = $requestId
        }

        if ($body) {
            $header.Add("content-length", $body.Length)
        }
        else {
            $body = @{
                db         = $this.database
                csl        = $csl
                properties = @{
                    Options    = @{
                        queryconsistency = "strongconsistency"
                        servertimeout    = $this.ServerTimeout.ToString()
                    }
                    Parameters = $this.parameters
                }
            } | ConvertTo-Json
        }

        write-verbose ($header | convertto-json)
        write-verbose $body

        $error.clear()
        try {
            $this.Result = Invoke-WebRequest -Method Post -Uri $uri -Headers $header -Body $body
            write-verbose $this.Result
        }
        catch {
            $errorRecord = $_
            $statusCode = $null
            $exception = $errorRecord.Exception

            try {
                if ($exception -and $exception.Response -and $exception.Response.StatusCode) {
                    $statusCode = [int]$exception.Response.StatusCode
                }
                elseif ($exception -and ($exception | Get-Member -Name 'StatusCode')) {
                    $statusCode = [int]$exception.StatusCode
                }
                elseif ($errorRecord | Get-Member -Name 'StatusCode') {
                    $statusCode = [int]$errorRecord.StatusCode
                }
            }
            catch { }

            $this.Result = $null

            if ($statusCode -eq 401 -and -not $this.LegacyRetryAttempted) {
                write-warning 'Request returned 401 Unauthorized. Retrying with legacy MSAL authentication to prompt for credentials.'
                $this.LegacyRetryAttempted = $true
                $previousAuthMode = $this.AuthMode
                $this.AuthMode = 'Legacy'
                $this.authenticationResult = $null
                $this.Token = $null

                try {
                    if ($this.LogonMsal($kustoResource, @("$kustoResource/user_impersonation"))) {
                        return $this.Post($body)
                    }
                    else {
                        throw
                    }
                }
                finally {
                    if ($previousAuthMode) {
                        $this.AuthMode = $previousAuthMode
                    }
                }
            }

            throw
        }

        if ($error) {
            return $error
        }

        try {
            return ($this.FixColumns($this.Result.content) | convertfrom-json)
        }
        catch {
            write-warning "error converting json result to object. unparsed results in `$this.Result`r`n$error"

            if (!$this.FixDuplicateColumns) {
                write-warning "$this.fixDuplicateColumns = $true may resolve."
            }
            return ($this.Result.content)
        }
    }

    [collections.arrayList] RemoveEmptyResults([collections.arrayList]$sourceContent) {
        if (!$this.RemoveEmptyColumns -or !$sourceContent -or $sourceContent.count -eq 0) {
            return $sourceContent
        }
        $columnList = (Get-Member -InputObject $sourceContent[0] -View Extended).Name
        write-verbose "checking column list $columnList"
        $populatedColumnList = [collections.arraylist]@()

        foreach ($column in $columnList) {
            if (@($sourceContent | where-object $column -ne "").Count -gt 0) {
                $populatedColumnList += $column
            }
        }
        return [collections.arrayList]@($sourceContent | select-object $populatedColumnList)
    }

    [bool] ResolveCluster() {
        if($this.cluster.startswith('https://')) {
            $this.cluster = $this.cluster.substring(8)
        }

        if(!(test-netConnection $this.cluster -p 443).TcpTestSucceeded) {
            write-warning "cluster not reachable:$($this.cluster)"
            if((test-netConnection "$($this.cluster).kusto.windows.net" -p 443).TcpTestSucceeded) {
                $this.cluster += '.kusto.windows.net'
                write-host "cluster reachable:$($this.cluster)" -foregroundcolor green
            }
            else {
                write-warning "cluster not reachable:$($this.cluster)"
                return $false
            }
        }
        return $true
    }

    [KustoObj] SetCluster([string]$cluster) {
        $this.Cluster = $cluster
        return $this.Pipe()
    }

    [KustoObj] SetDatabase([string]$database) {
        $this.Database = $database
        $this.SetTables()
        $this.SetFunctions()
        return $this.Pipe()
    }

    [KustoObj] SetPipe([bool]$enable) {
        $this.PipeLine = $enable
        return $this.Pipe()
    }

    [KustoObj] SetTable([string]$table) {
        $this.Table = $table
        return $this.Pipe()
    }

    [KustoObj] SetFunctions() {
        $this.Functions.Clear()
        $this.FunctionObjs.Clear()
        $this.exec('.show functions')
        $this.CreateResultTable()

        foreach ($function in $this.ResultTable) {
            $this.Functions.Add($function.Name, $function.Name)
            $this.FunctionObjs.Add($function.Name, $function)
        }
        return $this.Pipe()
    }

    [KustoObj] SetTables() {
        $this.Tables.Clear()
        $this.exec('.show tables | project TableName')
        $this.CreateResultTable()

        foreach ($table in $this.ResultTable) {
            $this.Tables.Add($table.TableName, $table.TableName)
        }
        return $this.Pipe()
    }
}

# IMPORTANT: Keep this closing quote uncommented on first run alongside the matching Invoke-Expression above.
# Only comment both lines together after the class has been loaded into the current session for linting convenience.
# comment next line after microsoft.identity.client type has been imported into powershell session to troubleshoot 2 of 2
'@

main