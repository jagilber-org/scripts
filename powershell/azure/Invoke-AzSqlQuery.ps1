<#
.SYNOPSIS
    Tests SQL connectivity to an Azure SQL PaaS database.

.DESCRIPTION
    Connects to an Azure SQL database using SqlClient and executes a test query.
    Can also verify TCP port connectivity. With the default query of 'select 1',
    a successful result returns '1'.

.NOTES

    File Name  : Invoke-AzSqlQuery.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Invoke-AzSqlQuery.ps1 -database 'myDb' -username 'admin' -password 'P@ss'
#>

[CmdletBinding()]
param(
    $username = "<sql-admin-user>",
    $password = "<sql-admin-password>",
    $database = "testAzureSqlDb",
    $port = 1433,
	$query = "select 1",
	[switch]$checkPorts
)

$VerbosePreference = $DebugPreference = "continue"
$ErrorActionPreference = "continue"
$error.Clear()
$sqlConnection = new-object System.Data.SqlClient.SqlConnection
$databaseFqdn = "$database.database.windows.net"
$sqlConnection.ConnectionString = "Server=tcp:$databaseFqdn,$port;
    Initial Catalog=$database;
    Persist Security Info=False;
    User ID=$username;
    Password=$password;
    MultipleActiveResultSets=False;
    Encrypt=True;
    TrustServerCertificate=False;
    Connection Timeout=30;"

$sqlConnection.Open()
$sqlCmd = new-object System.Data.SqlClient.SqlCommand($query, $sqlConnection)
$sqlReader = $sqlCmd.ExecuteReader()
$Counter = $sqlReader.FieldCount

while ($sqlReader.Read())
{
    for ($i = 0; $i -lt $Counter; $i++)
    {
        write-host $sqlReader.GetName($i), $sqlReader.GetValue($i)
    }
}

$sqlConnection.Close()

if($checkPorts)
{
	Test-NetConnection -ComputerName $databaseFqdn -Port $port
	write-host "checking sql redirect"
	Test-NetConnection -ComputerName $databaseFqdn -Port 11000 # first
	Test-NetConnection -ComputerName $databaseFqdn -Port 11999 # last
}

$VerbosePreference = $DebugPreference = "silentlycontinue"
write-host "finished"
