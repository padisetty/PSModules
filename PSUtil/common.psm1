trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'

function Get-PSUtilDefaultIfNull ($value, $defaultValue)
{
    Write-Verbose "Get-PSUtilDefaultIfNull Value=$value, DefaultValue=$defaultValue"
    if ([string]$value.Length -eq 0)
    {
        $defaultValue
    }
    else
    {
        $value
    }
}

$logfile = Get-PSUtilDefaultIfNull $logfile 'test.log'

function Invoke-PSUtilIgnoreError ($scriptBlock)
{
    try
    {
        . $scriptBlock
    }
    catch
    {
        Write-Verbose "IgnoreError: Message=$($_.Exception.Message)"
    }
}

function Invoke-PSUtilRetryOnError ($scriptBlock, $retryCount = 3)
{
    for ($i=1; $i -le $retryCount; $i++)
    {
        try
        {
            $a = . $scriptBlock
            $a
            break
        }
        catch
        {
            Write-Host "Error: $($_.Exception.Message), RetryCount=$i, ScriptBlock=$scriptBlock" -ForegroundColor Yellow
            Write-Host $a
            if ($i -eq $retryCount)
            {
                throw $_.Execption
            }
            Sleep 10 # wait before retrying
        }
    }
}

# local variables has _wait_ prefix to avoid potential conflict in ScriptBlock
# Retry the scriptblock $cmd until no error and return true
function Invoke-PSUtilWait ([ScriptBlock] $Cmd, 
               [string] $Message, 
               [int] $RetrySeconds,
               [int] $SleepTimeInMilliSeconds = 5000)
{
    $_wait_activity = "Waiting for $Message to succeed"
    $_wait_t1 = Get-Date
    $_wait_timeout = $false
    Write-Verbose "Wait for $Message to succeed in $RetrySeconds seconds"
    while ($true)
    {
        try
        {
            $_wait_success = $false
            $_wait_result = & $cmd 2>$null | select -Last 1 
            if ($? -and $_wait_result)
            {
                $_wait_success = $true
            }
        }
        catch
        {
        }
        $_wait_t2 = Get-Date
        if ($_wait_success)
        {
            $_wait_result
            break;
        }
        if (($_wait_t2 - $_wait_t1).TotalSeconds -gt $RetrySeconds)
        {
            $_wait_timeout = $true
            break
        }
        $_wait_seconds = [int]($_wait_t2 - $_wait_t1).TotalSeconds
        Write-Progress -Activity $_wait_activity `
            -PercentComplete (100.0*$_wait_seconds/$RetrySeconds) `
            -Status "$_wait_seconds Seconds, will try for $RetrySeconds seconds before timeout, Current result=$_wait_result"
        Sleep -Milliseconds $SleepTimeInMilliSeconds
    }
    Write-Progress -Activity $_wait_activity -Completed
    if ($_wait_timeout)
    {
        Write-Verbose "$Message [$([int]($_wait_t2-$_wait_t1).TotalSeconds) Seconds - Timeout], Current result=$_wait_result"
        throw "Timeout - $Message after $RetrySeconds seconds, Current result=$_wait_result"
    }
    else
    {
        Write-Verbose "Succeeded $Message in $([int]($_wait_t2-$_wait_t1).TotalSeconds) Seconds."
    }
}

function Set-PSUtilLogFile ([string]$file, [switch] $delete)
{
    Write-Verbose "New log file is $file"
    $script:logfile = $file
    if ($delete)
    {
        del $logfile -ea 0
    }
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
        $message >> $logfile
    }
}

function Get-PSUtilStringFromObject ($obj)
{
    $st = ''
    foreach ($key in $obj.Keys)
    {
        if ($obj[$key] -is [Timespan])
        {
            $value = '{0:hh\:mm\:ss}' -f $obj."$key"
        }
        else
        {
            $value = [string]$obj[$key]
        }
        if ($st.Length -gt 0)
        {
            $st = "$st`t$key=$value"
        }
        else
        {
            $st = "$key=$value"
        }
    }
    $st
}

function Get-PSUtilMultiLineStringFromObject ($obj)
{
    '  ' + (Get-PSUtilStringFromObject $obj).Replace("`t","`n  ")
}

function Invoke-PSUtilSleepWithProgress ([Parameter(Mandatory=$true)][int]$Seconds)
{
    $activity = "Sleeping"
    $t1 = Get-Date
    Write-Verbose "Sleeping for $Seconds seconds"
    while ($true)
    {
        $t2 = Get-Date
        if (($t2 - $t1).TotalSeconds -gt $Seconds)
        {
            break
        }
        $wait_seconds = [int]($t2 - $t1).TotalSeconds
        Write-Progress -Activity $activity `
            -PercentComplete (100.0*$wait_seconds/$Seconds) `
            -Status "Completed $wait_seconds/$Seconds seconds"
        Sleep -Seconds 5
    }
    Write-Progress -Activity $activity -Completed
    Write-Verbose "Sleep completed"
}

function Compress-PSUtilFolder($SourceFolder, $ZipFileName, $IncludeBaseDirectory = $true)
{
    del $ZipFileName -ErrorAction 0
    Add-Type -Assembly System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($SourceFolder,
        $ZipFileName, [System.IO.Compression.CompressionLevel]::Optimal, $IncludeBaseDirectory)
}
