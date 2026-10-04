<#
.SYNOPSIS
    Generates a self-signed certificate request.

.DESCRIPTION
    Generates a self-signed certificate request (CSR) for RDS and testing deployments with SAN support using certreq.exe.

.NOTES

    File Name  : New-CertificateRequest.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\New-CertificateRequest.ps1 -subject '*.contoso.com'
    Creates a wildcard certificate request for contoso.com.

.EXAMPLE
    .\New-CertificateRequest.ps1 -subject 'remote.contoso.com' -sans @('broker.contoso.com','broker.contoso.lab')
    Creates a certificate request with Subject Alternative Names.
#>

[CmdletBinding()]
param(
    [string]$pfxPassword = "",
    [string]$subject = "", #"*.contoso.com",
    [string[]]$sans = @(),
    [string]$onlineCa = "",
    [string]$outputDir = (get-location)
)

function New-CertificateRequest
{
    param (
        [ValidatePattern("CN=")][string]$subject,
        [string[]]$SANs,
        [string]$outputDir,
        [string]$pfxPassword,
        [string]$OnlineCA = "",
        [string]$CATemplate = "WebServer"
    )

    ### Preparation
    $subjectDomain = $subject.split(',')[0].split('=')[1]
    if ($subjectDomain -match "\*.")
    {
        $subjectDomain = $subjectDomain -replace "\*", "star"
    }

    $CertificateINI = "$($outputDir)\$($subjectDomain).ini"
    $CertificateREQ = "$($outputDir)\$($subjectDomain).req"
    $CertificateRSP = "$($outputDir)\$($subjectDomain).rsp"
    $CertificateCER = "$($outputDir)\$($subjectDomain).cer"
    $CertificatePFX = "$($outputDir)\$($subjectDomain).pfx"

    ### INI file generation
    new-item -type file $CertificateINI -force
    add-content $CertificateINI '[Version]'
    add-content $CertificateINI 'Signature="$Windows NT$"'
    add-content $CertificateINI ''
    add-content $CertificateINI '[NewRequest]'
    add-content $CertificateINI ('Subject="' + $subject + '"')
    add-content $CertificateINI 'exportable=TRUE'
    add-content $CertificateINI 'KeyLength=2048'
    add-content $CertificateINI 'KeySpec=1'
    add-content $CertificateINI 'KeyUsage=0x30'
    add-content $CertificateINI 'MachineKeySet=True'
    add-content $CertificateINI 'ProviderName="Microsoft RSA SChannel Cryptographic Provider"'
    add-content $CertificateINI 'ProviderType=12'
    add-content $CertificateINI 'SMIME=FALSE'

    ### Date Ranges
    add-content $CertificateINI ('NotBefore="' + (get-date).ToShortDateString() + '"')
    ### Expire in 5 years
    add-content $CertificateINI ('NotAfter="' + (get-date).AddYears(5).ToShortDateString() + '"')

    add-content $CertificateINI 'RequestType=Cert'
    add-content $CertificateINI 'HashAlgorithm=sha256'
    add-content $CertificateINI '[EnhancedKeyUsageExtension]'
    add-content $CertificateINI 'OID=1.3.6.1.5.5.7.3.1 ; this is for Server Authentication / Token Signing'

    if ($SANs)
    {
        add-content $CertificateINI '[Extensions]'
        add-content $CertificateINI '2.5.29.17 = "{text}"'

        foreach ($SAN in $SANs)
        {
            add-content $CertificateINI ('_continue_ = "dns=' + $SAN + '&"')
        }
    }

    ### Certificate request generation
    if (test-path $CertificateREQ) {del $CertificateREQ}
    certreq -new $CertificateINI $CertificateREQ

    ### Online certificate request and import
    if ($OnlineCA)
    {
        if (test-path $CertificateCER) {del $CertificateCER}
        if (test-path $CertificateRSP) {del $CertificateRSP}
        certreq -submit -attrib "CertificateTemplate:$CATemplate" -config $OnlineCA $CertificateREQ $CertificateCER

        certreq -accept $CertificateCER
    }

    if($pfxPassword)
    {
        $cleanSubject = $subject.Replace("=","\=").Replace("*","\*")
        $SecurePassword = $pfxPassword | ConvertTo-SecureString -AsPlainText -Force

        Get-ChildItem -Path cert:\LocalMachine\My -Recurse | where-object Subject -imatch $cleansubject | export-PfxCertificate -Password $securePassword -FilePath $CertificatePFX -Force
        $CertificatePFX
    }

    $CertificateINI
    $CertificateREQ
}

if([string]::IsNullOrEmpty($subject))
{
    write-host "supply subject name. can be wildcard. ex: *.contoso.com. exiting"
    return
}

New-CertificateRequest -subject "CN=$($subject)" -SANs $sans -outputDir $outputDir -pfxpassword $pfxPassword -OnlineCA $onlineCa
