#Requires -Modules Az.CostManagement, Az.Accounts
<#
.SYNOPSIS
    Comprehensive Azure cost analysis with flexible date ranges, grouping, and export.

.DESCRIPTION
    Unified Azure cost management script that consolidates multiple cost query patterns into
    a single parameterized tool. Supports querying by service, resource group, resource,
    meter, location, and resource type with configurable date ranges and granularity.

    Query modes:
    - Summary:    Total costs for the date range
    - ByService:  Costs grouped by Azure service name
    - ByResource: Costs grouped by individual resource ID
    - ByMeter:    Costs grouped by billing meter (useful for spot VM analysis)
    - ByLocation: Costs grouped by Azure region
    - ByTag:      Costs grouped by tag keys (configurable)
    - All:        Runs all of the above and exports each to CSV

.PARAMETER SubscriptionId
    Azure subscription ID. Defaults to current context.

.PARAMETER StartDate
    Start date for cost query (yyyy-MM-dd). Defaults to 7 days ago.

.PARAMETER EndDate
    End date for cost query (yyyy-MM-dd). Defaults to today.

.PARAMETER Granularity
    Time granularity: Daily, Monthly, or None. Default: Daily.

.PARAMETER QueryMode
    Which cost breakdown to run. Default: All.

.PARAMETER CostType
    ActualCost or Usage. Default: ActualCost.

.PARAMETER TagKeys
    Array of tag key names for ByTag mode. Default: @('Environment', 'Project').

.PARAMETER ResourceTypeFilter
    Filter results to specific resource types (e.g., 'microsoft.compute/virtualmachinescalesets').

.PARAMETER ServiceFilter
    Filter results to specific service names (e.g., 'Virtual Machines').

.PARAMETER OutputPath
    Directory for CSV exports. Defaults to $env:TEMP.

.PARAMETER NoExport
    Skip CSV export; output objects to pipeline only.

.EXAMPLE
    .\Export-AzCostReport.ps1 -QueryMode ByService
    # Today's costs grouped by service

.EXAMPLE
    .\Export-AzCostReport.ps1 -StartDate '2026-04-01' -EndDate '2026-04-15' -QueryMode ByMeter -ServiceFilter 'Virtual Machines'
    # Meter-level breakdown for VMs over 2 weeks

.EXAMPLE
    .\Export-AzCostReport.ps1 -QueryMode All -Granularity Monthly
    # Full cost report with monthly granularity

.NOTES
    Requires PowerShell 7+ and Az.CostManagement module.
    Azure cost data may have 8-24 hour delays.
    Version: 1.0.0
#>
[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [string]$StartDate = (Get-Date).AddDays(-7).ToString('yyyy-MM-dd'),
    [string]$EndDate = (Get-Date).ToString('yyyy-MM-dd'),
    [ValidateSet('Daily', 'Monthly', 'None')]
    [string]$Granularity = 'Daily',
    [ValidateSet('Summary', 'ByService', 'ByResourceGroup', 'ByResource', 'ByMeter', 'ByLocation', 'ByTag', 'ByResourceType', 'All')]
    [string]$QueryMode = 'All',
    [ValidateSet('ActualCost', 'Usage')]
    [string]$CostType = 'ActualCost',
    [string[]]$TagKeys = @('Environment', 'Project'),
    [string]$ResourceTypeFilter,
    [string]$ServiceFilter,
    [string]$OutputPath = $env:TEMP,
    [switch]$NoExport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-AzContext)) {
    Write-Host 'Connecting to Azure...' -ForegroundColor Yellow
    Connect-AzAccount
}

if (-not $SubscriptionId) {
    $SubscriptionId = (Get-AzContext).Subscription.Id
}

