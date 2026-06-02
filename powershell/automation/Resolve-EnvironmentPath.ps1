<#
.SYNOPSIS
    Resolves a path to a directory or file on the local system using current directory and PATH environment variables.

.DESCRIPTION
    Searches for a specified item by checking the current directory, then iterating through all
    directories in the PATH environment variable. Supports environment variable expansion in the
    input path. Returns the fully resolved path if found, or null with a warning if not found.

.NOTES

    File Name  : Resolve-EnvironmentPath.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.PARAMETER item
    The file or directory name to resolve. Defaults to the current working directory. Supports
    environment variable notation (e.g., %USERPROFILE%\tools).

.EXAMPLE
    .\Resolve-EnvironmentPath.ps1 -item nuget
    Searches for 'nuget' in the current directory and all PATH directories.

.EXAMPLE
    .\Resolve-EnvironmentPath.ps1 -item "code.cmd"
    Resolves the full path to the VS Code command-line launcher.

.LINK
    https://github.com/jagilber-org/scripts
#>
[CmdletBinding()]
param(
    $item = (get-location).path
)

function resolve-envPath($item)
{
    write-host "resolving $item"
    $item = [environment]::ExpandEnvironmentVariables($item)
    $sepChar = [io.path]::DirectorySeparatorChar

    if($result = Get-Item $item -ErrorAction SilentlyContinue)
    {
        return $result.FullName
    }

    $paths = [collections.arraylist]@($env:Path.Split(";"))
    [void]$paths.Add([io.path]::GetDirectoryName($MyInvocation.ScriptName))

    foreach ($path in $paths)
    {
        if($result = Get-Item ($path.trimend($sepChar) + $sepChar + $item.trimstart($sepChar)) -ErrorAction SilentlyContinue)
        {
            return $result.FullName
        }
    }

    Write-Warning "unable to find $item"
    return $null
}

$result = resolve-envPath $item
write-host "result: $result"
