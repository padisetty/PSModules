param ($Name)

echo $Name
$host.ui.RawUI.WindowTitle = $Name

if ($Name.Length -eq 0) {
    Import-Module -Global PSTest -Force -Verbose:$false
    . "$PSScriptRoot\Common Setup.ps1"

    Remove-Item $PSScriptRoot\output\* -ea 0 -Force -Recurse
    md $PSScriptRoot\output -ea 0
    cd $PSScriptRoot\output
}

Write-Verbose 'Executing Run'

$InputParameterSets = @(
        @{Param1='Param1-Value1'
        numerator=1
        denominator=1
        },
        @{Param1='Param1-Value2'
        numerator=1
        denominator=0
        }
        )
$tests = @(
    "$PSScriptRoot\Test1.ps1"
    "$PSScriptRoot\Test2.ps1"
    "$PSScriptRoot\Test Fail.ps1"
)

function OnError()
{
    Write-Verbose 'Executing OnError'
}

Invoke-PsTest -Test $tests -InputParameters $InputParameterSets  -Count 1 -OnError 'OnError'

gstat

Convert-PsTestToTableFormat    
