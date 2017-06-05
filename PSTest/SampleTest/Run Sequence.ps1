param ($Name)

echo $Name
$host.ui.RawUI.WindowTitle = $Name

if ($Name.Length -eq 0) {
    Import-Module -Global PsUtil -Force -Verbose:$false
    Import-Module -Global PSTest -Force -Verbose:$false

    Remove-Item $PSScriptRoot\output\* -ea 0 -Force -Recurse
    md $PSScriptRoot\output -ea 0
    cd $PSScriptRoot\output
}

Write-Verbose 'Executing Run'

$InputParameterSets = @(
  @{Param1='Param1-Value1'
        numerator=1
        denominator=1
        ParameterSetRepeat=1 # number of times all test should be repeated with this set.
    },
    @{Param1='Param1-Value2'
        numerator=1
        denominator=0
    }
)

$tests = @(
    @{ 
        Test = "..\Test1.ps1"
        ParallelCount = 2
        TestRepeat = 3
        DisableAutoShellExit = $false
        OutputKeys = @('InstanceId') 
    }
    "..\Test Fail.ps1"
)

function OnError()
{
    Write-Verbose 'Executing OnError'
}

Invoke-PsTest -Test $tests -InputParameters $InputParameterSets  -OuterRepeat 1 -OnError 'OnError' 

gstat

Convert-PsTestToTableFormat    
