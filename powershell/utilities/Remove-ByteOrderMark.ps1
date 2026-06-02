<#
.SYNOPSIS
    Removes Byte Order Mark from UTF-encoded files.

.DESCRIPTION
    Cleans BOM characters from the start of UTF-encoded files. BOM can affect use of iwr script | iex patterns. Converts files with BOM to UTF-8 without BOM.

.NOTES

    File Name  : Remove-ByteOrderMark.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Remove-ByteOrderMark.ps1 -path 'C:\scripts' -extensionFilter '*.ps1'
    Removes BOM from all .ps1 files in the specified directory.
#>

[CmdletBinding()]
param(
    $path = (get-location).path,
    $extensionFilter = "*.ps1",
    [switch]$listOnly,
    [switch]$saveAsAscii,
    [switch]$force
)

$Utf8NoBom = New-Object Text.UTF8Encoding($False)

function main()
{
    foreach($file in get-childitem -Path $path -recurse -filter $extensionFilter)
    {
        $hasBom = has-bom -file $file
        if($hasBom -or $saveAsAscii -or $force)
        {
            if($hasBom)
            {
                write-host "file has bom: $($file.fullname)" -ForegroundColor Yellow
            }

            if(!$listOnly)
            {
                write-warning "re-writing file without bom: $($file.fullname)"
                $content = Get-Content $file.fullname -Raw

                if($saveAsAscii)
                {
                    out-file -InputObject $content -Encoding ascii -FilePath ($file.fullname)
                }
                else
                {
                    [System.IO.File]::WriteAllLines($file.fullname, $content, $Utf8NoBom)
                }
            }
        }
        else
        {
            write-host "file does *not* have bom: $($file.fullname)" -ForegroundColor Green
        }
    }
}

function has-bom($file)
{
    [Byte[]]$bom = Get-Content -Encoding Byte -ReadCount 4 -TotalCount 4 -Path $file.fullname

    foreach ($encoding in [text.encoding]::GetEncodings().GetEncoding())
    {
        $preamble = $encoding.GetPreamble()

        if ($preamble)
        {
            foreach ($i in 0..$preamble.Length)
            {
                if ($preamble[$i] -ne $bom[$i])
                {
                    continue
                }
                elseif ($i -eq $preable.Length)
                {
                    return $true
                }
            }
        }
    }

    return $false
}

main
