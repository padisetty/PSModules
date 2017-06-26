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
        denominator=0
        CommandId = 'c8fe1c7e-7d49-4310-9807-36876ae7194f'  
        AssociationId = 'be1b31da-0e52-48d1-91e5-c817dc9481e1'
        AutomationExecutionId = 'dfe74621-55ca-11e7-ae09-c1ce8e35670d'
    }
)

$tests = @(
    @{ 
        PsTest = "..\Add and Divide.ps1"
        PsTestParallelCount = 1
        PsTestRepeat = 1
        PsTestDisableAutoShellExit = $false
        PsTestOutputKeys = @('InstanceId') 
        #ErrorBehavior = 'SkipTests'
    }
)


function OnError($PsTestObject)
{
    Write-Verbose 'Error Information:'
}

$commonParameters = @{
#    PsTestOnError='OnError'
    PsTestParameterSetRepeat=1 # number of times all test should be repeated with this set.
    PsTestMaxError=5
}

Invoke-PsTest -Test $tests -ParameterSets $ParameterSets  -CommonParameters $commonParameters

$null = gstat

Convert-PsTestToTableFormat    
