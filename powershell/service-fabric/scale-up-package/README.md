# Service Fabric Primary Node Type Scale-Up Package

Generates a complete, cluster-specific deployment package for scaling up a Service Fabric **classic** (VMSS-backed) primary node type. The script discovers the existing topology, clones the VMSS resource definition, and emits everything needed for the customer to execute the scale-up independently.

## Quick Start

### Prerequisites

- PowerShell 7+
- `Az.Accounts` module (live mode only)
- Either:
  - **Live mode**: `az login` / `Connect-AzAccount` to the target subscription
  - **Export mode**: An ARM template export JSON from the customer's resource group (no Azure access needed)

### Generate the Package

**From a live cluster:**

```powershell
.\New-ServiceFabricScaleUpPackage.ps1 `
  -ResourceGroupName 'my-sf-rg' `
  -ClusterName 'my-sf-cluster' `
  -TargetVmSku 'Standard_D8ads_v5' `
  -ReplacementVmssName 'nt0new' `
  -OutputPath '.\scaleup-output'
```

**From an ARM template export (offline / no subscription access):**

```powershell
.\New-ServiceFabricScaleUpPackage.ps1 `
  -TemplateExportPath '.\customer-export.json' `
  -TargetVmSku 'Standard_D4s_v3' `
  -ReplacementVmssName 'nt0new' `
  -OutputPath '.\scaleup-output'
```

### What It Produces

The output folder will contain 6 files:

| File | Purpose |
|------|---------|
| `replacement-vmss.template.json` | ARM template — whole-object clone of existing VMSS with name/SKU/password parameterized |
| `replacement-vmss.parameters.json` | Parameter file — fill in `adminPassword`, review the other 3 values |
| `Test-ScaleUpReadiness.ps1` | Validation script with `-Phase PreFlight`, `PostDeploy`, `PostDrain`, `PostCleanup` |
| `Invoke-DrainOldNodes.ps1` | Drains old nodes in seed-node-aware order (seeds last) |
| `Remove-StaleNodeState.ps1` | Removes old node state after drain completes |
| `RUNBOOK.md` | Step-by-step runbook with cluster-specific topology and commands |

### Customer Execution Flow

The generated `RUNBOOK.md` walks through these phases:

1. **Pre-Flight** — Run `Test-ScaleUpReadiness.ps1 -Phase PreFlight` to verify quota, connectivity, and cluster health
2. **Deploy** — Edit `replacement-vmss.parameters.json` (set password), then deploy the ARM template via Azure Portal, CLI, or PowerShell
3. **Post-Deploy Validation** — Run `Test-ScaleUpReadiness.ps1 -Phase PostDeploy` to verify new VMSS joined the cluster
4. **Drain Old Nodes** — Run `Invoke-DrainOldNodes.ps1` to move workloads off old instances (seed nodes drain last)
5. **Post-Drain Validation** — Run `Test-ScaleUpReadiness.ps1 -Phase PostDrain`
6. **Remove Old VMSS** — Delete the old VMSS from the portal or via `Remove-AzVmss`
7. **Cleanup** — Run `Remove-StaleNodeState.ps1` to clear stale node records from Service Fabric
8. **Post-Cleanup Validation** — Run `Test-ScaleUpReadiness.ps1 -Phase PostCleanup`

### WhatIf / Dry Run

```powershell
.\New-ServiceFabricScaleUpPackage.ps1 `
  -TemplateExportPath '.\export.json' `
  -TargetVmSku 'Standard_D4s_v3' `
  -ReplacementVmssName 'nt0new' `
  -OutputPath '.\out' `
  -WhatIf
```

Shows what would be generated without writing any files.

## Files in This Folder

| File | Description |
|------|-------------|
| `New-ServiceFabricScaleUpPackage.ps1` | The generator script (v2.0.0) |
| `New-ServiceFabricScaleUpPackage.Tests.ps1` | Pester v5 test suite (69 tests) |
| `MANUAL-FALLBACK-SCALE-UP.md` | Manual fallback steps when the same-node-type approach stalls (separate node type path) |
| `README.md` | This file |

## Key Design Decisions

- **Whole-object clone**: The VMSS resource is deep-copied from the raw API/export response and emitted as-is. Only 4 fields are parameterized (name, SKU, instance count, admin password). This preserves every property — zones, security profiles, NIC config, disk encryption, managed identity — without maintaining an explicit property list.
- **ARM expression resolution** (export mode): Nested `parameters()`, `variables()`, `concat()`, and `resourceId()` expressions are recursively resolved so the output template contains concrete values.
- **Read-only property stripping**: `provisioningState`, `uniqueId`, `timeCreated`, `requireGuestProvisionSignal`, and top-level `etag` are recursively removed so the ARM template deploys cleanly.
- **User-assigned identity cleanup**: `principalId` and `clientId` values inside `userAssignedIdentities` entries are stripped and replaced with empty objects `{}` (ARM GET returns these read-only fields; PUT requires empty objects).
- **Inbound NAT pool removal**: `loadBalancerInboundNatPools` references are stripped from all NIC IP configurations. The replacement VMSS cannot share NAT pools with the existing VMSS — ARM creates per-instance NAT rules keyed by pool + instance ID that collide, producing `InboundNatRuleInUse` deployment errors.
- **Seed-node-aware drain ordering**: The drain script orders nodes so seed nodes are drained last, preventing quorum loss.
- **SF module auto-loading**: Generated scripts (drain, cleanup, validation) include Service Fabric module detection and automatic cluster connection using the discovered management endpoint and certificate thumbprint.

## Running Tests

```powershell
Invoke-Pester -Path .\New-ServiceFabricScaleUpPackage.Tests.ps1 -Output Detailed
```

Requires the fixture files at `c:\cases\2605070050002786\0514\` (prod and dev ARM template exports).

## Reference

- [Scale up a Service Fabric cluster primary node type](https://learn.microsoft.com/azure/service-fabric/service-fabric-scale-up-primary-node-type)
