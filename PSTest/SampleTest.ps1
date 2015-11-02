# You should define before running this script.
#    $name - You can create some thing like '0', '1', '2', '3' etc for each session
param ([string]$name = '0')

Import-Module -Global PSTest -Force

$VerbosePreference = 'Continue'
trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'

cd c:\temp

function Setup ()
{
    Write-PSUtilLog 'Setup ' Yellow

    $obj.Param1 = 'Value1'
    $obj.Param2 = 'Value2'
}

$i = 0
function Cleanup ()
{
    Write-PSUtilLog 'Cleanup ' Yellow
}

function Test1 ($st)
{
    Write-PSUtilLog 'Test1' Yellow
    Write-PSUtilLog "Param st=$st"
    $script:i++
    if ($i -eq 2)
    {
        Write-Error 'Test1 fail for second time around'
    }
}

function Test2 ()
{
    Write-PSUtilLog 'Test2' Yellow
}

function OnError ()
{
    Write-PSUtilLog 'OnError' Yellow
}

Invoke-PsTestRandomLoop -Name $name `
    -Main {
        Cleanup
        Setup
        Test1 "siva"
        Test2
        Cleanup
      }`
    -Parameters @{ 
        ParamA = @('A1', 'A2', 'A3')
        ParamB = @('B1', 'B2', 'B3')
    } `
    -OnError {OnError} `
    -ContinueOnError `
    -MaxCount 3
