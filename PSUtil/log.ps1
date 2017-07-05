function Set-PSUtilLogFile ([string]$file, [switch] $delete)
{
    Write-Verbose "New log file is '$file'"
    $global:_PsUtilOptions.LogFile = $file
    if ($delete)
    {
        del $global:_PsUtilOptions.LogFile -ea 0
    }
}

if (! $global:_PsUtilOptions) {
    $global:_PsUtilOptions = @{
        TimeStamp = $true
        LogFile = 'psutil.log'
    }
}

function Set-PSUtilLogFile ([string]$file, [switch] $delete)
{
    Write-Verbose "New log file is '$file'"
    $global:_PsUtilOptions.LogFile = $file
    if ($delete)
    {
        del $global:_PsUtilOptions.LogFile -ea 0
    }
}

function Set-PSUtilTimeStamp ($TimeStamp)
{
    $global:_PsUtilOptions.TimeStamp = $TimeStamp
}


function Get-PSUtilOptions ()
{
    return $_PsUtilOptions
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
        if ($_PsUtilOptions.TimeStamp) {
            $time = "$((Get-date).ToLongTimeString()) "
        } else {
            $time = ''
        }
        if ($st.Length -gt 0)
        {
            $message = "$time$st"
        }
        else
        {
            $message = $st
        }
        Write-Host $message -ForegroundColor $color
        $message >> $global:_PsUtilOptions.LogFile
    }
}
