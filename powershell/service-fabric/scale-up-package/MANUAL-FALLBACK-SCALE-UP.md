# Manual Fallback: Service Fabric Primary Node Type Scale-Up

> **When to use this document**: The automated `New-ServiceFabricScaleUpPackage.ps1` same-node-type
> scale-up has stalled, failed partway through, or produced unexpected behavior (e.g. seed nodes
> won't migrate, cluster health degraded, drain stuck in `Disabling` state). This document provides
> the manual recovery path grounded in the official Microsoft Learn procedure:
> [Scale up a Service Fabric cluster primary node type](https://learn.microsoft.com/en-us/azure/service-fabric/service-fabric-scale-up-primary-node-type).

## Key Difference: Same-Node-Type vs. Separate-Node-Type

| Aspect | Same-Node-Type (script default) | Separate-Node-Type (this fallback) |
|---|---|---|
| New subnet | No | Yes |
| New load balancer | No | Yes |
| New public IP | No | Yes |
| New node type name | No (reuses existing) | Yes (new `isPrimary: true` type) |
| Seed migration | Implicit (SF manages) | Explicit (unmark old `isPrimary`, SF migrates seeds) |
| DNS change | No | Yes (swap DNS label to new public IP) |
| Official MS Learn alignment | Partial (simpler variant) | Full alignment |

## Prerequisites

Before starting manual fallback:

1. **Document current state**: Capture cluster health, node status, seed nodes, and any error details.
2. **Connect to the cluster**:

```powershell
$clusterName = "<cluster-fqdn>:19000"
$thumb = "<certificate-thumbprint>"

Connect-ServiceFabricCluster `
    -ConnectionEndpoint $clusterName `
    -KeepAliveIntervalInSec 10 `
    -X509Credential `
    -ServerCertThumbprint $thumb `
    -FindType FindByThumbprint `
    -FindValue $thumb `
    -StoreLocation CurrentUser `
    -StoreName My

Get-ServiceFabricClusterHealth
```

3. **Verify Azure context**:

```powershell
$ctx = Get-AzContext
"Subscription: $($ctx.Subscription.Name) ($($ctx.Subscription.Id))"
```

4. **Gather variables** (substitute your actual values throughout):

```powershell
$resourceGroupName = "<resource-group>"
$clusterName       = "<cluster-name>"
$oldNodeTypeName   = "<existing-node-type>"     # e.g. "nt0vm", "cpsfsprd"
$newNodeTypeName   = "<new-node-type>"           # e.g. "nt1vm" (max 9 chars)
$oldVmssName       = $oldNodeTypeName            # usually same as node type
$newVmssName       = $newNodeTypeName
$certThumbprint    = "<cert-thumbprint>"
$certUrlValue      = "<key-vault-secret-url>"    # e.g. https://mykv.vault.azure.net/secrets/mycert/abc123
$sourceVaultValue  = "<key-vault-resource-id>"   # e.g. /subscriptions/.../Microsoft.KeyVault/vaults/mykv
```

---

## Phase 1: Assess Current State

### 1.1 Check if the automated script left a partial deployment

```powershell
# List all VMSS in the resource group
Get-AzVmss -ResourceGroupName $resourceGroupName | Format-Table Name, Sku, @{N='Capacity';E={$_.Sku.Capacity}} -AutoSize

# Check SF cluster node types
$cluster = Get-AzServiceFabricCluster -ResourceGroupName $resourceGroupName -Name $clusterName
$cluster.NodeTypes | Format-Table Name, IsPrimary, VmInstanceCount, DurabilityLevel -AutoSize

# Check node status
Get-ServiceFabricNode | Format-Table NodeName, NodeType, NodeStatus, IsSeedNode, HealthState -AutoSize
```

### 1.2 Decision point

| Scenario | Action |
|---|---|
| Replacement VMSS exists, nodes are Up, old nodes not yet drained | Continue from **Phase 4** (drain old nodes) |
| Replacement VMSS exists but nodes are Down/Error | Delete replacement VMSS, start from **Phase 2** |
| No replacement VMSS, old VMSS still running normally | Start from **Phase 2** |
| Cluster health is Error, system services are unhealthy | **Stop**. Stabilize cluster first before any scale operations |

### 1.3 Clean up any failed partial deployment

If the automated script's replacement VMSS is broken, remove it:

```powershell
# Only if the replacement VMSS from the automated attempt is non-functional
Remove-AzVmss -ResourceGroupName $resourceGroupName -VMScaleSetName "<replacement-vmss-name>" -Force
```

---

## Phase 2: Create New Infrastructure (Separate-Node-Type Pattern)

This follows the [official MS Learn procedure](https://learn.microsoft.com/en-us/azure/service-fabric/service-fabric-scale-up-primary-node-type#deploy-a-new-primary-node-type-with-upgraded-scale-set). You need to create:

- A new subnet in the existing VNet
- A new public IP address
- A new load balancer
- A new VMSS with the upgraded VM SKU
- A new node type definition on the SF cluster resource (`isPrimary: true`)

### 2.1 Obtain Key Vault references

From Azure Portal → Key Vault → Certificates → Your cluster certificate:

- **Secret Identifier** (certificate URL)
- **X.509 SHA-1 Thumbprint**
- **Key Vault Resource ID** (from Properties blade)

### 2.2 Prepare the ARM template

Use the Microsoft-provided templates as a starting point:
- [Step1-AddPrimaryNodeType.json](https://github.com/microsoft/service-fabric-scripts-and-templates/tree/master/templates/nodetype-upgrade/Step1-AddPrimaryNodeType.json)
- [parameters.json](https://github.com/microsoft/service-fabric-scripts-and-templates/tree/master/templates/nodetype-upgrade/parameters.json)

**Critical**: Ensure that new resource names (subnet, public IP, load balancer, VMSS) are unique
from the originals. These resources will coexist temporarily and the originals are deleted later.

Customize the template for your environment:
- Set `vmNodeType1Size` to your target VM SKU
- Set `vmImageSku1` / `vmImageVersion1` to your target OS
- Set `nt1InstanceCount` to match or exceed the original capacity (minimum 5 for Silver)
- Ensure the new node type has `isPrimary: true`
- Match application ports, ephemeral ports, and gateway ports from the original node type
- Include all required VM extensions (Service Fabric, monitoring, etc.)

### 2.3 Deploy the new node type

```powershell
$templateFilePath = ".\Step1-AddPrimaryNodeType.json"
$parameterFilePath = ".\parameters.json"

# Validate first
Test-AzResourceGroupDeployment `
    -ResourceGroupName $resourceGroupName `
    -TemplateFile $templateFilePath `
    -TemplateParameterFile $parameterFilePath `
    -CertificateThumbprint $certThumbprint `
    -CertificateUrlValue $certUrlValue `
    -SourceVaultValue $sourceVaultValue `
    -Verbose

# Deploy
New-AzResourceGroupDeployment `
    -ResourceGroupName $resourceGroupName `
    -TemplateFile $templateFilePath `
    -TemplateParameterFile $parameterFilePath `
    -CertificateThumbprint $certThumbprint `
    -CertificateUrlValue $certUrlValue `
    -SourceVaultValue $sourceVaultValue `
    -Verbose
```

### 2.4 Verify both node types are healthy

```powershell
Get-ServiceFabricClusterHealth
Get-ServiceFabricNode | Format-Table NodeName, NodeType, NodeStatus, IsSeedNode, HealthState -AutoSize
```

All nodes on **both** node types should show `Up` and `Ok` health state.

---

## Phase 3: Migrate Seed Nodes to the New Node Type

### 3.1 Unmark the original node type as primary

Update the ARM template to set `isPrimary: false` on the original node type definition. Use the
Microsoft-provided [Step2-UnmarkOriginalPrimaryNodeType.json](https://github.com/microsoft/service-fabric-scripts-and-templates/tree/master/templates/nodetype-upgrade/Step2-UnmarkOriginalPrimaryNodeType.json) template or edit your own.

```powershell
$templateFilePath = ".\Step2-UnmarkOriginalPrimaryNodeType.json"

New-AzResourceGroupDeployment `
    -ResourceGroupName $resourceGroupName `
    -TemplateFile $templateFilePath `
    -TemplateParameterFile $parameterFilePath `
    -CertificateThumbprint $certThumbprint `
    -CertificateUrlValue $certUrlValue `
    -SourceVaultValue $sourceVaultValue `
    -Verbose
```

> **Expected duration**: Seed node migration takes significant time. Only one seed node changes at a
> time, and each requires two cluster upgrades (one for addition, one for removal). For 5 seed
> nodes, expect ~10 cluster upgrades. Monitor progress in Service Fabric Explorer.

### 3.2 Monitor seed migration

In Service Fabric Explorer, check the **Is Seed Node** column:
- Original node type nodes (`$oldNodeTypeName`): should transition to `false`
- New node type nodes (`$newNodeTypeName`): should transition to `true`

```powershell
# Monitor seed node status
Get-ServiceFabricNode | Where-Object { $_.IsSeedNode } |
    Format-Table NodeName, NodeType, IsSeedNode, NodeStatus -AutoSize
```

**Do not proceed to Phase 4 until all seed nodes are on the new node type.**

---

## Phase 4: Disable and Remove Old Nodes

### 4.1 Disable nodes on the original node type

```powershell
$nodes = Get-ServiceFabricNode
Write-Host "Disabling nodes on node type: $oldNodeTypeName"

foreach ($node in $nodes) {
    if ($node.NodeType -eq $oldNodeTypeName) {
        Write-Host "  Disabling: $($node.NodeName)"
        Disable-ServiceFabricNode -Intent RemoveNode -NodeName $node.NodeName -Force
    }
}
```

### 4.2 Monitor disable progress

```powershell
# Check status — wait for all to reach Disabled
Get-ServiceFabricNode |
    Where-Object { $_.NodeType -eq $oldNodeTypeName } |
    Format-Table NodeName, NodeStatus, HealthState -AutoSize
```

**For Silver/Gold durability**: Some nodes may stay in `Disabling` state. Check the Details tab in
Service Fabric Explorer. If they show a pending safety check of kind `EnsurePartitionQuorum`
(for infrastructure service partitions), it is **safe to proceed**.

**For Bronze durability**: Wait for **all** nodes to reach `Disabled` state.

### 4.3 Stop data on disabled nodes

```powershell
foreach ($node in $nodes) {
    if ($node.NodeType -eq $oldNodeTypeName) {
        Write-Host "  Stopping data: $($node.NodeName)"
        Start-ServiceFabricNodeTransition -Stop `
            -OperationId (New-Guid) `
            -NodeInstanceId $node.NodeInstanceId `
            -NodeName $node.NodeName `
            -StopDurationInSeconds 10000
    }
}
```

---

## Phase 5: Remove Original Resources

### 5.1 Remove the original VMSS

```powershell
Remove-AzVmss -ResourceGroupName $resourceGroupName -VMScaleSetName $oldVmssName -Force
```

### 5.2 Delete original load balancer and public IP

> **Note**: This step is optional if you're using a Standard SKU public IP and load balancer
> (multiple scale sets can share the same LB).

```powershell
$oldLbName = "LB-<cluster>-$oldNodeTypeName"       # adjust to your naming convention
$oldPublicIpName = "PublicIP-LB-FE-$oldNodeTypeName" # adjust to your naming convention
$newPublicIpName = "PublicIP-LB-FE-$newNodeTypeName"

# Capture DNS settings before deleting
$oldPublicIP = Get-AzPublicIpAddress -Name $oldPublicIpName -ResourceGroupName $resourceGroupName
$primaryDNSName = $oldPublicIP.DnsSettings.DomainNameLabel
$primaryDNSFqdn = $oldPublicIP.DnsSettings.Fqdn

# Delete old LB and IP
Remove-AzResource -ResourceName $oldLbName -ResourceType 'Microsoft.Network/loadBalancers' `
    -ResourceGroupName $resourceGroupName -Force
Remove-AzResource -ResourceName $oldPublicIpName -ResourceType 'Microsoft.Network/publicIPAddresses' `
    -ResourceGroupName $resourceGroupName -Force

# Transfer DNS label to new public IP
$newPublicIP = Get-AzPublicIpAddress -Name $newPublicIpName -ResourceGroupName $resourceGroupName
$newPublicIP.DnsSettings.DomainNameLabel = $primaryDNSName
$newPublicIP.DnsSettings.Fqdn = $primaryDNSFqdn
Set-AzPublicIpAddress -PublicIpAddress $newPublicIP
```

### 5.3 Remove stale node state from the cluster

```powershell
$nodes = Get-ServiceFabricNode
Write-Host "Removing node state for: $oldNodeTypeName"

foreach ($node in $nodes) {
    if ($node.NodeType -eq $oldNodeTypeName) {
        Write-Host "  Removing: $($node.NodeName)"
        Remove-ServiceFabricNodeState -NodeName $node.NodeName -Force
    }
}
```

---

## Phase 6: Clean Up ARM Template

Deploy the final template that removes the old node type definition, old supporting resources, and
updates the cluster management endpoint. Use the Microsoft-provided
[Step3-CleanupOriginalPrimaryNodeType.json](https://github.com/microsoft/service-fabric-scripts-and-templates/tree/master/templates/nodetype-upgrade/Step3-CleanupOriginalPrimaryNodeType.json)
or customize your own.

### 6.1 Template changes required

1. **Update `managementEndpoint`** to reference the new public IP
2. **Remove the original node type** from the `nodeTypes` array
3. **Remove old supporting resources** (old VMSS, old LB, old public IP, old subnet variables)
4. **For Silver+ durability**: Add `applicationDeltaHealthPolicies` to `upgradeDescription` to
   ignore existing `fabric:/System` health errors during the transition:

```json
"upgradeDescription": {
    "forceRestart": false,
    "upgradeReplicaSetCheckTimeout": "10675199.02:48:05.4775807",
    "healthCheckWaitDuration": "00:05:00",
    "healthCheckStableDuration": "00:05:00",
    "healthCheckRetryTimeout": "00:45:00",
    "upgradeTimeout": "12:00:00",
    "upgradeDomainTimeout": "02:00:00",
    "healthPolicy": {
        "maxPercentUnhealthyNodes": 100,
        "maxPercentUnhealthyApplications": 100
    },
    "deltaHealthPolicy": {
        "maxPercentDeltaUnhealthyNodes": 0,
        "maxPercentUpgradeDomainDeltaUnhealthyNodes": 0,
        "maxPercentDeltaUnhealthyApplications": 0,
        "applicationDeltaHealthPolicies": {
            "fabric:/System": {
                "defaultServiceTypeDeltaHealthPolicy": {
                    "maxPercentDeltaUnhealthyServices": 0
                }
            }
        }
    }
}
```

### 6.2 Deploy the cleanup template

```powershell
$templateFilePath = ".\Step3-CleanupOriginalPrimaryNodeType.json"

New-AzResourceGroupDeployment `
    -ResourceGroupName $resourceGroupName `
    -TemplateFile $templateFilePath `
    -TemplateParameterFile $parameterFilePath `
    -CertificateThumbprint $certThumbprint `
    -CertificateUrlValue $certUrlValue `
    -SourceVaultValue $sourceVaultValue `
    -Verbose
```

> **Expected duration**: Up to 2 hours. The upgrade changes InfrastructureService settings,
> requiring node restarts. The `upgradeReplicaSetCheckTimeout` ensures safety checks pass before
> proceeding on each node.

---

## Phase 7: Final Validation

```powershell
# Cluster health should be OK
Get-ServiceFabricClusterHealth

# Only new node type nodes should exist, all Up and Ok
Get-ServiceFabricNode | Format-Table NodeName, NodeType, NodeStatus, IsSeedNode, HealthState -AutoSize

# Verify SF resource in portal shows "Ready" status
$cluster = Get-AzServiceFabricCluster -ResourceGroupName $resourceGroupName -Name $clusterName
$cluster.ClusterState

# Test application connectivity
# (substitute your application's endpoint)
Invoke-WebRequest -Uri "https://<cluster-fqdn>:<port>/" -UseBasicParsing
```

---

## Troubleshooting Common Issues

| Symptom | Cause | Resolution |
|---|---|---|
| Seed nodes won't migrate | Cluster upgrade stuck or health check failing | Check `Get-ServiceFabricClusterUpgrade` for pending safety checks. Resolve unhealthy partitions first. |
| Nodes stuck in `Disabling` | Pending safety check `EnsurePartitionQuorum` | For Silver+ durability, this is expected for infrastructure partitions. Safe to proceed if only `EnsurePartitionQuorum` remains. |
| `InboundNatRuleInUse` on VMSS creation | NAT pool conflict between old and new VMSS on same LB | Separate-node-type pattern uses its own LB, avoiding this issue. |
| Deployment validation error `reliabilityLevel` | Instance count too low for reliability level | Silver requires ≥5 nodes, Gold requires ≥7. Match or exceed. |
| `The cluster is not healthy` during deployment | Pre-existing health issues | Run `Get-ServiceFabricClusterHealth -ConsiderWarningAsError $false` and resolve errors before proceeding. |
| New nodes show `Down` after VMSS deployment | SF extension failed or certificate issue | Check VMSS instance view: `Get-AzVmssVM -ResourceGroupName $rg -VMScaleSetName $vmss -InstanceView`. Verify cert URL and thumbprint match cluster config. |
| DNS not resolving after IP swap | DNS propagation delay | Wait 5-10 minutes. Verify with `Resolve-DnsName <fqdn>`. |

---

## References

- [Scale up a Service Fabric cluster primary node type](https://learn.microsoft.com/en-us/azure/service-fabric/service-fabric-scale-up-primary-node-type) — Official MS Learn procedure (this document's primary source)
- [Microsoft-provided ARM templates on GitHub](https://github.com/microsoft/service-fabric-scripts-and-templates/tree/master/templates/nodetype-upgrade) — Step1, Step2, Step3 templates
- [Service Fabric cluster capacity planning](https://learn.microsoft.com/en-us/azure/service-fabric/service-fabric-cluster-capacity) — Durability levels and seed node requirements
- [Add a node type to a cluster](https://learn.microsoft.com/en-us/azure/service-fabric/virtual-machine-scale-set-scale-node-type-scale-out) — Foundational procedure for adding node types
- `New-ServiceFabricScaleUpPackage.ps1` — The automated same-node-type approach (use when possible; fall back here when it stalls)
