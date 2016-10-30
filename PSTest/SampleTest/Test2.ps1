# You should define before running this script.
#    $name - Name identifies logfile and test name in results
#            When running in parallel, name should be unique for each instance
#            Some thing like 'SampleTest.0', 'SampleTest.1', etc when running in parallel

param ([string]$InstanceId=$InstanceId)


Write-Verbose "Executing Test2, InstanceId=$InstanceId"


