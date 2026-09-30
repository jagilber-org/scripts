<#
.SYNOPSIS
    Modifies the Windows desktop heap SharedSection registry value.

.DESCRIPTION
    Adjusts the desktop heap SharedSection registry value to increase non-interactive session limits for Windows services.

.NOTES

    File Name  : Set-DesktopHeap.ps1

    Author     : jagilber

    Disclaimer : Provided AS-IS without warranty.

    Version    : 1.0.0

    Changelog  : 1.0.0 - Version normalization (constitution quality-007/008/009)



.EXAMPLE
    .\Set-DesktopHeap.ps1
    Displays and modifies the desktop heap settings.
#>

[CmdletBinding()]
param()

$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\SubSystems"

$Name = "Windows"

# The critical bit is:
#
# SharedSection=1024,20480,768
# The first number (1024) is the system heap size.
# The second number (20480) is the size for interactive sessions.
# The third number (768) is the size of non-interactive (services) sessions. Note how the third number is 26x smaller than the second.
#    Changing this to: SharedSection=1024,20480,2048
#    Increased the limit of background service processes running from 113 to 270, almost perfectly scaling with the heap size.
#    Pick a value that reflects the maximum number of service processes that you expect to be deployed on the system.
#    Do not make this value larger than necessary, and no larger than 8192, as each service in your system will consume more of a precious resource.
#

$value = "%SystemRoot%\system32\csrss.exe ObjectDirectory=\Windows SharedSection=1024,20480,2048 Windows=On SubSystemType=Windows ServerDll=basesrv,1 ServerDll=winsrv:UserServerDllInitialization,3 ServerDll=sxssrv,4 ProfileControl=Off MaxRequestThreads=16"

if (!(Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
    New-ItemProperty -Path $registryPath -Name $name -Value $value -PropertyType ExpandString -Force | Out-Null
}
else {
    New-ItemProperty -Path $registryPath -Name $name -Value $value -PropertyType ExpandString -Force | Out-Null
}

reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\SubSystems"
