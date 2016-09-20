
Import-Module -Global PSTest -Force -Verbose:$false

Invoke-PsTestPre

$InputParameters = @{Param1='Run All1'}
Invoke-PsTest -Test "$PSScriptRoot\SampleTest.ps1" -InputParameters $InputParameters  -Count 1

$InputParameters = @{Param1=@('Run All1', 'Run All2')}
#Invoke-PsTestRandomLoop -Test "$PSScriptRoot\SampleTest.ps1" -InputParameters $InputParameters  -Count 1

Invoke-PsTestPost