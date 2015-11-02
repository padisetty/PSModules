Import-Module -Global PSUtil -Force -Verbose:$false

trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'

$PsTestDefaults = @{
    }

function Set-PsTestDefaults ($DefaultOutputFolder)
{
    $PsTestDefaults.DefaultOutputFolder = Get-PSUtilDefaultIfNull $DefaultOutputFolder $PsTestDefaults.DefaultOutputFolder

    if (! (Test-Path $PsTestDefaults.DefaultOutputFolder -PathType Container))
    {
        $null = md $PsTestDefaults.DefaultOutputFolder
    }
    Write-Verbose "Created folder $($PsTestDefaults.DefaultOutputFolder)"
    $PsTestDefaults.ResultsFile = "$($PsTestDefaults.DefaultOutputFolder)\Results.csv"
    Write-Verbose "Results files location is $($PsTestDefaults.ResultsFile)"
}

function Get-PsTestDefaults ()
{
    @{
        DefaultOutputFolder = $PsTestDefaults.DefaultOutputFolder
    }
}

Set-PsTestDefaults -DefaultOutputFolder '.\Output'

function Get-PsTestStatistics ([string]$logfile = $PsTestDefaults.ResultsFile)
{
    try
    {
        [int]$success = (cat $logfile | Select-String 'Result=Success').Line | wc -l
        [int]$fail = (cat $logfile | Select-String 'Result=Fail').Line | wc -l
        if ($success+$fail -gt 0)
        {
            $percent = [decimal]::Round(100*$success/($success+$fail))
        }
        else
        {
            $percent = 0
        }
        "Summary so far: Success=$success, Fail=$fail percent success=$percent%"
    }
    catch
    {
        Write-Warning "$logfile not found."
    }
}


function Get-PsTestFailedResults ([string]$Filter, [string]$ResultsFile = $PsTestDefaults.ResultsFile, [switch]$OutputInSingleLine)
{
   Get-PsTestResults 'Result=Fail' $filter $ResultsFile -OutputInSingleLine:$OutputInSingleLine
}


function Get-PsTestPassedResults ([string]$Filter, [string]$ResultsFile = $PsTestDefaults.ResultsFile, [switch]$OutputInSingleLine)
{
   Get-PsTestResults 'Result=Success' $filter $ResultsFile -OutputInSingleLine:$OutputInSingleLine
}

function Get-PsTestResults ([string]$Filter1, [string]$Filter2, 
                       [string]$ResultsFile = $PsTestDefaults.ResultsFile, [switch]$OutputInSingleLine)
{
    if (Test-Path $ResultsFile)
    {
        if ($OutputInSingleLine)
        {
            cat $ResultsFile | ? {$_ -like "*$Filter1*"} | ? {$_ -like "*$Filter2"}
        }
        else
        {
            cat $ResultsFile | ? {$_ -like "*$Filter1*"} | ? {$_ -like "*$Filter2"} | % {$_.Replace("`t","`n    ")}
        }
    }
    else
    {
        Write-Warning "$ResultsFile not found"
    }
}

function Convert-PsTestToTableFormat ($inputFile = '')
{
    if ($inputFile.Length -eq 0) {
        $inputFile = $PsTestDefaults.ResultsFile
    }
    
    if (! (Test-Path $inputFile -PathType Leaf)) {
        Write-Error "Input file not found, file=$inputFile"
        r
    }

    $finfo = Get-Item $inputFile
    $outFile = $inputFile.Replace($finfo.Extension, '.output' + $finfo.Extension)
    Write-Verbose "Input file=$inputFile"
    Write-Verbose "Output file=$outFile"

    $labels =  @()
    foreach ($line in (cat $inputFile))
    {
        $parts = $line.Split("`t")
        foreach ($part in $parts)
        {
            $kv = $part.Split('=')
            if (!$labels.Contains($kv[0]))
            {
                $labels += $kv[0]
            }
        }
    }
    
    $st = ''
    foreach ($label in $labels)
    {
        $st += "$label`t"
    }
    $st > $outFile
    foreach ($line in (cat $inputFile))
    {
        $row = @{}

        $parts = $line.Split("`t")
        foreach ($part in $parts)
        {
            $kv = $part.Split('=')
            $row.Add($kv[0], $kv[1])
        }

        $st = ''
        foreach ($label in $labels)
        {
            $st += "$($row[$label])`t"
        }
        $st >> $outFile
    }
}

