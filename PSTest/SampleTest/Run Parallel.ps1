Import-Module -Global PSTest -Force -Verbose:$false
#. "$PSScriptRoot\Common Setup.ps1"

Remove-Item $PSScriptRoot\output\* -ea 0 -Force -Recurse
md $PSScriptRoot\output -ea 0
cd $PSScriptRoot\output


Invoke-PsTestLaunchInParallel -PsFileToLaunch '..\Run Sequence.ps1' -ParallelShellCount 2 -TotalCount 2

Convert-PsTestToTableFormat    
