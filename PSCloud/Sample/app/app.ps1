#Application starting point.

if (gcm 'Set-DisplayResolution' -EA 0)
{
    Set-DisplayResolution -Width 1600 -Height 900 -Force
}

ipmo devutil

configuration myconfigure
{
    ConfigureIEESC disableESC
    {
    }

    ConfigureRemoteDesktop enableRD
    {
    }

    ConfigureServerManager sm
    {
    }

    LocalConfigurationManager
    {
        RebootNodeIfNeeded = $true
    }
}

configuration appConfig
{
    Node $AllNodes.Nodename
    {
        myconfigure myconfig
        {
        }
    }

    if ($AllNodes.Where{$_.Role -like "*FrontEnd*"}.Nodename.Count -gt 0)
    {
        Node $AllNodes.Where{$_.Role -like "*FrontEnd*"}.Nodename
        {
            . $PSScriptRoot\FrontEnd.ps1
        }
    }
    if ($AllNodes.Where{$_.Role -like "*BackEnd*"}.Nodename.Count -gt 0)
    {
        Node $AllNodes.Where{$_.Role -like "*BackEnd*"}.Nodename
        {
            . $PSScriptRoot\BackEnd.ps1
        }
    }
}

appConfig app1
{
}
