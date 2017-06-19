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

$ParameterSets = @(
  @{Param1='Param1-Value1'
        numerator=1
        denominator=1
        PsTestParameterSetRepeat=1 # number of times all test should be repeated with this set.
    }
   <# @{Param1='Param1-Value2'
        numerator=1
        denominator=0
    } #>
)

$tests = @(
    @{ 
        PsTest = "..\Test1.ps1"
        PsTestParallelCount = 2
        PsTestRepeat = 2
        PsTestDisableAutoShellExit = $false
        PsTestOutputKeys = @('Param1', 'InstanceId') 
    }
   # "..\Test Fail.ps1"
)

function OnError()
{
    Write-Verbose 'Executing OnError'
}

$commonParameters = @{
    PsTestOnError='OnError'
    PsTestParameterSetRepeat=1
    PsTestStopOnError=$false
}

Invoke-PsTest -Test $tests -ParameterSets $ParameterSets  -CommonParameters $commonParameters

gstat

Convert-PsTestToTableFormat    
