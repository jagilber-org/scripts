<#
.SYNOPSIS
    powershell script to compare regex pattern match strings in two files
.DESCRIPTION
    powershell script to compare regex pattern match strings in two files
.NOTES
   File Name  : regex-file-compare.ps1
   Author     : jagilber
   Version    : 1.0.0
   Changelog  : 1.0.0 - Version normalization from 140926 (constitution quality-007/008/009)
.EXAMPLE
    .\logmanwrapper.ps1 -regexpattern "KB[0-9][0-9][0-9][0-9][0-9][0-9][0-9]" -fileOne c:\temp\test1.txt -fileTwo c:\temp\test2.txt
    deploy all configuration files in default 'configs' or 'configs_templates' folder to local machine using defalut etl output folder of %systemroot%\temp
.PARAMETER regexpattern
    regex pattern to find string matches for compare between two files
.PARAMETER fileOne
    the first text file for compare
.PARAMETER fileTwo
    the second text file for compare

#>

[CmdletBinding()]
Param(
    [parameter(Position=0,Mandatory=$true,HelpMessage="Enter the quoted regex pattern")]
    [string] $regexpattern,
    [parameter(Position=1,Mandatory=$true,HelpMessage="Enter path to first file")]
    [string] $fileOne,
    [parameter(Position=2,Mandatory=$true,HelpMessage="Enter path to second file")]
    [string] $fileTwo
    )

# modify
cls
#$regexPattern = "KB[0-9][0-9][0-9][0-9][0-9][0-9][0-9]"
#$fileOne = "C:\cases\000000000000001\server1\790bf25f-e78a-4592-9a28-52221c287d16\SERVER1_Hotfixes.TXT"
#$fileTwo = "C:\cases\000000000000001\server2\cd3f6d65-2c50-4efe-88ab-9cc549bf39f1\SERVER2_Hotfixes.TXT"
$listOne = @{}
$listTwo = @{}
$listCombined = @{}
$listOneOnly = @{}
$listTwoOnly = @{}

# get all matches from first file
$regex = new-object System.Text.RegularExpressions.Regex($regexPattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
$matchesOne = $regex.Matches([System.IO.File]::ReadAllText($fileOne))


foreach($match in $matchesOne)
{
    $value = $match.Groups[0].Value

    if(!$listOne.Contains($value))
    {
        $value
        $listOne.Add($value,$value)
    }
}


# get all matches from second file
$matchesTwo = $regex.Matches([System.IO.File]::ReadAllText($fileTwo))


foreach($match in $matchesTwo)
{

    $value = $match.Groups[0].Value

    if(!$listTwo.Contains($value))
    {
        $value
        $listTwo.Add($value,$value)
    }
}


# find all matches in common
foreach($item in $listOne.GetEnumerator())
{
    if($listTwo.Contains($item.key))
    {
        if(!$listCombined.ContainsKey($item.Key))
        {
            $listCombined.Add($item.key,$item.value)
        }
    }
    else
    {
        $listOneOnly.Add($item.key,$item.value)
    }
}

foreach($item in $listTwo.GetEnumerator())
{
    if($listOne.Contains($item.Key))
    {
        if(!$listCombined.ContainsKey($item.Key))
        {
            $listCombined.Add($item.Key,$item.Value)
        }
    }
    else
    {
        $listTwoOnly.Add($item.key,$item.value)
    }
}

# list all in common
write-host "*************************************************************"
write-host "Items in both files:$($listCombined.Count)"
write-host "*************************************************************"
foreach($item in $listCombined.GetEnumerator())
{
    $item.Key
}


# list differences from first file
write-host "*************************************************************"
write-host "Items only in first file:$($listOneOnly.Count) out of $($listOne.Count)"
write-host "*************************************************************"
foreach($item in $listOneOnly.GetEnumerator())
{
    $item.Key
}

# list differences from second file
write-host "*************************************************************"
write-host "Items only in second file:$($listTwoOnly.Count) out of $($listTwo.Count)"
write-host "*************************************************************"
foreach($item in $listTwoOnly.GetEnumerator())
{
    $item.Key
}

write-host "*************************************************************"
write-host "Items in both files:$($listCombined.Count)"
write-host "*************************************************************"

# list differences from first file
write-host "*************************************************************"
write-host "Items only in first file:$($listOneOnly.Count) out of $($listOne.Count)"
write-host "*************************************************************"

# list differences from second file
write-host "*************************************************************"
write-host "Items only in second file:$($listTwoOnly.Count) out of $($listTwo.Count)"
write-host "*************************************************************"

write-host "*************************************************************"
write-host "finished"
write-host "*************************************************************"
