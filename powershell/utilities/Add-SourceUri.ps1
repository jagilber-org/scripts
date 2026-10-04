<#
.SYNOPSIS
    Adds source URI to clipboard contents.

.DESCRIPTION
    Updates clipboard contents to append a source URI similar to OneNote paste behavior. Designed to be used with AutoHotkey for automated paste-with-source workflows.

.NOTES

    File Name  : Add-SourceUri.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Add-SourceUri.ps1
    Processes current clipboard HTML content and appends the source URI.
#>

[cmdletbinding()]
param(

)

add-type -assemblyname system.windows.forms

$html = [System.Windows.Forms.Clipboard]::GetText([System.Windows.Forms.TextDataFormat]::Html)
$text = [System.Windows.Forms.Clipboard]::GetText([System.Windows.Forms.TextDataFormat]::Text)

write-verbose $html

if([regex]::isMatch($html,'SourceURL:')){
    $sourceUrl = [regex]::match($html,'(SourceURL:.+)').Groups[1].value
    write-verbose $sourceUrl
}

if($sourceUrl -and !([regex]::isMatch($text,'SourceURL:'))){
    $text = $text + [environment]::newLine + [environment]::newLine + $sourceUrl + [environment]::newLine
    #$text = $html # + [environment]::newLine + [environment]::newLine + $sourceUrl + [environment]::newLine
    write-verbose $text
    [System.Windows.Forms.Clipboard]::SetText($text)
}