if (-not $NoExport-and -not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$scope = "subscriptions/$SubscriptionId"
$dateTag = "$StartDate`_to_$EndDate"
$allResults = @{}

function Invoke-CostQuery {
    param(
        [string]$Label,
        [hashtable[]]$Grouping = @()
    )

    Write-Host "`n=== $Label ===" -ForegroundColor Cyan
    Write-Host "Scope: $scope | Type: $CostType | Range: $StartDate to $EndDate | Granularity: $Granularity" -ForegroundColor Gray

    try {
        $params = @{
            Scope              = $scope
            Type               = $CostType
            Timeframe          = 'Custom'
            TimePeriodFrom     = $StartDate
            TimePeriodTo       = $EndDate
            DatasetGranularity = $Granularity
        }
        if ($Grouping.Count -gt 0) {
            $params['DatasetGrouping'] = $Grouping
        }

        $result = Invoke-AzCostManagementQuery @params

        if (-not $result.Row -or $result.Row.Count -eq 0) {
            Write-Host "No data returned for $Label" -ForegroundColor Yellow
            return @()
        }

        $columns = $result.Column
        $records = foreach ($row in $result.Row) {
            $obj = [ordered]@{}
            for ($i = 0; $i -lt $columns.Count; $i++) {
                $colName = $columns[$i].Name
                $value = if ($i -lt $row.Count) { $row[$i] } else { $null }
                if ($columns[$i].Type -eq 'Number' -and $null -ne $value) {
                    $value = [decimal]$value
                }
                $obj[$colName] = $value
            }
            [PSCustomObject]$obj
        }

        # Apply filters if specified
        if ($ResourceTypeFilter -and ($columns.Name -contains 'ResourceType')) {
            $records = $records | Where-Object { $_.ResourceType -like $ResourceTypeFilter }
        }
        if ($ServiceFilter -and ($columns.Name -contains 'ServiceName')) {
            $records = $records | Where-Object { $_.ServiceName -like $ServiceFilter }
        }

        Write-Host "Returned $($records.Count) records" -ForegroundColor Green
        return $records
    }
    catch {
        Write-Warning "$Label failed: $($_.Exception.Message)"
        return @()
    }
}

function Export-Results {
    param(
        [string]$Name,
        [object[]]$Data
    )
    if ($NoExport -or $Data.Count -eq 0) { return }
    $filePath = Join-Path $OutputPath "AzCost_${Name}_${dateTag}.csv"
    $Data | Export-Csv -Path $filePath -NoTypeInformation
    Write-Host "Exported to: $filePath" -ForegroundColor Green
}

$modes = if ($QueryMode -eq 'All') {
    @('Summary', 'ByService', 'ByResourceGroup', 'ByResource', 'ByMeter', 'ByLocation', 'ByResourceType')
} else {
    @($QueryMode)
}

foreach ($mode in $modes) {
    switch ($mode) {
        'Summary' {
            $data = Invoke-CostQuery -Label 'Cost Summary'
            if ($data) {
                $allResults['Summary'] = $data
                Export-Results -Name 'Summary' -Data $data
            }
        }
        'ByService' {
            $data = Invoke-CostQuery -Label 'Costs by Service' -Grouping @(@{Type = 'Dimension'; Name = 'ServiceName' })
            if ($data) {
                $allResults['ByService'] = $data
                Export-Results -Name 'ByService' -Data $data
                $data | Group-Object ServiceName | Sort-Object { ($_.Group | Measure-Object -Property PreTaxCost -Sum -ErrorAction SilentlyContinue).Sum } -Descending |
                    Select-Object -First 10 | ForEach-Object {
                        Write-Host "  $($_.Name): $($_.Count) records" -ForegroundColor Cyan
                    }
            }
        }
        'ByResourceGroup' {
            $data = Invoke-CostQuery -Label 'Costs by Resource Group' -Grouping @(
                @{Type = 'Dimension'; Name = 'ResourceGroupName' },
                @{Type = 'Dimension'; Name = 'ServiceName' }
            )
            if ($data) {
                $allResults['ByResourceGroup'] = $data
                Export-Results -Name 'ByResourceGroup' -Data $data
            }
        }
        'ByResource' {
            $data = Invoke-CostQuery -Label 'Costs by Resource' -Grouping @(
                @{Type = 'Dimension'; Name = 'ResourceId' },
                @{Type = 'Dimension'; Name = 'ServiceName' },
                @{Type = 'Dimension'; Name = 'ResourceGroupName' }
            )
            if ($data) {
                $allResults['ByResource'] = $data
                Export-Results -Name 'ByResource' -Data $data
            }
        }
        'ByMeter' {
            $data = Invoke-CostQuery -Label 'Costs by Meter' -Grouping @(
                @{Type = 'Dimension'; Name = 'MeterName' },
                @{Type = 'Dimension'; Name = 'ServiceName' },
                @{Type = 'Dimension'; Name = 'ResourceType' }
            )
            if ($data) {
                $allResults['ByMeter'] = $data
                Export-Results -Name 'ByMeter' -Data $data
            }
        }
        'ByLocation' {
            $data = Invoke-CostQuery -Label 'Costs by Location' -Grouping @(
                @{Type = 'Dimension'; Name = 'ResourceLocation' },
                @{Type = 'Dimension'; Name = 'ServiceName' }
            )
            if ($data) {
                $allResults['ByLocation'] = $data
                Export-Results -Name 'ByLocation' -Data $data
            }
        }
        'ByResourceType' {
            $data = Invoke-CostQuery -Label 'Costs by Resource Type' -Grouping @(
                @{Type = 'Dimension'; Name = 'ResourceType' },
                @{Type = 'Dimension'; Name = 'ServiceName' }
            )
            if ($data) {
                $allResults['ByResourceType'] = $data
                Export-Results -Name 'ByResourceType' -Data $data
            }
        }
        'ByTag' {
            $tagGrouping = @($TagKeys | ForEach-Object { @{Type = 'TagKey'; Name = $_ } })
            $tagGrouping += @{Type = 'Dimension'; Name = 'ServiceName' }
            $data = Invoke-CostQuery -Label "Costs by Tags ($($TagKeys -join ', '))" -Grouping $tagGrouping
            if ($data) {
                $allResults['ByTag'] = $data
                Export-Results -Name 'ByTag' -Data $data
            }
        }
    }
}

Write-Host "`n=== COST REPORT COMPLETE ===" -ForegroundColor Magenta
Write-Host "Subscription: $SubscriptionId" -ForegroundColor Gray
Write-Host "Date Range:   $StartDate to $EndDate" -ForegroundColor Gray
Write-Host "Cost Type:    $CostType" -ForegroundColor Gray
Write-Host "Granularity:  $Granularity" -ForegroundColor Gray

if (-not $NoExport) {
    $exported = Get-ChildItem (Join-Path $OutputPath "AzCost_*${dateTag}*") -ErrorAction SilentlyContinue
    if ($exported) {
        Write-Host "`nExported files:" -ForegroundColor Green
        $exported | ForEach-Object {
            Write-Host "  $($_.Name) ($($_.Length) bytes)" -ForegroundColor Cyan
        }
    }
}

Write-Host "`nNote: Azure cost data may have 8-24 hour delays for recent usage." -ForegroundColor Yellow

$allResults
