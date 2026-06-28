# Service Fabric Primary Node Type Scale-Up Package

Generates a complete, cluster-specific deployment package for scaling up a Service Fabric **classic** (VMSS-backed) primary node type. The script discovers the existing topology, clones the VMSS resource definition, and emits everything needed for the customer to execute the scale-up independently.

> This tool targets **classic / traditional** Service Fabric clusters (`Microsoft.ServiceFabric/clusters` backed by your own VMSS, LB, VNet, etc.). It does **not** apply to **Service Fabric managed clusters** (`Microsoft.ServiceFabric/managedClusters`), where Azure owns the underlying resources and scaling is performed through the managed cluster resource.

## What the Script Expects (Minimum Cluster Requirements)

To build a repro environment (or to point the tool at a real cluster), the resource group must contain a **secure, certificate-based classic Service Fabric cluster** with the standard set of supporting Azure resources. The script discovers topology by reading these resources, so all of them must exist and be correctly cross-referenced.

### Required resources

| Resource | ARM type | Why the script needs it |
|----------|----------|--------------------------|
| Service Fabric cluster | `Microsoft.ServiceFabric/clusters` | Source of truth: primary node type, `clusterEndpoint`, `managementEndpoint`, gateway/app/ephemeral ports, durability level, and the `diagnosticsStorageAccountConfig` (sflogs) reference. |
| VMSS (one or more) | `Microsoft.Compute/virtualMachineScaleSets` | The VMSS backing the **primary** node type is cloned. It is matched to the cluster via the **Service Fabric VMSS extension** (`publisher` matching `ServiceFabric`) whose `nodeTypeRef` + `clusterEndpoint` align with the primary node type. A non‑primary node type may have its own VMSS, but the primary one **must** carry the SF extension. |
| Key Vault | `Microsoft.KeyVault/vaults` | Holds the cluster X.509 certificate. The script reads it from the VMSS `osProfile.secrets[0].sourceVault.id` + `vaultCertificates[].certificateUrl`. The Key Vault must be **deployment-enabled** and **colocated** (same region) with the VMSS. |
| Load Balancer + Public IP | `Microsoft.Network/loadBalancers`, `Microsoft.Network/publicIPAddresses` | Discovered from the primary NIC's `loadBalancerBackendAddressPools`. Used to validate connectivity and to wire the replacement VMSS to the existing backend pool. |
| Virtual Network + subnet | `Microsoft.Network/virtualNetworks` | Discovered from the primary NIC `ipConfigurations[].subnet.id`; the subnet address prefix is read for the replacement VMSS. |
| **sflogs** storage account | `Microsoft.Storage/storageAccounts` | The cluster's **support log** account, referenced by `cluster.properties.diagnosticsStorageAccountConfig` (blob/table endpoint). **Required** — every classic cluster has exactly one, created at cluster provisioning. The generated scripts reference it as `SupportLogStorageAccountName`. |

### What is NOT required: the WAD diagnostics storage account

The cold-start confusion here is the difference between **two distinct storage roles**:

- **`sflogs` (support log storage)** — set on the *cluster* resource (`diagnosticsStorageAccountConfig`). **Always present and required.** This is what the script discovers; it is **not** WAD.
- **WAD diagnostics account** — the *separate* account targeted by the legacy **Azure Diagnostics / `IaaSDiagnostics` VMSS extension** (`Microsoft.Azure.Diagnostics`). **This is optional and is being retired.**

The Windows Azure Diagnostics (WAD/LAD) extension was **deprecated and retires March 31, 2026**; new deployments are not supported. Because of this, the script **excludes the `Microsoft.Azure.Diagnostics` extension by default** (see the `-ExcludeExtensions` parameter, default `@('Microsoft.Azure.Diagnostics')`) so the cloned VMSS does not carry it. **A repro cluster does not need a WAD/diagnostics storage account and should not provision one.** Only the cluster-level `sflogs` account is required.

If you are building a repro from a sample template, simply do not add the `IaaSDiagnostics`/`Microsoft.Azure.Diagnostics` extension block (or its associated `applicationDiagnostics` storage account). The cluster will still create the mandatory `sflogs` account.

### Identity and permissions (live mode)

- `az login` / `Connect-AzAccount` to the subscription containing the cluster.
- **Reader** on the resource group is the minimum to discover topology; the script also issues a raw VMSS GET via `Invoke-AzRestMethod` (`api-version=2023-09-01`).
- To later **deploy** the generated template the operator needs **Contributor** (or equivalent write access) on the resource group, plus the cluster certificate to connect to Service Fabric for the drain/cleanup phases.

### Fastest way to stand up a repro — `base-cluster.template.json`

