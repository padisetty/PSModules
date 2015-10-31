# Author: Sivaprasad Padisetty
# Copyright 2013, Licensed under Apache License 2.0
#


function SyncFolder ($source, $destination)
{
    robocopy "`"$source`"" "`"$destination`"" /mir /v | Out-Null
    if ($LastExitCode -ge 8) {
        Write-Error "robocopy failed: LastExitCode=$LastExitCode `"$modulePath`" to `"$destination`""
    }
}

function MountVHD ($VHDPath)
{
    Mount-VHD $VHDPath
    $drive = (Get-DiskImage -ImagePath $VHDPath | Get-Disk | Get-Partition).DriveLetter
    "$($drive):"
    Get-PSDrive | Out-Null # Work around. some times the drive is not mounted
}

function DismountVHD ($VHDPath)
{
    Dismount-VHD $VHDPath
}


function CreateDataVHD ($VHDPath, $ResourceExtensionReferences, $size, $NodeName)
{
    if (Test-Path $VHDPath)
    {
        Dismount-VHD $VHDPath -ErrorAction 0 # incase if it is left mounted from previous run.
    }
    else
    {

        $drive = (New-VHD -path $vhdpath -SizeBytes $size -Dynamic   | `
                        Mount-VHD -Passthru |  get-disk -number {$_.DiskNumber} | Initialize-Disk -PartitionStyle MBR -PassThru | `
                        New-Partition -UseMaximumSize -AssignDriveLetter:$False -MbrType IFS | `
                        Format-Volume -Confirm:$false -FileSystem NTFS -force | get-partition | Add-PartitionAccessPath -AssignDriveLetter -PassThru | get-volume).DriveLetter 

        Dismount-VHD $VHDPath
    }
    $mountPath = mountVHD -vhdpath $VHDPath


    $modules = @()
    $localFolders = @()
    foreach ($resourceExtensionReference in $ResourceExtensionReferences)
    {
        if ($resourceExtensionReference.ReferenceName -like '*:*' -or $resourceExtensionReference.ReferenceName -like '\*') #absolute path specificed
        {
            $localFolders += $resourceExtensionReference.ReferenceName
        }
        elseif (Test-Path ($folder = "$($params["MultiApplicationRoot"])\$($resourceExtensionReference.ReferenceName)"))
        {
            $localFolders += $folder
        }
        else
        {
            $modules += $resourceExtensionReference.ReferenceName
        }
    }

    #copy modules
    $modulePaths = $env:PSModulePath.Split(";")
    foreach ($module in $modules)
    {
        $found = $false
        foreach ($modulePath in $modulePaths)
        {
            if (Test-Path ($modulePath = "$modulePath\$module") -PathType Container)
            {
                $found = $true
                [System.IO.DirectoryInfo] $dinfo = Get-Item $modulePath

                SyncFolder $modulePath "$mountPath\Modules\$($dinfo.Name)"
                break;
            }
        }
        if (!$found)
        {
            Write-Error "Module $module is not found in PSModulePath"
        }
    }

    $multiApplicuationRunPS = ""
    $multiApplicuationRunPP = ""
    $i = 0
    #Copy application folders.
    foreach ($folderToCopy in $localFolders)
    {
        $i = 0
        [System.IO.DirectoryInfo] $dinfo = Get-Item $folderToCopy
        if (!$dinfo)
        {
            Write-Error "The folder $folderToCopy is not found."
        }
        
        SyncFolder $folderToCopy ($destination = "$mountPath\$($dinfo.Name)")
        if (Test-Path "$destination\$($dinfo.Name).ps1")
        {
            $multiApplicuationRunPS += "    . `"`$PSScriptRoot\$($dinfo.Name)\$($dinfo.Name).ps1`"`n"
        }
        if (Test-Path "$destination\$($dinfo.Name).pp")
        {
            $multiApplicuationRunPP += "    Puppet p$i`n    {`n        Source=`"$destination\$($dinfo.Name).pp`"`n    }`n"
        }
    }

    Copy "$($params["MultiRoot"])\run.ps1" "$mountPath\run.ps1"
    
    #create psd1 ConfigurationData file
    $configfile = "$mountPath\run.psd1"
    Write-Verbose "Configuration File=$configfile"

    "@{`n`tAllNodes = @(`n`t`t@{" | Out-File $configfile
    "`t`t`tNodeName=`"$NodeName`""  | Out-File -Append $configfile
    foreach ($param in $params.GetEnumerator())
    {
        "`t`t`t$($param.Key)=`"$($param.Value)`""  | Out-File -Append $configfile
    }
    "`t`t}`n`t)`n}" | Out-File -Append $configfile
    if ($multiApplicuationRunPP.Length -gt 0)
    {
        #Patch and copy the psrun.ps1
        $st = Get-Content "$($params["MultiRoot"])\pprun.ps1" -Raw
        $st.Replace("[Param.MultiApplicuationRun]", $multiApplicuationRunPP) | Out-File "$mountPath\pprun.ps1"

        $configfile = "$mountPath\pprun param.ps1"
        Write-Verbose "Configuration File=$configfile"

        foreach ($param in $params.GetEnumerator())
        {
            "$($param.Key)=$($param.Value)"  | Out-File -Append $configfile
        }
    }
    else
    {
        #Patch and copy the psrun.ps1
        $st = Get-Content "$($params["MultiRoot"])\psrun.ps1" -Raw
        $st.Replace("[Param.MultiApplicuationRun]", $multiApplicuationRunPS) | Out-File "$mountPath\psrun.ps1"
    }

    dismountVHD $VHDPath
}

