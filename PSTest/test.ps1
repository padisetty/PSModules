﻿Import-Module -Global PSUtil -Force -Verbose:$false

$ResultsFile = 'Results.csv'
#Remving this enables to inherit global value
Remove-Variable PSDefaultParameterValues -Force -ErrorAction Ignore -Scope local

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
            cat $ResultsFileName | ? {$_ -like "*$Filter1*"} | ? {$_ -like "*$Filter2"} | % {$_.Replace("`t","`r`n    ")}
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
    $Tests, 
    [String]$OnError, 
    [Hashtable[]]$InputParameterSets = @{},
    [switch]$StopOnError,
    [string]$LogNamePrefix = 'PSTest',
    [int]$OuterRepeat = 1
    )
{
    $_depth++
    $_LogFileName = "$LogNamePrefix.log"
    Set-PSUtilLogFile $_LogFileName

    for ($i=1; $i -le $OuterRepeat; $i++) {
        
        $set = 0
        foreach ($inputParameterSet in $InputParameterSets) {
            $set++
            $obj = New-Object -TypeName ‘System.Collections.Generic.Dictionary[[String],[Object]]’ -ArgumentList @([System.StringComparer]::CurrentCultureIgnoreCase)
            $obj.OuterRepeat = "$i of $OuterRepeat"
            $obj.ParameterSet = "#$set"

            if ($inputParameterSet.ContainsKey('ParameterSetRepeat')) {
                $parameterSetRepeat = $inputParameterSet.ParameterSetRepeat
            } else {
                $parameterSetRepeat = 1
            }
            for ($j=1; $j -le $parameterSetRepeat; $j++) {
                $inputParameterSet.Keys | % { $obj.$_ = $inputParameterSet.$_ }
                $obj.ParameterSetRepeat = "$j of $parameterSetRepeat"

                Write-PSUtilLog 'New Parameter Set:'
                Write-PSUtilLog '------------------'
                Write-PSUtilLog 'Inputs:'
                foreach ($inputparameter in $inputParameterSet.Keys) {
                    Write-PSUtilLog "    $inputparameter=$($inputParameterSet[$inputparameter])"
                }
                Write-PSUtilLog 'Tests:'
                foreach ($test in $Tests) {
                    Write-PSUtilLog "    $(getTestName($test))"
                }
                Write-PSUtilLog "OnError=$OnError, StopOnError=$StopOnError, OuterRepeat=$OuterRepeat"
                Write-PSUtilLog ''

                foreach ($test in $Tests) {
                    runTest -Test $test -OnError $OnError -StopOnError:$StopOnError
                }
            }
            #logStat $(Get-PSUtilStringFromObject $obj)
        }
    }
    $_depth--
}

function runTest (
    $Test, 
    [String]$onError, 
    [switch]$StopOnError)
{
    $sb, $parameters, $testname, $testRepeat = getExecutionContext($Test)

    for ($i = 1; $i -le $testRepeat; $i++) {
        $newobj = cloneTestObject $obj $Test
        $newobj.TestRepeat = "$i of $testRepeat"
        Write-PSUtilLog "**BEGIN '$TestName' ($_LogFileName)"

        $startTime = Get-Date
        $ret = runFunction $sb $parameters $newobj
        $newobj.ExecutionTime = ((Get-Date) - $startTime).ToString()

        if ($ret) {
            $newobj.Result = 'Success'
        } elseif ($onError.Length -gt 0) {
            $sb, $parameters, $null = getExecutionContext($onError)
            $null = runFunction $sb $parameters $newobj
        }

        logStat $(Get-PSUtilStringFromObject $newobj)

        Write-PSUtilLog "END '$testName' ($_LogFileName)`r`n`r`n"

        if ($StopOnError -and $newobj.Result -ne 'Success')
        {
            gstat

            Convert-PsTestToTableFormat    
            throw "$TestName`:$($newobj.Message)"
        }
    }

    foreach ($k in $Test.Output) {
        $obj.$k = $newobj.$k
    }
}

