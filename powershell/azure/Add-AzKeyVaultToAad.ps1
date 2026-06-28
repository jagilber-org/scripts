<#
.SYNOPSIS
    Adds a certificate to Azure Key Vault and optionally registers an Azure AD application with the certificate.

.DESCRIPTION
    Creates or imports a PFX certificate into Azure Key Vault. Can also create an Azure AD application
    registration and associate the certificate for service principal authentication.
    Supports both certificate-only mode and full AAD application provisioning.

.NOTES

    File Name  : Add-AzKeyVaultToAad.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Add-AzKeyVaultToAad.ps1 -certPassword 'P@ssw0rd' -certNameInVault 'myCert' -vaultName 'myVault' -resourceGroup 'myRG'

.LINK
    https://docs.microsoft.com/en-us/azure/key-vault/
#>

[cmdletbinding()]
param(
    [string]$pfxPath = "$($env:temp)\$($adApplicationName).pfx",
    [string]$certPassword, # password that was used to secure the pfx file at the time of export
    [string]$certNameInVault, # cert name in vault, has to be '^[0-9a-zA-Z-]+$' pattern (digits, letters or dashes only, no spaces)
    [string]$vaultName, # has to be unique?
    [string]$resourceGroup,
    [string]$uri, #  a valid formatted URL, not validated for single-tenant deployments used for identification
    [string]$adApplicationName,
    [switch]$noprompt,
    [string]$location = "eastus",
    [string]$certSubject = $adApplicationName,
    [switch]$adApplicationOnly,
    [switch]$certOnly,
    [int]$retryCount = 5
)

$error.Clear()

# authenticate
try
{
    get-command connect-azaccount | Out-Null
}
catch [management.automation.commandNotFoundException]
{
    if ((read-host "az not installed but is required for this script. is it ok to install?[y|n]") -imatch "y")
    {
        write-host "installing minimum required az modules..."
        install-module az.accounts
        install-module az.resources
        install-module az.keyVault
        import-module az.accounts
        import-module az.resources
        import-module az.keyvault
    }
    else
    {
        return 1
    }
}

if (!(@(Get-AzResourceGroup).Count))
{
    connect-azaccount

    if (!(Get-azResourceGroup))
    {
        Write-Warning "unable to authenticate to az. returning..."
        return 1
    }
}

if (!(Get-azResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue))
{
    New-azResourceGroup -Name $resourceGroup -location $location
}

if (Get-azKeyVaultCertificate -vaultname $vaultName -name $certNameInVault -ErrorAction SilentlyContinue)
{
    if ($noprompt -or (read-host "remove existing cert in vault?[y|n]") -imatch "y")
    {
        write-host "removing old cert from existing vault."
        remove-azKeyVaultCertificate -vaultname $vaultName -name $certNameInVault -Force
    }
}

if ((Get-azKeyVault -VaultName $vaultName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue))
{
    if ($noprompt -or (read-host "remove existing vault?[y|n]") -imatch "y")
    {
        write-host "removing old existing vault."
        remove-azKeyVault -VaultName $vaultName -ResourceGroupName $resourceGroup -Force
    }
}

if (!(Get-azKeyVault -VaultName $vaultName -ResourceGroupName $resourceGroup -ErrorAction SilentlyContinue))
{
    write-host "creating new azure rm key vault"
    New-azKeyVault -VaultName $vaultName -ResourceGroupName $resourceGroup -Location $location -EnabledForDeployment -EnabledForTemplateDeployment
}

if (!$certPassword)
{
    $certPassword = (get-credential).Password
}

$securePassword = ConvertTo-SecureString -String $certPassword -Force -AsPlainText

if (!$uri)
{
    $uri = "https://$($env:Computername)/$($adApplicationName)"
}

$cert = $null

