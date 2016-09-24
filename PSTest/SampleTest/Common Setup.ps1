Write-Verbose 'Common Setup'
$VerbosePreference = 'Continue'
trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'
