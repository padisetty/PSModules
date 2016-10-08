Import-Module -Global PSUtil -Force -Verbose:$false

$ResultsFile = 'Results.csv'

function Explode ([Hashtable[]]$parameterSets, 
                  [string]$key,
                  [object[]]$values)
{
    [Hashtable[]] $results = @()

    foreach ($parameterSet in $parameterSets)
    {
        foreach ($value in $values)
        {
            [Hashtable]$tempParameterSet = $parameterSet.Clone()
            $tempParameterSet.Add($key, $value)
            $results += $tempParameterSet
        }
    }
    $results
}

function Get-PsTestStatistics ([string]$logfile = $ResultsFile)
{
    Write-Verbose "Get-PsTestStatistics (gstat) Log File=$logfile"
    try
    {
        [int]$success = ((cat $logfile | Select-String 'Result=Success').Line | measure -Line).Lines
        [int]$fail = ((cat $logfile | Select-String 'Result=Fail').Line | measure -Line).Lines
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

function Get-PsTestFailedResults ([string]$Filter, [string]$ResultsFileName = $ResultsFile, [switch]$OutputInSingleLine)
{
   Get-PsTestResults 'Result=Fail' $filter $ResultsFileName -OutputInSingleLine:$OutputInSingleLine
}

function Get-PsTestPassedResults ([string]$Filter, [string]$ResultsFileName = $ResultsFile, [switch]$OutputInSingleLine)
{
   Get-PsTestResults 'Result=Success' $filter $ResultsFileName -OutputInSingleLine:$OutputInSingleLine
}

function Get-PsTestResults ([string]$Filter1, [string]$Filter2, 
                       [string]$ResultsFileName = $ResultsFile, [switch]$OutputInSingleLine)
{
    if (Test-Path $ResultsFileName)
    {
        if ($OutputInSingleLine)
        {
            cat $ResultsFileName | ? {$_ -like "*$Filter1*"} | ? {$_ -like "*$Filter2"}
        }
        else
        {
            cat $ResultsFileName | ? {$_ -like "*$Filter1*"} | ? {$_ -like "*$Filter2"} | % {$_.Replace("`t","`n    ")}
        }
    }
    else
    {
        Write-Warning "$ResultsFileName not found"
    }
}

function Convert-PsTestToTableFormat ($inputFile = '')
{
    if ($inputFile.Length -eq 0) {
        $inputFile = $ResultsFile
    }
    
    if (! (Test-Path $inputFile -PathType Leaf)) {
        Write-Error "Input file not found, file=$inputFile"
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


function Test-PSTestExecuting ()
{
    return $_depth -gt 0
}

$_depth = 0
function Invoke-PsTest (
    [String[]]$Tests, 
    [String]$OnError, 
    [Hashtable[]]$InputParameterSets = @{},
    [switch]$StopOnError,
    [string]$LogNamePrefix = 'PSTest',
    [int]$Count = 1
    )
{
    $_depth++

    for ($i=1; $i -le $Count; $i++) {
        $set = 0
        foreach ($inputParameterSet in $InputParameterSets) {
            $set++
            $global:obj = New-Object -TypeName ‘System.Collections.Generic.Dictionary[[String],[Object]]’ -ArgumentList @([System.StringComparer]::CurrentCultureIgnoreCase)
            $obj.Add('Tests', '')
            $obj.Add('Result', '')
            $obj.Add('Message', '')
            $obj.Add('Index', $i)
            $testnames = ''
            $inputParameterSet.Keys | % { $obj.$_ = $inputParameterSet.$_ }
            if ($_depth -eq 1) {
                $prefix = ''
                if ($Count -gt 1) {
                    $prefix += "Iteration#$i "
                }
                if ($InputParameterSets.Count -gt 1) {
                    $prefix += "ParameterSet#$set "
                }
                $_LogFileName = "$prefix$LogNamePrefix.log"
                if (Test-Path $_LogFileName) {
                    throw "Logfile $_LogFileName already exists"
                }
            }
            Set-PSUtilLogFile $_LogFileName
            Write-PSUtilLog 'Inputs:'
            foreach ($inputparameter in $inputParameterSet.Keys) {
                Write-PSUtilLog "    $inputparameter=$($inputParameterSet[$inputparameter])"
            }
            Write-PSUtilLog 'Tests:'
            foreach ($test in $Tests) {
                Write-PSUtilLog "    $test"
            }
            Write-PSUtilLog "OnError=$OnError, StopOnError=$StopOnError, Count=$Count"
            Write-PSUtilLog ''

            foreach ($test in $Tests) {
                if (Test-Path $test) {
                    $testname = (Get-Item $test).BaseName
                } else {
                    $testname = $test
                }
                if ($testnames.Length -gt 0) {
                    $testnames += ', '
                }
                $testnames += $testname

                runTest -Test $test -TestName $testname -OnError $OnError -StopOnError:$StopOnError -Index $i -Count $Count
            }
            $obj.'Tests' = $testnames
            if ($obj.Result.Length -eq 0) {
                $obj.Result = 'Success'
            }
            logStat $(Get-PSUtilStringFromObject $obj)
            gstat
            Write-PSUtilLog ''
            Write-PSUtilLog ''
        }
    }
    $_depth--
}

function runFunction ([string]$functionName) {
    if (Test-Path $functionName) {
        $sb=Get-Command $functionName | select -ExpandProperty ScriptBlock 
        #$sb = [ScriptBlock]::Create((cat $functionName -Raw))
        $parameters = $sb.Ast.ParamBlock.Parameters
    } else {
        $sb = (get-command $functionName -CommandType Function).ScriptBlock
        $parameters = $sb.Ast.Parameters
    }

    foreach ($parameter in $parameters)
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
    [String]$TestName,
    [String]$onError, 
    [switch]$StopOnError,
    [int]$Index,
    [int]$Count)
{
    try
    {
        $startTime = Get-Date

        Write-PSUtilLog "<<<< BEGIN '$TestName' ($Index of $Count)"
        runFunction $Test
        $obj."$TestName.Result" = 'Completed Successfully'
    }
    catch
    {
        $obj.Result = 'Fail'

        $ex = $_.Exception
        $line = $_.InvocationInfo.ScriptLineNumber
        $script = (Get-Item $_.InvocationInfo.ScriptName).Name

        $message = "$($ex.Message) ($script, Line #$line)" 
        $obj."$TestName.Result" = $message
        Write-PSUtilLog "Failed Message=$message"
        if ($obj.Message.Length -eq 0) {
            $obj.Message = $message
        }

        if ($onError.Length -eq 0)
        {
            Write-PSUtilLog 'OnError Dump'
            try
            {
                runFunction $onError
            }
            catch
            {
                Write-PSUtilLog "OnError: Message=$message"
            }
        }

        if ($StopOnError)
        {
            throw $ex
        }
    }
    Write-PSUtilLog ">>>> END '$TestName' Result=($($obj."$TestName.Result")) ($Index of $Count)`n"
}

function Invoke-PsTestRandomLoop (
    [String[]]$Tests, 
    [String]$OnError, 
    [Hashtable]$InputParameters,
    [switch]$StopOnError,
    [string]$LogNamePrefix = 'Random',
    [int]$Count = 1
    )
{
    for ($i = 1; $i -le $Count; $i++)
    {
        $obj = @{}

        foreach ($key in $InputParameters.keys)
        {
            $obj.$key = randomPick $InputParameters.$key
        }
        Invoke-PSTest -Tests $Tests -OnError $OnError -InputParameters $obj `
                        -StopOnError $StopOnError -Count 1 -LogNamePrefix "$($LogNamePrefix)Combo #$i-"
    }
}

function PsTestLaunchWrapper ([string]$FileName, [string]$Name) {
    $_depth++
    $VerbosePreference = 'Continue'
    trap { break } #This stops execution on any exception
    $ErrorActionPreference = 'Stop'

    Write-Host "Executing $FileName" -ForegroundColor Yellow
    & $FileName $Name
    $_depth--
    gstat
    if (-not (gfail)) { Stop-Process -Id $pid }
   # exit
}

function Invoke-PsTestLaunchInParallel (
        [int]$ParallelShellCount = 1, 
        [Parameter (Mandatory=$true)][string]$PsFileToLaunch,
        [int]$TotalCount = $ParallelShellCount
        )
{
    try {
    $count = 0
    Write-Verbose "LaunchTest Parallel ParallelShellCount=$ParallelShellCount, PsFileToLaunch=$PsFileToLaunch"

    if (!(Test-Path -Path $PsFileToLaunch -PathType Leaf))
    {
        throw "The file $PsFileToLaunch not found"
    }

    $finfo = Get-Item $PsFileToLaunch

    if ("$($finfo.DirectoryName)\output" -ne "$((pwd).Path)") {
        throw "Please should execute LaunchInParallel from folder $((pwd).Path)\output"
    }
    $namePrefix = $finfo.BaseName

    $proceslist = ,0*$ParallelShellCount
    $prevstat = $null
    $prevfails = $null

    #Connect to the process if already present. It assumes that end with the same id
    $global:psmap = @{}
    if (Test-Path 'psmap.txt') {
        cat 'psmap.txt' | % { $a = $_.split(' '); $psmap.Add([int]$a[0], [int]$a[1])}
    }
    $count = 0 # tracks total process launched so far

    for ($j=1; $j -le $TotalCount; $j++) {
        if (Test-Path $j) {
            $count = $j
            if ($psmap.ContainsKey($j)) {
                $pid = $psmap.$j
                Write-Verbose "Reusing for index=$j with pid=$($pid)"
            } else {
                Write-Verbose "Skipping $j"
            }
        } else {
            break
        }
    }

    while ($true)
    {
        $removelist = @()
        $change = $false
        foreach ($dir in $psmap.Keys) {
            $pid = $psmap.$dir

            if (-not (Get-Process -id $pid -ea 0))
            {
                $change = $true
                $removelist += $dir
                Write-Verbose "Completed ProcessId=$pid"
                if (Test-Path "$dir\Results.csv") {
                    cat "$dir\Results.csv" >> Results.csv
                }
            }
        }

        $removelist | % { $psmap.Remove($_) }

        while ($psmap.Keys.Count -lt $ParallelShellCount -and 
                    $Count -lt $TotalCount) {
            $change = $true
            $count++
            $null = md $count

            #$ps = Start-Process "$PSHOME\PowerShell.exe"  -PassThru -ArgumentList "-NoExit -NoProfile -f `"$($finfo.FullName)`" $namePrefix$Count" -WorkingDirectory $count
            $ps = Start-Process "$PSHOME\PowerShell.exe"  -PassThru -ArgumentList "-NoExit -NoProfile -command PsTestLaunchWrapper `"'$($finfo.FullName)'`" $Count" -WorkingDirectory $count
            $psmap.$count = $ps.Id
            Write-Verbose "$Count Started ProcessId=$($ps.id)"
            Sleep 1
        }

        if ($change) {
            $psmap.GetEnumerator() | % { "$($_.Key) $($_.Value)" } > 'psmap.txt'
        }

        gstat
        if ($psmap.Keys.Count -eq 0) {
            Write-Verbose 'Completed'
            return
        }
        Sleep 5
    }
    }
    catch
    {
        $ex = $_.Exception
        $line = $_.InvocationInfo.ScriptLineNumber
        $script = (Get-Item $_.InvocationInfo.ScriptName).Name
$ex
$line
$script
    }
}


New-Alias -Name gstat -Value Get-PsTestStatistics -EA 0
New-Alias -Name gfail -Value Get-PsTestFailedResults -EA 0
New-Alias -Name gpass -Value Get-PsTestPassedResults -EA 0
New-Alias -Name gresults -Value Get-PsTestResults -EA 0
Export-ModuleMember -Alias * -Function * -Verbose:$false

function logStat ([string]$message, 
                  [ConsoleColor]$color = 'White'
)
{
    Invoke-PSUtilRetryOnError {$message >> $ResultsFile}
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
Write-Verbose 'Imported Module PSTest'