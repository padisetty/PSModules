# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel
#     $obj - This is a dictionary, used to pass output values
#            (e.g.) report the metrics back, or pass output values that will be input to subsequent functions

param ([string]$Param1='Value1')


Write-Verbose "Executing Test1, Param1=$Param1"

Write-Verbose "#PsTEST# OutputID=set via #PSTEST"
sleep -Milliseconds 1
#Output values
@{
    'InstanceId' = $Param1
    'HBTime' = '1:04'
}