function RemoveResource ($resdef)
{
    if ($resdef.Type -ne "VMRole")
    {
        Write-Error "Resource type shoud be 'VMRole', in file $file, current value is '$($resource.Type)'"
    }
    $vmname = $resdef.Name 

    $vm = Get-VM | ? Name -eq $vmname 
    if ($vm -ne $null)
    {
        if ($vm.State -ne "off")
        {
            $vm | Stop-VM -Force
        }

        foreach ($file in ($vm | Get-VMHardDiskDrive).Path)
        {
            if (Test-Path $file)
            {
                Dismount-VHD $file -ErrorAction 0 # unmount it, if left mounted
                del $file
            }
        }

        $vm | Remove-VM -Force
        Write-Host "VM $vmname deleted" -ForegroundColor Green
    }
}

function CreateResourceSingleVM ($resdef)
{
    if ($resdef.Type -ne "VMRole")
    {
        Write-Error "Resource type shoud be 'MicrosoftCompute/VMRole', in file $file, current value is '$($resource.Type)'"
    }
    $vmname = $params["MultiVMComputerName"]

    switch ($resdef.IntrinsicSettings.HardwareProfile.VMSize)
    {
        "s" {
            $memorySize = 1GB
            $processorCount = 1
        }
        default {
            Write-Error "Unknown VMSIZE=$($resdef.IntrinsicSettings.HardwareProfile.VMSize), Only supported values are 'S'" 
        }
    }

    $vm = Get-VM | ? Name -eq $vmname 
    if ($vm -ne $null)
    {
        Write-Warning "VM $vmname already present, so skipping to create a new VM"

        foreach ($file in ($vm | Get-VMHardDiskDrive).Path) # in case if previous run did not unmount the drive.
        {
            Dismount-VHD $file -ErrorAction 0
        }
    }
    else
    {
        #Create VHD diff disk
        $file = "$($params["MultiHypervVHDBaseRoot"])\$($resdef.IntrinsicSettings.StorageProfile.OSVirtualHardDiskImage).vhd*"
        $basevhd = Get-ChildItem $file  -File
        if ($basevhd -isnot [System.IO.FileInfo])
        {
            Write-Error "VHD Base file is not present. File=$file"
        }

        $diffvhdpath = "$($params["MultiHypervVHDDiffRoot"])\$($basevhd.Name).diff.$vmname$($basevhd.Extension)"
        if (!(Test-path $diffvhdpath))
        {
            New-VHD -Differencing -ParentPath $basevhd.FullName -path $diffvhdpath > $null
        }

        $path = mountVHD $diffvhdpath 

        if (!(Test-Path "$path\windows\setup\scripts"))
        {
            md "$path\windows\setup\scripts" > $null
        }
        copy "$PSScriptRoot\runonce.cmd" "$path\windows\setup\scripts\setupcomplete.cmd"

        $templatefile = "$($params["MultiApplicationRoot"])\unattend.pstemplate"
        if ( !(Test-Path $templatefile) )
        {
            $templatefile = "$PSScriptRoot\unattend.pstemplate"
        }

        Expand-PSTemplateFile -InPSTemplateFile $templatefile -OutFile "$path\unattend.xml" -params $params
    
        dismountVHD $diffvhdpath
        #Create VM
        $vm = new-vm -VHDPath $diffvhdpath -name $vmname
    }

    Set-VMMemory $vm -DynamicMemoryEnabled $true -StartupBytes $memorySize
    Set-VMProcessor $vm -Count $processorCount

    foreach ($adapter in $resdef.IntrinsicSettings.NetworkProfile.NetworkAdapters)        
    {
        connect-VMNetworkAdapter $vmname -switchName $adapter.NetworkRef
    }

    #Create data disk
    $file = "$($params["MultiHypervVHDDataRoot"])\$vmname Data Disk.vhdx"
    CreateDataVHD -vhdpath $file $resdef.ResourceExtensionReferences -size 1GB -nodeName $vmname

    if ($file -notin (Get-VMHardDiskDrive -VMName $vmname).Path)
    {
        Add-VMHardDiskDrive -Path $file -VMName $vmname
    }

    Start-VM $vmname
    vmconnect localhost $vmname
}