if (![IO.File]::Exists($pfxPath))
{
    if (!$certSubject)
    {
        write-host "please provide argument certSubject. exiting"
        exit 1
    }

    if ($certs = (Get-ChildItem Cert:\CurrentUser\My | Where-Object Subject -imatch "CN=$($certSubject)"))
    {
        foreach ($cert in $certs)
        {
            if ($noprompt -or (read-host "remove existing cert from local My store?[y|n]") -imatch "y")
            {
                remove-item -Path "Cert:\CurrentUser\My\$($cert.thumbprint)" -Force
            }
        }
    }

    if ($certs = (Get-ChildItem Cert:\CurrentUser\Root | Where-Object Subject -imatch "CN=$($certSubject)"))
    {
        foreach ($cert in $certs)
        {
            if ($noprompt -or (read-host "remove existing cert from local Root store?[y|n]") -imatch "y")
            {
                remove-item -Path "Cert:\CurrentUser\Root\$($cert.thumbprint)" -Force
            }
        }
    }

    #$cert = New-SelfSignedCertificate -CertStoreLocation "cert:\currentuser\My" -Subject "CN=$($adApplicationName)" -KeyExportPolicy Exportable -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider"
    write-host "installing new self signed cert to cert:\currentuser\my"
    $cert = New-SelfSignedCertificate -CertStoreLocation "cert:\currentuser\My" -Subject "CN=$($certSubject)" -KeyExportPolicy Exportable #-Provider "Microsoft Enhanced RSA and AES Cryptographic Provider"
    $cert

    Export-PfxCertificate -cert $cert -FilePath $pfxPath -Password $securePassword
    write-host "installing new self signed cert to cert:\currentuser\root"
    Import-PfxCertificate -Exportable -Password $securePassword -CertStoreLocation Cert:\CurrentUser\Root -FilePath $pfxPath
}

if (!$adApplicationOnly)
{
    $count = 0
    while ($count -lt $retryCount)
    {
        ipconfig /flushdns
        write-host "$($count) -- sleeping 30 seconds while vault is created and registered in dns"
        start-sleep -Seconds 30
        ping "$($vaultName).vault.azure.net"
        $error.Clear()
        $azurecert = Import-azKeyVaultCertificate -vaultname $vaultName -name $certNameInVault -filepath $pfxpath -password $securePassword

        if (!$error)
        {
            break
        }

        write-verbose ($error | out-string)
        $count++
    }

    $azurecert
    write-host $error | out-string
    $error.Clear()
}

if ($certOnly)
{
    return
}

if ($oldapp = Get-azADApplication -IdentifierUri $uri -ErrorAction SilentlyContinue)
{
    if ($noprompt -or (read-host "remove existing ad application?[y|n]") -imatch "y")
    {
        Remove-azADApplication -ObjectId $oldapp.ObjectId -Force

        if ($sp = get-azADServicePrincipal -ServicePrincipalName $oldapp.applicationid)
        {
            Remove-azADServicePrincipal -ObjectId $sp.ObjectId -Force
        }
    }
}

if ($adApplicationName)
{
    $app = New-azADApplication -DisplayName $adApplicationName -HomePage $uri -IdentifierUris $uri -password $securePassword
    $sp = New-azADServicePrincipal -ApplicationId $app.ApplicationId
    Set-azKeyVaultAccessPolicy -vaultname $vaultName -serviceprincipalname $sp.ApplicationId -permissionstosecrets get
}

$tenantId = (Get-azSubscription).TenantId | Select-Object -Unique
$subscriptionId = (Get-azSubscription).subscriptionid | Select-Object -Unique

if ([io.file]::Exists($pfxPath))
{
    if ($noprompt -or (read-host "remove existing pfx file?[y|n]") -imatch "y")
    {
        write-host "removing existing file: $($pfxPath)"
        [io.file]::Delete($pfxPath)
    }
}

write-output "spn: $($spn | format-list *)"
write-output "application id: $($app.ApplicationId)"
write-output "tenant id: $($tenantId)"
write-output "subscription id: $($subscriptionId)"
write-output "uri: $($uri)"
write-output "cert thumbprint: $($azurecert.Thumbprint)"
write-output "vault id: /subscriptions/$($subscriptionId)/resourceGroups/$($resourceGroup)/providers/Microsoft.KeyVault/vaults/$($vaultName)"
