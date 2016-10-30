# Author: Sivaprasad Padisetty
# Copyright 2013, Licensed under Apache License 2.0
#

trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
Server Manager Configuration.

.DESCRIPTION
To enable or disable ServerManager auto start at the login time.

.PARAMETER enableOnStartup
When true, SM is auto started on login.

.EXAMPLE
    ConfigureServerManager disableServerManager
    {
    }
#>
configuration ConfigureServerManager
{
    param ([boolean] $enableOnStartup = $false)

    if ($enableOnStartup)
    {
        $value = "0"
    }
    else
    {
        $value = "1"
    }

    Registry DisableServerManager
    {
        Key = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\ServerManager"
        ValueName = "DoNotOpenServerManagerAtLogon"
        ValueType = "Dword"
        ValueData = $value
    }
}

<#
.SYNOPSIS
Configure IE ESC.

.DESCRIPTION
Enable or Disable Internet Explorer: Enhanced Security Configuration (ESC).

.PARAMETER enable
When true, IE ESC is on.

.EXAMPLE
    ConfigureIEESC disableIEESC
    {
    }
#>
configuration ConfigureIEESC
{
    param ([boolean] $enable = $false)

    if ($enable)
    {
        $value = "1"
    }
    else
    {
        $value = "0"
    }

    Registry adminkey
    {
        Key = “HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}”
        ValueName = "IsInstalled"
        ValueData = $value
        ValueType = "DWORD"
        Ensure = "Present"
    }

    Registry userkey
    {
        Key = “HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}”
        ValueName = "IsInstalled"
        ValueData = $value
        ValueType = "DWORD"
        Ensure = "Present"
    }
}

<#
.SYNOPSIS
Configure Remote Desktop.

.DESCRIPTION
Enable or Disable Remote Desktop

.PARAMETER enable
When true, Enables Remote Desktop

.EXAMPLE
    ConfigureRemoteDesktop disableRemoteDesktop
    {
    }
#>
configuration ConfigureRemoteDesktop
{
    param ([boolean] $enable = $true)

    if ($enable)
    {
        $value1 = "0"
        $value2 = "1"
        $firewall = "True"
    }
    else
    {
        $value1 = "1"
        $value2 = "0"
        $firewall = "False"
    }

    Registry fDenyTSConnections
    {
        Key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
        ValueName = "fDenyTSConnections"
        ValueData = $value1
        ValueType = "DWORD"
        Ensure = "Present"
    }

    Registry UserAuthentication
    {
        Key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
        ValueName = "UserAuthentication"
        ValueData = $value2
        ValueType = "DWORD"
        Ensure = "Present"
    }

    Script enablefirewall
    {
        GetScript = {$true}

        SetScript = {
            Set-NetFirewallRule -DisplayGroup 'Remote Desktop' -Enabled $using:firewall
        }
        TestScript = {$false}
    }
}

