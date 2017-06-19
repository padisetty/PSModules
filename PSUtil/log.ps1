function Set-PSUtilLogFile ([string]$file, [switch] $delete)
{
    Write-Verbose "New log file is '$file'"
    $global:_PsUtilLogFile = $file
    if ($delete)
    {
        del $_PsUtilLogFile -ea 0
    }
}

function Get-PSUtilLogFile ()
{
    return $_PsUtilLogFile
}

function Write-PSUtilLog ()
{
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline=$true)]
        [string]$st,
        [ConsoleColor]$color = 'White'
    )
    PROCESS {
        if ($st.Length -gt 0)
        {
            $message = "$((Get-date).ToLongTimeString()) $st"
        }
        else
        {
            $message = $st
        }
        Write-Host $message -ForegroundColor $color
        $message >> $_PsUtilLogFile
    }
}
