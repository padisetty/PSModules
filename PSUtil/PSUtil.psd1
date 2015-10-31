#
# Module manifest for module 'PSUtil'
#

@{
	ModuleVersion = '1.0'
	GUID = '3921e73f-3cff-430b-ad06-dfc690d1ed12'
	Author = 'Siva Padisetty'
	NestedModules='dev.psm1', 'common.psm1'
	FunctionsToExport= @(
            'Invoke-PSUtilWait',
            'Get-PSUtilDefaultIfNull',
            'Invoke-PSUtilRetryOnError',
            'Invoke-PSUtilIgnoreError',
            'Write-PSUtilLog',
            'Set-PSUtilLogFile',
            'Get-PSUtilStringFromObject',
            'Get-PSUtilMultiLineStringFromObject',
            'Invoke-PSUtilSleepWithProgress',
            'Compress-PSUtilFolder'
            )
}

