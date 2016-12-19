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

function Invoke-PSUtilRetryOnError ($ScriptBlock, $RetryCount = 3, $SleepTimeInMilliSeconds = 5000)
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
            Sleep -Milliseconds $SleepTimeInMilliSeconds
        }
    }
}

# local variables has _wait_ prefix to avoid potential conflict in ScriptBlock
# Retry the scriptblock $cmd until no error and return true
function Invoke-PSUtilWait ([ScriptBlock] $Cmd, 
               [string] $Message, 
               [int] $RetrySeconds = 300,
               [int] $SleepTimeInMilliSeconds = 5000,
               [switch] $PrintVerbose)
{
    $_wait_activity = "Waiting for $Message to succeed"
    $_wait_t1 = Get-Date
    $_wait_timeout = $false
    $_wait_seconds = 0
    Write-Verbose "Wait for $Message to succeed in $RetrySeconds seconds"
    while ($true)
    {
        try
        {
            $_wait_success = $false
            $_wait_result = & $cmd 2>$null

            if ($? -and $_wait_result)
            {
                $_wait_success = $true
            }
            if ($PrintVerbose) {
                Write-Verbose "result=$_wait_result ($_wait_seconds/$RetrySeconds)"
            }
        }
        catch
        {
            $_wait_result = "Exception: $($_.Exception.Message)"
            if ($PrintVerbose) {
                Write-Verbose "$_wait_result ($_wait_seconds/$RetrySeconds)"
            }
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