function CreateResource ($resdef)
{
    if ($resdef.Type -ne "VMRole")
    {
        Write-Error "Resource type shoud be 'MicrosoftCompute/VMRole', in file $file, current value is '$($resource.Type)'"
    }

    #$saveVMName = $resdef.Name

    $instanceCount = 1
    if ($resdef.IntrinsicSettings.ScaleOutSettings.InitialInstanceCount)
    {
        $instanceCount = $resdef.IntrinsicSettings.ScaleOutSettings.InitialInstanceCount
    }

    for ($i = 1; $i -le $instanceCount; $i++)
    {
        $global:params["MultiNodeNumber"] = $i

        if ($instanceCount -gt 1)
        {
            #$resdef.Name = "$saveVMName$i"
            $params["MultiVMComputerName"] = "$($resdef.Name)$i"
        }
        else
        {
            $params["MultiVMComputerName"] = $resdef.Name
        }

        CreateResourceSingleVM $resdef
    }

    #$resdef.Name = $saveVMName
}

function ClearResource ()
{
    Get-Disk | ? Model -like 'Virtual Disk*'  | % { Get-DiskImage -DevicePath $_.Path -EA 0} | % { Dismount-VHD $_.ImagePath }

    foreach ($vm in Get-VM)
    {
        if ($vm.State -ne "off")
        {
            $vm | Stop-VM -Force
        }

        foreach ($file in ($vm | Get-VMHardDiskDrive).Path)
        {
            if (Test-Path $file)
            {
                Dismount-VHD $file -ErrorAction 0 # unmount it, if left mounted
                del $file
            }
        }

        $vm | Remove-VM -Force
        Write-Host "VM $vmname deleted" -ForegroundColor Green
    }

    foreach ($file in Get-ChildItem "$($params["MultiHypervVHDDiffRoot"])\*")
    {
        Dismount-VHD $file -EA 0
        del $file 
    }

    foreach ($file in Get-ChildItem "$($params["MultiHypervVHDDataRoot"])\*")
    {
        Dismount-VHD $file -EA 0
        del $file 
    }

    Get-Process vmconnect -EA 0 | Stop-Process -Force
}


############################ PRIVATE FUNCTIONS #######################################