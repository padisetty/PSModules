Import-Module -Global PSTest -Force -Verbose:$false

rm ..\output\* -Recurse -Force -ea 0

Invoke-PsTestLaunchInParallel -PsFileToLaunch '..\Run Sequence.ps1' -ParallelShellCount 2 -TotalCount 3

Convert-PsTestToTableFormat    
