#
# Module manifest for module 'PSUtil'
#

@{
	ModuleVersion = '1.0'
	GUID = '3e9fa00e-351b-489b-8d3d-dda13dd4f452'
	Author = 'Siva Padisetty'
	NestedModules='test.psm1'
	FunctionsToExport= @(
            'Get-PsTestDefaults',
            'Set-PsTestDefaults',
            'Set-PsTestLogFile',

            'Get-PsTestName',
            'New-PsTestOutput',
            'Test-PsTestMain',

            'Invoke-PsTestPre',
            'Invoke-PsTestPost',
            
            
            'Get-PsTestStatistics', 
            'Get-PsTestPassedResults',
            'Get-PsTestFailedResults',
            'Get-PsTestResults',
            'Convert-PsTestToTableFormat',

            'Invoke-PsTestRandomLoop',
            'Invoke-PsTestLaunchInParallel',
            'Invoke-PsTest'
            )
    AliasesToExport = @(
        'gstat'
        'gfail'
        'gpass'
        'gresults'
    )
}
