#
# Module manifest for module 'PSUtil'
#

@{
	ModuleVersion = '1.0'
	GUID = '3921e73f-3cff-430b-ad06-dfc690d1ed12'
	Author = 'Siva Padisetty'
	NestedModules='dev.psm1', 'common.psm1', 'ssh.psm1', 'string.psm1'
	FunctionsToExport= @(
            'Invoke-PSUtilWait',
            'Get-PSUtilDefaultIfNull',
            'Invoke-PSUtilRetryOnError',
            'Invoke-PSUtilIgnoreError',

            'Get-PSUtilLogFile',
            'Set-PSUtilLogFile',
            'Write-PSUtilLog',
            
            'Get-PSUtilStringFromObject',
            'Get-PSUtilMultiLineStringFromObject',
            'Invoke-PSUtilSleepWithProgress',
            'Compress-PSUtilFolder',
            'Convertto-PS',

            'New-KeyPairs',
            'Add-SSHKnowHosts',
            'Invoke-SSHCommand'

            )
}

