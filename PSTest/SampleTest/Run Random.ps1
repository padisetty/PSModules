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

$tests = @(
    "$PSScriptRoot\Test1.ps1"
    "$PSScriptRoot\Test2.ps1"
)

$InputParameters = @{Param1=@('Random 1', 'Random 2')}
Invoke-PsTestRandomLoop -Test $tests -InputParameters $InputParameters  -Count 3 -LogNamePrefix  'Run Random-'

gstat

Convert-PsTestToTableFormat    
