param ($Name)

echo $Name
$host.ui.RawUI.WindowTitle = $Name

if (! (Test-PSTestExecuting)) {
    Import-Module -Global PSTest -Force -Verbose:$false

    Remove-Item $PSScriptRoot\output\* -ea 0 -Force -Recurse
    md $PSScriptRoot\output -ea 0
    cd $PSScriptRoot\output
}

Write-Verbose 'Executing Run'

$InputParameters = @{Param1='Run All1'}
$tests = @(
    "$PSScriptRoot\Test1.ps1"
    "$PSScriptRoot\Test2.ps1"
)
Invoke-PsTest -Test $tests -InputParameters $InputParameters  -Count 2

gstat

Convert-PsTestToTableFormat    