function runFunction ($sb, $parameters, $obj) {
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

    try {
        $result = & $sb @obj 4>&1 3>&1 5>&1 | extractMetric
        #$result = $sb.InvokeWithContext($null,@(), $p) 4>&1 3>&1 5>&1 | extractMetric

        if ($result -is [hashtable]) {
            Write-PSUtilLog "Test Result:" -color Cyan
            $result.Keys | % { $obj.$_ = $result.$_; Write-PSUtilLog "    $_ = $($result.$_)" -color Cyan}
        }
        $ret = $true
    } catch {
        $obj.Result = 'Fail'

        $ex = $_.Exception
        $line = $_.InvocationInfo.ScriptLineNumber
        $script = (Get-Item $_.InvocationInfo.ScriptName).Name
        $message = "$($ex.Message) ($script, Line #$line)" 

        Write-PSUtilLog $message -color Red

        if ($obj.Message.Length -eq 0) {
            $obj.Message = $message
        }
        $ret = $false        
    }
    $ret
}

function getTestName ($Test) {
    if ($Test -is [hashtable]) {
        $t = $Test.Test
    } else {
        $t = $Test
    }

    if (Test-Path $t) {
        $testname = (Get-Item $t).BaseName
    } else {
        $testname = $t
    }
    return $testname
}

function getExecutionContext ($Test) {
    if ($Test -is [hashtable]) {
        $t = $Test.Test
        $testRepeat = $Test.TestRepeat
    } else {
        $t = $Test
    }

    if (! $testRepeat -or $testRepeat -lt 0) {
        $testRepeat = 1
    }

    if (Test-Path $t) {
        $sb=Get-Command $t | select -ExpandProperty ScriptBlock 
        #$sb = [ScriptBlock]::Create((cat $functionName -Raw))
        $parameters = $sb.Ast.ParamBlock.Parameters
        $testname = (Get-Item $t).BaseName
    } else {
        $sb = (get-command $t -CommandType Function).ScriptBlock
        $parameters = $sb.Ast.Parameters
        $testname = $t
    }
    return $sb, $parameters, $testname, $testRepeat
}

function cloneTestObject ($obj, $test) {

    $newobj = New-Object -TypeName ‘System.Collections.Generic.Dictionary[[String],[Object]]’ -ArgumentList @([System.StringComparer]::CurrentCultureIgnoreCase)
    $newobj.Add('OuterRepeat', '')
    $newobj.Add('ParameterSet', '')
    $newobj.Add('ParameterSetRepeat', '')
    $newobj.Add('TestRepeat', '')
    $newobj.Add('Test', '')
    $newobj.Add('Result', '')
    $newobj.Add('Message', '')
    $newobj.Add('ExecutionTime', '')

    $obj.Keys | % { $newobj.$_ = $obj.$_ }
    if ($test -is [hashtable]) {
        $test.Keys | % { $newobj.$_ = $test.$_ }
    } else {
        $newobj.Test = $test
    }

    $newobj
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
    #$_depth++
    $global:VerbosePreference = 'Continue'
    trap { break } #This stops execution on any exception
    $ErrorActionPreference = 'Stop'

    Write-Host "Executing $FileName" -ForegroundColor Yellow
    . $FileName $Name
    #$_depth--
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
    Write-PSUtilLog "Results:`r`n    $($message.Replace("`t","`r`n    "))" $color
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
        $st
    )
    PROCESS {
        if ($st -is [System.Management.Automation.VerboseRecord]) {
            $st = $st.Message
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

            Write-PSUtilLog $st -color Cyan
        } elseif ($st -is [System.Management.Automation.WarningRecord]) {
            Write-PSUtilLog $st -color Magenta
        } else {
            $st
        }
    }
}
Write-Verbose 'Imported Module PSTest'