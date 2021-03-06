#
# Module manifest for module 'PSUtil'
#

@{
	ModuleVersion = '1.0'
	GUID = '3921e73f-3cff-430b-ad06-dfc690d1ed12'
	Author = 'Siva Padisetty'
	NestedModules='string.ps1', 'dev.ps1', 'invoke.ps1', 'log.ps1', 'common.ps1', 'ssh.ps1'
	FunctionsToExport= @(
            'Invoke-PSUtilWait',
            'Get-PSUtilDefaultIfNull',

            'Invoke-PSUtilRetryOnError',
            'Invoke-PSUtilIgnoreError',
            'Invoke-PSUtilSleepWithProgress',

            'Set-PSUtilLogFile',
            'Set-PSUtilTimeStamp',
            'Get-PSUtilOptions',
            'Write-PSUtilLog',
            
            'Get-PSUtilStringFromObject',
            'Get-PSUtilMultiLineStringFromObject',
            'Get-PsUtilExceptionMessage',

            'Compress-PSUtilFolder',
            'Convertto-PS',

            'New-PsUtilKeyPairs',
            'Invoke-PsUtilSSHCommand'

            )
}

