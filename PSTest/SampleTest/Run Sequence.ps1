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

$tests = @(
    @{ 
        PsTest = "..\Add and Divide.ps1"
        PsTestParallelCount = 2
    
        PsTestRepeat = 2
    
        PsTestDisableAutoShellExit = $false
        PsTestOutputKeys = @('InstanceId') 
        #FailBehavior = 'SkipTests'
    }
)

$commonParameters = @{
    PsTestOnFail='..\OnFailure.ps1'
    
    PsTestSuiteRepeat=2 # number of times all test should be repeated with this set.

    PsTestSuiteMaxFail=10 # max failures allowed
    PsTestSuiteMaxConsecutiveFailPerTest=2 #multiple failures in the same test is counted as 1 

    PsTestMaxFail=3 # per test
    PsTestMaxConsecutiveFail=3 # per test

    Param1='Param1-Value1'
    numerator=1
    denominator=0
    CommandId = 'c8fe1c7e-7d49-4310-9807-36876ae7194f'  
    AssociationId = 'be1b31da-0e52-48d1-91e5-c817dc9481e1'
    AutomationExecutionId = 'dfe74621-55ca-11e7-ae09-c1ce8e35670d'
}

Invoke-PsTest -Test $tests -CommonParameters $commonParameters -LogNamePrefix 'sampletest'

#Convert-PsTestToTableFormat    
