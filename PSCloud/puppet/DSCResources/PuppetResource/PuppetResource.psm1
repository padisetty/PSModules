# Author: Sivaprasad Padisetty
# Copyright 2013, Licensed under Apache License 2.0
#


function Get-TargetResource 
{
     param 
     (      
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Source,

        [parameter(Mandatory = $false)]
        [string]
        $PuppetMaster = ""
     )
     
     $getTargetResourceResult = 
     @{
    	    Source = $Source; 
            PuppetMaster = $PuppetMaster;
      }
  
      $getTargetResourceResult;
}


function Set-TargetResource 
{
     param 
     (      
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Source,

        [parameter(Mandatory = $false)]
        [string]
        $PuppetMaster = ""
     )

    try
    {
        Write-Verbose "$Source"
        if (-not (Test-Path $Source))
        {
            Write-Error "Did not find the path $Source"
            return $false;
        }

        Write-Verbose "$PSScriptRoot\..\.."
        $item = Get-Item ("$PSScriptRoot\..\..")
        Write-Verbose "Searching for puppet*.msi in $($item.FullName)"

        $msi = Get-ChildItem -Path $item.FullName -Filter "puppet*.msi"

        if ($msi.GetType().Name -ne 'FileInfo')
        {
            Write-Error "Puppet setup MSI file is not found in directory $($item.DirectoryName)"
            return $false
        }

        $file = '"' + $msi.FullName + '"'
        Write-Verbose "Installing MSI $file"

        $Error.clear()
        $process = [System.Diagnostics.Process]::Start("msiexec", "/q /i $file")
        $process.WaitForExit()

        if ($process.ExitCode -ne 0)
        {
            write-error "Puppet Setup Failed ExitCode=$($process.ExitCode) Error=$Error"
            return $false
        }

        if (Test-Path "$($item.DirectoryName)\modules")
        {
            Write-Verbose "Copying modules $($item.DirectoryName)\modules to c:\ProgramData\PuppetLabs\puppet\etc\modules"
            robocopy "$($item.DirectoryName)\modules" c:\ProgramData\PuppetLabs\puppet\etc\modules /mir
        }

        Write-Verbose "Applying puppet script file $Source"
        $Error.clear()
        if (!(Test-Path "c:\temp"))
        {
            md "c:\temp"
        }
        & "${env:ProgramFiles(x86)}\Puppet Labs\Puppet\bin\puppet" apply "`"$Source`"" | Out-File c:\temp\x.log
        if ($LastExitCode -ne 0 -or $Error.Count -ne 0)
        {
            Write-Error ("LastExitCode=$LastExitCode Error=$Error")
            return $false
        }

        foreach($line in $(Get-Content c:\temp\x.log))
        {
            Write-Verbose $line
        }
    }
    catch
    {
        Write-Error ("CATCH1: LastExitCode=$LastExitCode $Error $_")
        return $false
    }

    return $true
}


# The Test-TargetResource cmdlet is used to validate if the role or feature is in a state as expected in the instance document.
function Test-TargetResource 
{
     param 
     (      
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Source,

        [parameter(Mandatory = $false)]
        [string]
        $PuppetMaster = ""
     )

    $false;
}

