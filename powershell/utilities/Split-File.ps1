<#
.SYNOPSIS
    Splits a large CSV file into smaller parts.

.DESCRIPTION
    Splits a large CSV file into smaller parts by a configurable maximum size in GB using StreamReader and StreamWriter for efficient processing.

.NOTES

    File Name  : Split-File.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Split-File.ps1 -csvPath 'C:\data\large.csv' -maxSizeGb 2
    Splits the CSV file into 2 GB parts.
#>

[CmdletBinding()]
param(
  $maxSizeGb = 1,
  $maxSizeBytes = $maxSizeGb * 1073741824,
  $csvPath = "{input_csv_file}",
  $header = (Get-Content $csvPath -First 1),
  $counter = 0,
  $outputPath = "$csvPath.part$counter.csv",
  [switch]$writeHeader
)

# Use StreamReader for efficient line-by-line processing
$reader = [System.IO.File]::OpenText($csvPath)
# Read header line from file
$firstLine = $reader.ReadLine()
$writer = New-Object System.IO.StreamWriter($outputPath)
if ($writeHeader) {
    $writer.WriteLine($firstLine)
}

# size of csv file in bytes
$csvFileSize = (Get-Item $csvPath).length
# read first 1000 lines and measure time taken and avg size of each line
$lineCount = 0
$startTime = Get-Date
$lineSize = 0
$line = $reader.ReadLine()
while ($line -ne $null -and $lineCount -lt 1000) {
    $lineSize += $line.Length
    $lineCount++
    $line = $reader.ReadLine()
}
$reader.BaseStream.Position = 0 # Reset stream position to the beginning

$endTime = Get-Date
$timeTaken = $endTime - $startTime
$avgLineSize = $lineSize / $lineCount
$avgLineSizeBytes = $avgLineSize #* 2 # Assuming UTF-16 encoding
# write info to console
Write-Host "Total size of file: $csvFileSize bytes"
Write-HOst "max size bytes: $maxSizeBytes bytes"
Write-Host "Time taken to read first 1000 lines: $timeTaken"
Write-Host "Estimated number of lines in file: $($csvFileSize / $avgLineSizeBytes)"
Write-Host "Estimated avg line size: $avgLineSizeBytes bytes"
Write-Host "Estimated number of files to split into: $($csvFileSize / $maxSizeBytes)"
Write-Host "Estimated time to process file: $($timeTaken * ($maxSizeBytes / $avgLineSizeBytes))"

while (($line = $reader.ReadLine()) -ne $null) {
    if ($writer.BaseStream.Length -ge $maxSizeBytes) {
        $writer.Close()
        $counter++
        Write-Host "Splitting file into part $counter ..."
        $outputPath = "$csvPath.part$counter.csv"
        $writer = New-Object System.IO.StreamWriter($outputPath)
        if ($writeHeader) {
            $writer.WriteLine($header)
        }
    }
    $writer.WriteLine($line)
    $writer.Flush()
}

$writer.Close()
$reader.Close()
