# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name should be unique for each instance
#            Some thing like 'SampleTest.0', 'SampleTest.1', etc when running in parallel

param ([string]$StartIndex = '1',
        [string]$Param1='Value1'
        )


#Import-Module -Global PSTest -Force -Verbose:$false

Invoke-PsTestPre

#All tests receives $obj as input, which is a key value pairs
#It contains all the inputs, and outputs produced thus far
function Test1 ()
{
    Write-PSUtilLog 'Executing Test1' Yellow
    New-PsTestOutput 'Param2' 'Set from Test1'
}

function Test2 ($Param1='Default', $Param2)
{
    Write-PSUtilLog 'Executing Test2' Yellow
    Write-PSUtilLog "Param1=$Param1"
    Write-PSUtilLog "Param2=$Param2"
}

function TestFail ()
{
    Write-Error 'Failed test case'
}

function OnError ()
{
    Write-PSUtilLog 'OnError' Yellow
}

$InputParameters = @{Param1=$Param1}
Invoke-PsTest -Test 'Test1','Test2','TestFail' -InputParameters $InputParameters  -OnError 'OnError' -Count 2

Invoke-PsTestPost