function Invoke-PsTestRandomLoop (
        [Parameter(Mandatory=$true)][string] $Name,
        [ScriptBlock] $Main,
        [Hashtable]$Parameters,
        [ScriptBlock]$OnError,
        [switch] $ContinueOnError,
        [int]$MaxCount = 10
    )
{
    Set-PSUtilLogFile "$($PsTestDefaults.DefaultOutputFolder)\test$name.log" -delete

    if ((Get-Host).Name.Contains(' ISE '))
    {
        #$psise.CurrentPowerShellTab.DisplayName = $MyInvocation.MyCommand.Name + " $name"
    }
    else
    {
        (get-host).ui.RawUI.WindowTitle = $MyInvocation.PSCommandPath + " $name"
    }

    $count = 0
    while ($true)
    {
        $global:obj = New-Object 'system.collections.generic.dictionary[[string],[object]]'
        $obj.Add('Name', $name)
        $obj.Add('Result', '')
        $obj.Add('Message', '')
        $obj.Add('Count', $count)
        $obj.Add('Time', "$((Get-Date).ToShortDateString()) $((Get-Date).ToShortTimeString())")

        foreach ($key in $parameters.keys)
        {
            $obj.$key = randomPick $parameters.$key
        }
        $count++
        singleRun -sb $Main -onError $OnError -continueOnError:$ContinueOnError

        if ($count -ge $MaxCount)
        {
            Write-PSUtilLog "Iterations reached $MaxCount so exiting"
            break
        }
    }
}

