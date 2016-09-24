# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name should be unique for each instance
#            Some thing like 'SampleTest.0', 'SampleTest.1', etc when running in parallel

param ([string]$Param1='Value1', $Obj)

if (! (Test-PSTestExecuting)) {
    Import-Module -Global PSTest -Force -Verbose:$false
    . "$PSScriptRoot\Common Setup.ps1"
}

Write-Verbose 'Executing Test1'
$Obj.'Param2' = 'Set from Test1'

#Write-Error 'x'