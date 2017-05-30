# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name maps to unique ID.
#            Some thing like '0', '1', etc when running in parallel
#     $obj - This is a dictionary, used to pass output values
#            (e.g.) report the metrics back, or pass output values that will be input to subsequent functions

param ($numerator, $denominator)


Write-Verbose "#PSTEST# Test Fail.Output1=Test Fail.Output Pre Value1"
Write-Verbose "#PSTEST# foo=bar"

Write-Verbose 'Executing Test Fail (Divide by zero)'
Write-Verbose "Result=$($numerator/$denominator)"

@{
    'Test Fail.Output1' = @{ 'x' = 'y'}
}