function Invoke-PsTestLaunchInParallel (
        [int]$ParallelShellCount = 1, 
        [Parameter (Mandatory=$true)][string]$PsFileToLaunch
        )
{
    Write-Verbose "LaunchTest Parallel ParallelShellCount=$ParallelShellCount, PsFileToLaunch=$PsFileToLaunch"

    if (!(Test-Path -Path $PsFileToLaunch -PathType Leaf))
    {
        throw "The file $PsFileToLaunch not found"
    }
    if (Test-Path $PsTestDefaults.DefaultOutputFolder -PathType Container)
    {
        $dinfo = Get-Item $PsTestDefaults.DefaultOutputFolder

        mv  -Path $PsTestDefaults.DefaultOutputFolder -Destination "$($dinfo.Name).$((Get-Date).ToString('yyyy-MM-dd_hh.mm.ss'))"
    }
    $null = md $PsTestDefaults.DefaultOutputFolder

    $finfo = Get-Item $PsFileToLaunch

    $namePrefix = $finfo.BaseName

    $proceslist = ,0*$ParallelShellCount
    $prevstat = $null
    $prevfails = $null

    #Connect to the process if already present. It assumes that end with the same id
    $pslist = gps powershell -ea 0
    if ($pslist -ne $null)
    {
        for ($j = 0; $j -lt $ParallelShellCount; $j++)
        {
            foreach ($ps in $pslist)
            {
                if ($ps.MainWindowTitle -eq "$($finfo.FullName.ToLower()) $namePrefix$j")
                {
                    "Reusing for index=$j $($ps.ProcessName) with id=$($ps.Id)"
                    $proceslist[$j] = $ps
                }
            }
        }
    }

    while ($true)
    {
        for ($j = 0; $j -lt $ParallelShellCount; $j++)
        {
            if ($proceslist[$j] -eq 0)
            {
                $proceslist[$j] = Start-Process "$PSHOME\PowerShell.exe" -ArgumentList "-NoProfile -NoExit -f `"$PsFileToLaunch`" $namePrefix$j" -PassThru
                Write-Verbose "Started $PsFileToLaunch $j ProcessId=$($proceslist[$j].id)"
                Sleep 1
            }
            elseif ($proceslist[$j] -ne 0) 
            {
                if (-not (Get-Process -id $proceslist[$j].Id -ea 0))
                {
                    Write-Verbose "Completed ProcessId=$($proceslist[$j].id)"
                    $proceslist[$j] = 0
                }
            }
        }

        $stat = gstat
        if ($prevstat -ne $stat)
        {
            $stat
            $prevstat = $stat

            $fails = gfail
            foreach ($fail in $fails)
            {
                if (!$prevfails -or !$prevfails.Contains($fail))
                {
                    $fail
                }
            }

            $prevfails = $fails
            ''
        }
        Sleep 5
    }
    return
}

New-Alias -Name gstat -Value Get-PsTestStatistics
New-Alias -Name gfail -Value Get-PsTestFailedResults
New-Alias -Name gpass -Value Get-PsTestPassedResults
New-Alias -Name gresults -Value Get-PsTestResults
Export-ModuleMember -Alias * -Function *

function logStat ([string]$message, 
                  [ConsoleColor]$color = 'White'
)
{
    Invoke-PSUtilRetryOnError {$message >> $PsTestDefaults.ResultsFile}
    Write-PSUtilLog $message $color
}

function randomPick ([string[]] $list)
{
    $list[(Get-Random $list.Count)]
}

function getDiffString ()
{
    $st = ''
    foreach ($key in $obj.keys)
    {
        if (!$diffobj.ContainsKey($key) -or $diffobj[$key] -ne $obj[$key])
        {
            if ($st.Length -gt 0)
            {
                $st += ', '
            }
            $st += "$key=$($obj[$key])"

            $diffobj[$key] = $obj[$key]
        }
    }
    if ($st.Length -gt 0)
    {
        "DiffParams=($st)"
    }
}




function extractMetric ()
{
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline=$true)]
        [string]$st
    )
    PROCESS {
        if ($st.StartsWith('#PSTEST#')) 
        { 
            $a = $st.Substring(8).Trim().Split('=')
            $key = ([string]$a[0]).Trim()
            $value = ([string]$a[1]).Trim()
            if ($a.Count -ne 2 -or $key.Length -eq 0 -or $value.Length -eq 0)
            {
                Write-Error '#PSTEST# invalid format, it has to be of the form #PSTEST# x=y'
            } else {
                if ($obj.$key) {
                    $obj.$key = $obj.$key + ", " + $value
                } else {
                    $obj.$key = $value
                }
            }
        }
        $st
    }
}

function singleRun ([ScriptBlock] $sb, [ScriptBlock]$onError, [switch] $continueOnError)
{
    try
    {
        Write-PSUtilLog ''
        Write-PSUtilLog ''
        Write-PSUtilLog '<<<< --------------- BEGIN TEST --------------------'
        & $sb 4>&1 3>&1 5>&1 | extractMetric | Write-PSUtilLog
        $obj.Result = 'Success'
        logStat (Get-PSUtilStringFromObject $obj)
        gstat
        Write-PSUtilLog ">>>> --------------- END TEST SUCCESS --------------------" 'Green'
    }
    catch
    {
        $obj.Result = 'Fail'
        $obj.Message = $_.Exception.Message
        logStat (Get-PSUtilStringFromObject $obj) 'Red'
        $ex = $_.Exception

        if ($onError -ne $null)
        {
            Write-PSUtilLog ''
            Write-PSUtilLog ''
            Write-PSUtilLog 'OnError Dump'
            try
            {
                & $onError 4>&1 3>&1 5>&1 | Write-PSUtilLog
            }
            catch
            {
                Write-PSUtilLog "OnError: Message=$($_.Exception.Message)"
            }
        }
        gstat
        Write-PSUtilLog ">>>> --------------- END TEST FAIL --------------------" 'Red'

        if (! $ContinueOnError)
        {
            throw $ex
        }
    }
}


function singleRunWithStringArray ([string[]] $Tests, [string]$OnError, [switch] $ContinueOnError)
{
    try
    {
        $script:diffobj = New-Object 'system.collections.generic.dictionary[[string],[object]]'
        Write-PSUtilLog ''
        Write-PSUtilLog ''
        Write-PSUtilLog "<<<< BEGIN TEST Tests=($($Tests -join ', ')), $(getDiffString)"
        foreach ($test in $Tests)
        {
            #$tinfo = gcm $test
            #$tinfo.ScriptBlock.Attributes

            Write-PSUtilLog "Start $test $(getDiffString)"
            iex $test 4>&1 3>&1 5>&1 | extractMetric | Write-PSUtilLog
            Write-PSUtilLog "End $test $(getDiffString)"
        }
        $obj.Result = 'Success'
        logStat (Get-PSUtilStringFromObject $obj)
        Write-PSUtilLog ">>>> --------------- END TEST SUCCESS --------------------" 'Green'
    }
    catch
    {
        $obj.Result = 'Fail'
        $obj.Message = $_.Exception.Message
        logStat (Get-PSUtilStringFromObject $obj) 'Red'
        $ex = $_.Exception

        if ($OnError -ne $null)
        {
            Write-PSUtilLog ''
            Write-PSUtilLog ''
            Write-PSUtilLog 'OnError Dump'
            try
            {
                . $OnError 4>&1 3>&1 5>&1 | Write-PSUtilLog
            }
            catch
            {
                Write-PSUtilLog "OnError: Message=$($_.Exception.Message)"
            }
        }
        Write-PSUtilLog ">>>> --------------- END TEST FAIL --------------------" 'Red'

        if (! $ContinueOnError)
        {
            throw $ex
        }
    }
}
