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

function Set-PsTestLogFile ($LogFileName) 
{
    Set-PSUtilLogFile "$($PsTestDefaults.DefaultOutputFolder)\$LogFileName.log" -delete
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
        "Test Summary so far: Success=$success, Fail=$fail percent success=$percent%"
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
    [String[]]$Tests, 
    [String]$OnError, 
    [Hashtable]$InputParameters,
    [switch] $StopOnError,
    [int]$StartIndex = 1,
    [int]$Count = 1
    )
{
    #Set-PSUtilLogFile "$($PsTestDefaults.DefaultOutputFolder)\$name.log" -delete

    #if ((Get-Host).Name.Contains(' ISE '))
    #{
    #    #$psise.CurrentPowerShellTab.DisplayName = $MyInvocation.MyCommand.Name + " $name"
    #}
    #else
    #{
    #    (get-host).ui.RawUI.WindowTitle = $MyInvocation.PSCommandPath + " $name"
    #}

    $currentCount = 1
    while ($true)
    {
        $obj = @{}

        foreach ($key in $InputParameters.keys)
        {
            $obj.$key = randomPick $InputParameters.$key

"for $key, Value=$($obj.$key)"
        }
        Invoke-PSTest -Tests $Tests -OnError $OnError -InputParameters $obj `
                        -StopOnError $StopOnError -StartIndex $StartIndex -Count 1

        if ($currentCount -ge $Count)
        {
            Write-PSUtilLog "Iterations reached $Count so exiting"
            break
        }
    }
}

function Invoke-PsTestLaunchInParallel (
        [int]$ParallelShellCount = 1, 
        [Parameter (Mandatory=$true)][string]$PsFileToLaunch,
        [int]$TotalCount = $ParallelShellCount
        )
{
    $Count = 0
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
        $currentCount = 0
        for ($j = 0; $j -lt $ParallelShellCount; $j++)
        {
            if ($proceslist[$j] -eq 0 -and $Count -lt $TotalCount)
            {
                $currentCount++
                $Count++
                $proceslist[$j] = Start-Process "$PSHOME\PowerShell.exe" -ArgumentList "-NoProfile -f $PsFileToLaunch $namePrefix$Count" -PassThru
                Write-Verbose "$Count Started $PsFileToLaunch $j ProcessId=$($proceslist[$j].id)"
                Sleep 1
            }
            elseif ($proceslist[$j] -ne 0) 
            {
                $currentCount++
                if (-not (Get-Process -id $proceslist[$j].Id -ea 0))
                {
                    Write-Verbose "Completed ProcessId=$($proceslist[$j].id)"
                    $proceslist[$j] = 0
                }
            }
        }

        if ($currentCount -eq 0) {
            return
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

function Get-PsTestName ([string]$Index) 
{
    $name = (Get-Item $MyInvocation.PSCommandPath).BaseName
    if ($Index.Length -gt 0) {
        $name = "$name.$Index"
    }
    return $name
}

function New-PsTestOutput ($Key, $Value)
{
    $obj.Add($Key, $Value)
}

function Test-PsTestMain ()
{
    (Get-PSCallStack)[-1].Command -eq (Get-Item $MyInvocation.PSCommandPath).Name
}

function Invoke-PsTestPre ()
{
    if (Test-PsTestMain) {
        cd $PSScriptRoot
        $outputFolder = '.\output'
        Remove-Item $outputFolder -ea 0 -Force -Recurse
        Set-PsTestDefaults -DefaultOutputFolder $outputFolder

        $VerbosePreference = 'Continue'
        trap { break } #This stops execution on any exception
        $ErrorActionPreference = 'Stop'
    }
}

function Invoke-PsTestPost ()
{
    if (Test-PsTestMain) {
        Convert-PsTestToTableFormat    
    }
}


function Invoke-PsTest (
    [String[]]$Tests, 
    [String]$OnError, 
    [Hashtable]$InputParameters = @{},
    [switch] $StopOnError,
    [int]$StartIndex = 1,
    [int]$Count = 1
    )
{
    while ($Count-- -gt 0) {
        $name = (Get-Item $MyInvocation.PSCommandPath).BaseName
        Set-PsTestLogFile "$name.$StartIndex"
    
        $obj = New-Object 'system.collections.generic.dictionary[[string],[object]]'
        #$global:obj = @{}
        $obj.Add('Name', $name)
        $obj.Add('Index', $StartIndex)
        $obj.Add('Result', '')
        $obj.Add('Message', '')

        $InputParameters.Keys | % { $obj.$_ = $InputParameters.$_ }
        foreach ($test in $Tests) {
            $params = runTest -Test $test -OnError $OnError -StopOnError:$StopOnError -Index $StartIndex
        }
        $StartIndex++
    }
}

function runFunction ([string]$functionName) {
    if (Test-Path $functionName) {
        $sb = [ScriptBlock]::Create($functionName)
    } else {
        $sb = (get-command $functionName -CommandType Function).ScriptBlock
    }

    foreach ($parameter in $sb.Ast.Parameters)
    {
        $paramname = $parameter.Name.VariablePath.UserPath
        if ($obj.ContainsKey($paramname)) {
            #$obj[$paramname] = $InputParameters[$paramname]
            Write-PSUtilLog "    Parameter $paramname=$($obj[$paramname]) (Overritten)"
        } else {
            Write-PSUtilLog "    Parameter $paramname=$($parameter.DefaultValue) (Default Value)"
        }
    }

    & $sb @obj 4>&1 3>&1 5>&1 | extractMetric | Write-PSUtilLog
}

function runTest (
    [String]$Test, 
    [String]$onError, 
    [switch] $StopOnError,
    [int]$Index)
{
    #$obj.'obj' = $obj
    try
    {
        $startTime = Get-Date

        Write-PSUtilLog ''
        Write-PSUtilLog "<<<< BEGIN $Test.$Index"
        runFunction $Test
        $obj.Result = 'Success'
    }
    catch
    {
        $obj.Result = 'Fail'
        $ex = $_.Exception
        $line = $_.InvocationInfo.ScriptLineNumber
        $script = (Get-Item $_.InvocationInfo.ScriptName).Name

        $obj.Message = "$($ex.Message) ($script, Line #$line)" 

        if ($onError -ne $null)
        {
            Write-PSUtilLog 'OnError Dump'
            try
            {
                runFunction $onError
            }
            catch
            {
                Write-PSUtilLog "OnError: Message=$($_.Exception.Message)"
            }
        }

        if ($StopOnError)
        {
            throw $ex
        }
    }
    #Remove, so output does not have noise
    #$obj.Remove('obj')

    logStat $(Get-PSUtilStringFromObject $obj)
    gstat
    Write-PSUtilLog ">>>> END $Test.$Index ($($obj.'Result'))`n"
    $obj
}


New-Alias -Name gstat -Value Get-PsTestStatistics -EA 0
New-Alias -Name gfail -Value Get-PsTestFailedResults -EA 0
New-Alias -Name gpass -Value Get-PsTestPassedResults -EA 0
New-Alias -Name gresults -Value Get-PsTestResults -EA 0
Export-ModuleMember -Alias * -Function *

function logStat ([string]$message, 
                  [ConsoleColor]$color = 'White'
)
{
    Invoke-PSUtilRetryOnError {$message >> $PsTestDefaults.ResultsFile}
    Write-PSUtilLog "Results:`n    $($message.Replace("`t","`n    "))" $color
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

