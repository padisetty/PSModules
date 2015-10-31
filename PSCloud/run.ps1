# Author: Sivaprasad Padisetty
# Copyright 2013, Licensed under Apache License 2.0
#


$global:VerbosePreference = "Continue"

if (gcm 'Set-DisplayResolution' -EA 0)
{
    Set-DisplayResolution -Width 1600 -Height 900 -Force
}

if (Test-Path "$PSScriptRoot\Modules" -PathType Container)
{
    foreach ($file in (Get-ChildItem "$PSScriptRoot\Modules" -Directory))
    {
        if (!(Test-Path "$PSHOME\Modules\$($file.Name)"))
        {
            cmd /c mklink /j "$PSHOME\Modules\$($file.Name)" "$($file.FullName)"
        }
    }
}


foreach ($file in (Get-ChildItem "$PSHOME\Modules" -Directory))
{
    if (!(Test-Path "$($file.FullName)\*"))
    {
        (Get-Item $file.FullName).Delete()
        Write-Verbose "Deleted $($file.FullName)"
    }
}

<#
if (Test-Path "$PSScriptRoot\Modules" -PathType Container)
{
    if ("$($PSScriptRoot)Modules" -notin ($env:PSModulePath.Split(";")))
    {
        $env:PSModulePath = "$($PSScriptRoot)Modules;" + $env:PSModulePath
        [Environment]::SetEnvironmentVariable("PSModulePath", $env:PSModulePath, "Machine")
    }
}

#>

configuration MultiMainConfiguration
{
    if (Test-Path "$PSScriptRoot\pprun.ps1")
    {
        . "$PSScriptRoot\pprun.ps1"
    }
    if (Test-Path "$PSScriptRoot\psrun.ps1")
    {
        . "$PSScriptRoot\psrun.ps1"
    }
}

Del $PSScriptRoot\config -Recurse -Force -EA 0
MultiMainConfiguration -OutputPath $PSScriptRoot\config -ConfigurationData "$PSScriptRoot\run.psd1"

$computerName = (Get-CimInstance win32_computersystem).Name

if (!(Test-Path "$PSScriptRoot\config\$computerName.MOF"))
{
    $computerName = 'localhost'
}

if (Test-Path "$PSScriptRoot\config\$computerName.meta.mof")
{
    Set-DscLocalConfigurationManager $PSScriptRoot\Config -ComputerName $computerName -Verbose
}

if (Test-Path "$PSScriptRoot\config\$computerName.MOF")
{
    Start-DscConfiguration -Path  $PSScriptRoot\config -ComputerName $computerName -Wait -Verbose -Force 
}
