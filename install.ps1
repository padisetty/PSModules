# Author: Siva Padisetty
# Copyright 2014, Licensed under Apache License 2.0
#


foreach ($file in (Get-ChildItem "$PSHOME\Modules" -Directory))
{
    if (!(Test-Path "$($file.FullName)\*"))
    {
        (Get-Item $file.FullName).Delete()
        Write-Verbose "Deleted $($file.FullName)"
    }
}

if (Test-Path "$PSScriptRoot" -PathType Container)
{
    foreach ($file in (Get-ChildItem "$PSScriptRoot" -Directory))
    {
        if (!(Test-Path "$PSHOME\Modules\$($file.Name)"))
        {
            cmd /c mklink /j "$PSHOME\Modules\$($file.Name)" "$($file.FullName)"
        }
    }
}