This folder ships a **current, minimal, WAD-free** secure cluster template, [`base-cluster.template.json`](base-cluster.template.json), that provisions exactly the required resources in one deployment: **1 secure single‑primary‑node‑type Service Fabric cluster, 1 VMSS (with the `ServiceFabricNode` extension only), 1 Standard Load Balancer + Standard static public IP, 1 NSG, 1 VNet/subnet, and 1 `sflogs` support‑log storage account.** There is intentionally **no `Microsoft.Azure.Diagnostics`/`IaaSDiagnostics` (WAD) extension and no second diagnostics storage account** — the public Microsoft/Azure-Samples templates are stale on this point and still include retired WAD plumbing.

You supply three certificate/Key Vault values (everything else has working dev defaults):

| Parameter | What to supply |
|-----------|----------------|
| `certificateThumbprint` | Thumbprint of the cluster certificate in Key Vault |
| `certificateUrlValue` | The KV secret URI, e.g. `https://<vault>.vault.azure.net:443/secrets/<name>/<version>` |
| `keyVaultResourceId` | Full resource ID of the **deployment-enabled** Key Vault holding the cert |

A starter parameter file, [`base-cluster.parameters.json`](base-cluster.parameters.json), is included with these values plus `clusterName`/`dnsName` pre-stubbed. It intentionally **omits `adminPassword`** — pass that as a secure string at deploy time, never commit it.

```powershell
# 1. Create the cert in a deployment-enabled Key Vault (same region as the cluster), then:
New-AzResourceGroup -Name 'sf-repro-rg' -Location 'eastus'

# Option A — edit base-cluster.parameters.json, then deploy with the parameter file:
New-AzResourceGroupDeployment `
  -ResourceGroupName 'sf-repro-rg' `
  -TemplateFile '.\base-cluster.template.json' `
  -TemplateParameterFile '.\base-cluster.parameters.json' `
  -adminPassword (Read-Host -AsSecureString 'VM admin password')

# Option B — pass everything inline (no parameter file):
New-AzResourceGroupDeployment `
  -ResourceGroupName 'sf-repro-rg' `
  -TemplateFile '.\base-cluster.template.json' `
  -clusterName 'sfrepro01' `
  -dnsName 'sfrepro01' `
  -certificateThumbprint '<THUMBPRINT>' `
  -certificateUrlValue 'https://<vault>.vault.azure.net:443/secrets/<name>/<ver>' `
  -keyVaultResourceId '/subscriptions/<sub>/resourceGroups/<kvrg>/providers/Microsoft.KeyVault/vaults/<vault>' `
  -adminPassword (Read-Host -AsSecureString 'VM admin password')
```

Once the cluster is healthy, point the generator at it (`-ResourceGroupName 'sf-repro-rg' -ClusterName 'sfrepro01'`) to produce the scale-up package.

> If you instead start from a public sample (e.g. [Azure-Samples `5-VM-Windows-1-NodeTypes-Secure`](https://github.com/Azure-Samples/service-fabric-cluster-templates/tree/master/5-VM-Windows-1-NodeTypes-Secure)), **delete the `IaaSDiagnostics` VMSS extension and its `applicationDiagnostics` storage account** before deploying — they are not needed and rely on the retired WAD agent.

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
| `base-cluster.template.json` | Minimal, current, WAD-free secure SF cluster template for standing up a repro environment (see [Minimum Cluster Requirements](#what-the-script-expects-minimum-cluster-requirements)) |
| `base-cluster.parameters.json` | Starter parameter file for `base-cluster.template.json` (cert/Key Vault values; `adminPassword` supplied at deploy time) |
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
- [Overview of Service Fabric clusters on Azure — cluster components and resources](https://learn.microsoft.com/azure/service-fabric/service-fabric-azure-clusters-overview#cluster-components-and-resources) (the VMSS / LB / public IP / VNet / storage account / Key Vault model the script discovers)
- [Service Fabric security best practices — set up Azure Key Vault](https://learn.microsoft.com/azure/security/fundamentals/service-fabric-best-practices#set-up-azure-key-vault-for-security) and [Service Fabric security (Key Vault colocation)](https://learn.microsoft.com/azure/service-fabric/service-fabric-best-practices-security)
- [Create a Service Fabric cluster Resource Manager template](https://learn.microsoft.com/azure/service-fabric/service-fabric-cluster-creation-create-template) and [sample secure cluster templates](https://github.com/Azure-Samples/service-fabric-cluster-templates)
- [Azure Diagnostics extension (WAD/LAD) overview + migration guidance](https://learn.microsoft.com/azure/azure-monitor/agents/diagnostics-extension-overview#migration-guidance) and [Migrate to Azure Monitor Agent from WAD/LAD](https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-migration-wad-lad) — **WAD retires March 31, 2026**, which is why the diagnostics storage account is no longer required.
- [Service Fabric managed clusters](https://learn.microsoft.com/azure/service-fabric/overview-managed-cluster) (out of scope for this tool)
