trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'

function Get-PSUtilDefaultIfNull ($value, $defaultValue)
{
    if ([string]$value.Length -eq 0)
    {
        $ret = $defaultValue
    } else {
        $ret = $value
    }
    Write-Verbose "Get-PSUtilDefaultIfNull Value=$value, DefaultValue=$defaultValue, Return=$ret"
    Return $ret
}

function Compress-PSUtilFolder($SourceFolder, $ZipFileName, $IncludeBaseDirectory = $true)
{
    del $ZipFileName -ErrorAction 0
    Add-Type -Assembly System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($SourceFolder,
        $ZipFileName, [System.IO.Compression.CompressionLevel]::Optimal, $IncludeBaseDirectory)
}
