Import-Module -Global PSUtil -Force -Verbose:$false

$ResultsFile = 'Results.csv'
#Remving this enables to inherit global value
Remove-Variable PSDefaultParameterValues -Force -ErrorAction Ignore -Scope local


$_depth = 0
function Invoke-PsTest (
    $Tests, 
    [Hashtable]$CommonParameters = @{},
    [string]$LogNamePrefix = 'PsTest'
    )
{
    $_depth++
    #Set-PSUtilLogFile "$LogNamePrefix.log"

    try {
        $repeat = getInheritedValue -objs @($CommonParameters) -key 'PsTestSuiteRepeat' -defaultValue 1
        $maxFail = getInheritedValue -objs @($CommonParameters) -key 'PsTestSuiteMaxFail' -defaultValue 1
        $maxConsecutiveFailPerTest = getInheritedValue -objs @($CommonParameters) -key 'PsTestSuiteMaxConsecutiveFailPerTest' -defaultValue 1

        $totalFailCount = $totalSuccessCount = 0
        $consecutiveFailCount = @{}

        for ($j=1; $j -le $repeat; $j++) {
            $obj = New-Object -TypeName ‘System.Collections.Generic.Dictionary[[String],[Object]]’ -ArgumentList @([System.StringComparer]::CurrentCultureIgnoreCase)
            copyKeys -dest $obj -source $CommonParameters
            $obj.PsTestSuiteRepeat = "$j of $repeat"

            Write-Host "***BEGIN Test Suite: $j of $repeat"
            #logObject -message 'Parameters' -obj $obj

            foreach ($test in $Tests) {
                $testName = getTestName($Test)
                if ($test.PsTestParallelCount -gt 1) {
                    $ret = runParallelTest -Test $test  -obj $obj -LogNamePrefix "$LogNamePrefix.$("{0:D4}" -f $j).$testName" 
                } else {
                    $ret = runTest -Test $test -obj $obj -LogNamePrefix "$LogNamePrefix.$("{0:D4}" -f $j).$testName"
                }
                $totalFailCount += $ret.FailCount
                $totalSuccessCount += $ret.SuccessCount
                Write-Host "Current Test Summary: Test=$testName, Success=$($ret.SuccessCount), Fail=$($ret.FailCount)"
                Write-Host "Overall Summary: TestSuite Repeat=$j of $repeat, Total Success=$totalSuccessCount, Total Fail=$totalFailCount"
                Write-Host ''
                if ($ret.FailCount -gt 0) {
                    $consecutiveFailCount.$testName++
                } else  {
                    $consecutiveFailCount.$testName = 0
                }

                if ($maxConsecutiveFailPerTest -le $consecutiveFailCount.$testName) {
                    throw "TestSuite: Max consecutive failures per test reached, current ConsecutiveFailCount=$($consecutiveFailCount.$testName), MaxConsecutiveFail=$maxConsecutiveFailPerTest"
                }

                if ($ret.FailCount -gt 0) {
                    if ($test.FailBehavior -eq 'SkipTests') {
                        Write-Host "Skipping remaining tests (if any) and will continue with next SuiteRepeat as FailBehavior is set to 'SkipTests'"
                        break
                    }
                }
            }
            Write-Host "END Test Suite: $j of $repeat, TotalSucces=$totalSuccessCount, TotalFail=$totalFailCount"
            Write-Host ''
            Write-Host ''


            if ($maxFail -le $totalFailCount) {
                throw "Max TestSuite failures reached, current FailCount=$totalFailCount, MaxFail=$maxFail"
            }
        }
        $_depth--
    } catch {
        Write-Host "Error: $(Get-PsUtilExceptionMessage $_)" -ForegroundColor Red
    }
    #Convert-PsTestToTableFormat    
    $testerrors = gfail
    if ($testerrors.Count -gt 0) {
        Write-Host 'List of Errors:'
        $testerrors | %{ Write-Host $_ ; Write-Host ''}
    }
}


#true on success
function runParallelTest (
    $Test, 
    $obj,
    [string]$LogNamePrefix)
{
    $testName = getTestName($Test)
    $ps = @()
    Write-PSUtilLog "**BEGIN TEST '$testName'"
    Write-PSUtilLog "PsTestSuiteRepeat: $($obj.PsTestSuiteRepeat)"
    for ($i = 1; $i -le $Test.PsTestParallelCount; $i++) {
        $file = "$LogNamePrefix.$i"

        "`$obj = $(Convertto-PS $obj)" > "$file.ps1"

        "`$test = $(Convertto-PS $Test)" >> "$file.ps1"
        "`$test.ParallelIndex = $i" >> "$file.ps1"
        "`$test.PsTestOutputObjectFile = '$file.out.ps1'" >> "$file.ps1"
        
        "runTest -test `$test -obj `$obj -LogNamePrefix '$file'" >> "$file.ps1"

        'Stop-Process -Id $pid' >> "$file.ps1"

        $windowStyle = 'Minimized' #default is minimized
        if ($obj.PsTestMaxFail -eq 1) { #if error count is zero, assumed to run in debug model
            $windowStyle = 'Normal'
        }
        $process = Start-Process -FilePath "$PSHOME\powershell.exe" -PassThru -ArgumentList @('-NoExit', '-NoProfile', "-command . '.\$file.ps1'") -WindowStyle $windowStyle
        $process.PriorityClass = 'BelowNormal'
        $ps += $process


        Write-PSUtilLog "[$file] Started process"
    }

    $failCount = $successCount = 0
    for ($i = 1; $i -le $ps.Count; $i++) {
        $file = "$LogNamePrefix.$i"
        Write-Host "[$file] Waiting for process to exit"
        $ps[$i-1].WaitForExit()
        Write-Host "[$file] Completed ExitCode=$($ps[$i-1].ExitCode)"
        #cat "$file.log" | % {"[$i] $_"} >> "$LogNamePrefix.log"
        if (Test-Path "$file.out.ps1") {
            $newobjs = cat "$file.out.ps1" -Raw | Invoke-Expression
            foreach ($newobj in $newobjs) {
                if ($newobj.PsTestResult -eq 'Success') {
                    $successCount++
                } else {
                    $failCount++
                }
                logResult $newobj

                copyKeys -dest $obj -source $newobj -keys $Test.PsTestOutputKeys
            }
        }
        del "$file.out.ps1","$file.ps1" -Force -EA:0
    }
    Write-PSUtilLog "**END TEST '$testName'"
    Write-PSUtilLog ''
    return @{FailCount=$failCount;SuccessCount=$successCount}
}

#returns hashtable with Error and Success counts.
function runTest (
    $test, 
    $obj, 
    [string]$LogNamePrefix)
{
    $maxFail = getInheritedValue -objs @($test, $obj) -key 'PsTestMaxFail' -defaultValue 1
    $maxConsecutiveFail = getInheritedValue -objs @($test, $obj) -key 'PsTestMaxConsecutiveFail' -defaultValue 1
    $sb, $parameters, $testname, $testRepeat = getExecutionContext($Test)
    $failCount = $successCount = $consecutiveFailCount = 0
    for ($i = 1; $i -le $testRepeat; $i++) {
        
        $newobj = cloneTestObject $obj $Test
        $newobj.PsTestLog = "$LogNamePrefix.$i.log"
        $newobj.PsTestResult = 'Success'
        Set-PSUtilLogFile $newobj.PsTestLog 
        Write-PSUtilLog ''
        Write-PSUtilLog "**BEGIN TEST '$TestName' (PsTestRepeat=$i of $testRepeat)"
        Write-PSUtilLog "PsTestSuiteRepeat: $($obj.PsTestSuiteRepeat)"
    
        logObject 'Before State' $newobj -keyorder @()

        $startTime = Get-Date
        $ret = runFunction $sb $parameters $newobj
        $newobj.PsTestExecutionTime = "'$(((Get-Date) - $startTime).ToString())'"

        if ($test.PsTestOutputObjectFile) {
            if ($i -eq 1) {
                Convertto-PS $newobj > $test.PsTestOutputObjectFile
            } else {
                Convertto-PS $newobj >> $test.PsTestOutputObjectFile
            }
        } else {
            logResult $newobj
        }

        logObject 'After State' $newobj
        
        if ($ret) {
            $consecutiveFailCount = 0
            $successCount++
        } else {
            $consecutiveFailCount++
            $failCount++
            if ($newobj.PsTestOnFail.Length -gt 0) {
                Set-PSUtilTimeStamp -TimeStamp $false
                $ret = $false
                Write-PSUtilLog ''
                Write-PSUtilLog "Failure Summary: Test=$TestName"
                logObject -message 'State' -obj $newobj

                $errorsb, $errorparameters, $null = getExecutionContext($newobj.PsTestOnFail)
                $null = runFunction $errorsb $errorparameters $newobj 
                Write-PSUtilLog ''
                Set-PSUtilTimeStamp -TimeStamp $true
            }
            if ($test.FailBehavior -eq 'SkipTests') {
                break
            }
        }

        Write-PSUtilLog "Test=$testname, Result=$($newobj.PsTestResult), Message=$($newobj.PsTestMessage)"
        Write-PSUtilLog "END TEST Repeat: $i of $testRepeat, Result Count: Success=$successCount Fail=$failCount"
        Write-PSUtilLog ''

        if ($ret) {
            Remove-Item -Path $newobj.PsTestLog 
        } else {
            Move-Item $newobj.PsTestLog "error.$($newobj.PsTestLog)"
        }

        if ($maxFail -le $failCount) {
            throw "Max failures reached, current FailCount=$failCount, MaxFail=$maxFail"
        }
        if ($maxConsecutiveFail -le $consecutiveFailCount) {
            throw "Max consecutive failures reached, current ConsecutiveFailCount=$consecutiveFailCount, MaxConsecutiveFail=$maxConsecutiveFail"
        }

        copyKeys -dest $obj -source $newobj -keys $Test.PsTestOutputKeys
    }
    return @{FailCount=$failCount;SuccessCount=$successCount}
}

#returns true on success
function runFunction ($sb, $parameters, $obj) {

    $inputParams = @{}
    
    foreach ($parameter in $parameters)
    {
        $paramname = $parameter.Name.VariablePath.UserPath
        if ($paramname -eq 'PsTestObject') {
            $inputParams.PsTestObject = $obj
        } elseif ($obj.ContainsKey($paramname)) {
            $inputParams.$paramname = $obj[$paramname]
            Write-PSUtilLog "    Parameter $paramname=$($obj[$paramname]) (Overritten)"
        } else {
            Write-PSUtilLog "    Parameter $paramname=$($parameter.DefaultValue) (Default Value)"
        }
    }

    try {
        $save =$global:VerbosePreference
        $global:VerbosePreference='Continue'
        $result = &  $sb @inputParams 4>&1 3>&1 5>&1  | extractMetric
        $global:VerbosePreference = $save

        #$result = $sb.InvokeWithContext($null,@(), $p) 4>&1 3>&1 5>&1 | extractMetric

        if ($result -is [hashtable]) {
            logObject -message 'Return Value' -obj $result -keyorder @()
            copyKeys -dest $obj -source $result
        }
        $ret = $true
    } catch {
        $obj.PsTestResult = 'Fail'

        $message = Get-PsUtilExceptionMessage $_
        Write-PSUtilLog "Error: $message" -color Red

        if ($obj.PsTestMessage.Length -eq 0) {
            $obj.PsTestMessage = $message
        }
        $ret = $false        
    }
    return $ret
}

function copyKeys ($dest, $source, $keys = $source.Keys, $append = $false) {
    foreach ($k in $keys) {
        if ($append -and $obj.$k.Length -gt 0) {
            $dest.$k += ", $($source.$k)"
        } else {
            $dest.$k = $source.$k
        }
    }
}

function getTestName ($Test) {
    if ($Test -is [hashtable]) {
        $t = $Test.PsTest
    } else {
        $t = $Test
    }

    if (Test-Path $t) {
        $testname = (Get-Item $t).BaseName
    } elseif (gcm $t -EA:0) {
        $testname = $t
    } else {
        throw "Test $t not found"
    }
    return $testname
}

function getExecutionContext ($Test) {
    if ($Test -is [hashtable]) {
        $t = $Test.PsTest
        $testRepeat = $Test.PsTestRepeat
    } else {
        $t = $Test
        $testRepeat = 1
    }

    if (! $testRepeat -or $testRepeat -lt 0) {
        $testRepeat = 1
    }

    if (Test-Path $t) {
        $sb=Get-Command $t | select -ExpandProperty ScriptBlock 
        #$sb = [ScriptBlock]::Create((cat $functionName -Raw))
        $parameters = $sb.Ast.ParamBlock.Parameters
        $testname = (Get-Item $t).BaseName
    } elseif (gcm $t -EA:0) {
        $sb = (get-command $t -CommandType Function).ScriptBlock
        $parameters = $sb.Ast.Parameters
        $testname = $t
    } else {
        throw "Test $t not found"
    }
    return $sb, $parameters, $testname, $testRepeat
}

function newTestObject ($obj = $null) {
    $newobj = New-Object -TypeName ‘System.Collections.Generic.Dictionary[[String],[Object]]’ -ArgumentList @([System.StringComparer]::CurrentCultureIgnoreCase)
    $newobj.Add('PsTest', '')
    $newobj.Add('PsTestResult', '')
    $newobj.Add('PsTestMessage', '')
    $newobj.Add('PsTestExecutionTime', '')
    $newobj.Add('PsTestLog', '')

    if ($obj) {
        copyKeys -dest $newobj -source $obj 
    }
    return $newobj
}

function cloneTestObject ($obj, $test) {

    $newobj = newTestObject $obj

    if ($test -is [hashtable]) {
        copyKeys -dest $newobj -source $test
    } else {
        $newobj.PsTest = $test
    }

    $newobj
}

$defaultKeyorder = @('PsTest', 'PsTestResult', 'PsTestMessage', 'PsTestExecutionTime', 'PsTestLog')

function getFilteredStringFromObject ($obj, $keyorder = $defaultKeyorder) {
    
    $newobj = New-Object -TypeName ‘System.Collections.Generic.Dictionary[[String],[Object]]’ -ArgumentList @([System.StringComparer]::CurrentCultureIgnoreCase)
    $keyorder | % { $newobj.Add($_,'') }

    $obj.Keys | % { if ($_ -notlike 'PsTest*' -or $keyorder.Contains($_)) { $newobj.$_ = $obj.$_ } }
    if ($newobj.PsTest) { $newobj.PsTest = getTestName($newobj.PsTest)}

    return Get-PSUtilStringFromObject $newobj
}

function logResult ($obj, 
                    $keyorder = $defaultKeyorder,
                  [ConsoleColor]$color = 'White'
)
{
    $st = getFilteredStringFromObject -obj $obj -keyorder $keyorder
    Invoke-PSUtilRetryOnError {$st >> $ResultsFile} -RetryCount 5 -SleepTimeInMilliSeconds 10
}

function logObject ( [string]$message,
        $obj, 
        $keyorder = $defaultKeyorder,
        [ConsoleColor]$color = 'White'
)
{
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.Append("$message`:`r`n    ")

    $st = getFilteredStringFromObject -obj $obj -keyorder $keyorder
    $null = $sb.Append($st.Replace("`t","`r`n    "))

    Write-PSUtilLog $sb.ToString() $color
}


function getInheritedValue ($objs, $key, $defaultValue) {
    $ret = $defaultValue
    foreach ($obj in $objs) {
        if ($obj.$key) {
            $ret = $obj.$key
        }    
    }
    return $ret
}

function Invoke-PsTestRandomLoop (
    [String[]]$Tests, 
    [String]$OnError, 
    [Hashtable]$Parameters,
    [switch]$StopOnError,
    [string]$LogNamePrefix = 'Random',
    [int]$Count = 1
    )
{
    for ($i = 1; $i -le $Count; $i++)
    {
        $obj = @{}

        foreach ($key in $Parameters.keys)
        {
            $obj.$key = randomPick $Parameters.$key
        }
        Invoke-PsTest -Tests $Tests -OnError $OnError -Parameters $obj `
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
    $null = gstat
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

        $null = gstat
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
        [int]$success = ((cat $logfile | Select-String 'PsTestResult=Success').Line | measure -Line).Lines
        [int]$fail = ((cat $logfile | Select-String 'PsTestResult=Fail').Line | measure -Line).Lines
        if ($success+$fail -gt 0)
        {
            $percent = [decimal]::Round(100*$success/($success+$fail))
        }
        else
        {
            $percent = 0
        }
        Write-Verbose "Test Summary so far: Success=$success, Fail=$fail percent success=$percent%"
        return @{Success=$success;Fail=$fail;SuccessPercent=$percent}
    }
    catch
    {
        Write-Warning "$logfile not found."
    }
}

function Get-PsTestFailedResults ([string]$Filter, [string]$ResultsFileName = $ResultsFile, [switch]$OutputInSingleLine)
{
   Get-PsTestResults 'PsTestResult=Fail' $filter $ResultsFileName -OutputInSingleLine:$OutputInSingleLine
}

function Get-PsTestPassedResults ([string]$Filter, [string]$ResultsFileName = $ResultsFile, [switch]$OutputInSingleLine)
{
   Get-PsTestResults 'PsTestResult=Success' $filter $ResultsFileName -OutputInSingleLine:$OutputInSingleLine
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

    $temp = $labels
    $labels = @('PsTestSuiteRepeat', 'PsTest', 'PsTestParallelCount', 'PsTestRepeat', 'PsTestResult', 'PsTestMessage', 'PsTestExecutionTime')
    $append = @()
    foreach ($label in $temp)
    {
        if ($label -like 'PsTest*') {
            if (! $labels.Contains($label))
            {
                $append += $label
            }
        } else {
            $labels += $label
        }
    }
    $labels += $append
    
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


function Test-PsTestExecuting ()
{
    return $_depth -gt 0
}

New-Alias -Name gstat -Value Get-PsTestStatistics -EA 0
New-Alias -Name gfail -Value Get-PsTestFailedResults -EA 0
New-Alias -Name gpass -Value Get-PsTestPassedResults -EA 0
New-Alias -Name gresults -Value Get-PsTestResults -EA 0
Export-ModuleMember -Alias * -Function * -Verbose:$false

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
            if ($st.StartsWith('#PSTEST#', [System.StringComparison]::CurrentCultureIgnoreCase)) 
            { 
                $a = $st.Substring(8).Trim().Split('=')
                $key = ([string]$a[0]).Trim()
                $value = ([string]$a[1]).Trim()
                if ($a.Count -ne 2 -or $key.Length -eq 0 -or $value.Length -eq 0)
                {
                    Write-Error '#PsTest# invalid format, it has to be of the form #PsTest# x=y'
                } else {      
                    if ($obj.$key -and $obj.$key.Count -eq 1) {
                        $obj.$key = @($obj.$key, $value)
                    } elseif ($obj.$key) {
                        $obj.$key += $value
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

function Invoke-PsTestOld (
    $Tests, 
    [Hashtable[]]$ParameterSets = @{},
    [Hashtable]$CommonParameters = @{},
    [string]$LogNamePrefix = 'PsTest'
    )
{
    $_depth++
    Set-PSUtilLogFile "$LogNamePrefix.log"

    try {
        $set = 0
        foreach ($parameterSet in $ParameterSets) {
            $set++
            $parameterSetRepeat = getInheritedValue -objs @($CommonParameters, $parameterSet) -key 'PsTestParameterSetRepeat' -defaultValue 1

            for ($j=1; $j -le $parameterSetRepeat; $j++) {
                $obj = New-Object -TypeName ‘System.Collections.Generic.Dictionary[[String],[Object]]’ -ArgumentList @([System.StringComparer]::CurrentCultureIgnoreCase)
                copyKeys -dest $obj -source $CommonParameters
                copyKeys -dest $obj -source $parameterSet
                $obj.PsTestParameterSet = "#$set"
                $obj.PsTestParameterSetRepeat = "$j of $parameterSetRepeat"

                Write-PSUtilLog "***BEGIN ParameterSet: Set #$set of $($ParameterSets.Count), Repeat: $($obj.PsTestParameterSetRepeat)"
                logObject -message 'Parameters' -obj $parameterSet
                foreach ($test in $Tests) {
                    if ($test.PsTestParallelCount -gt 1) {
                        $ret = runParallelTest -Test $test  -obj $obj -LogNamePrefix $LogNamePrefix 
                    } else {
                        $ret = runTest -Test $test -obj $obj
                    }

                    if ($obj.PsTestMaxError -le (gfail).Count)
                    {
                        throw "Max errors reached, MaxError=$($obj.PsTestMaxError)"
                    }
                    if ($test.ErrorBehavior -eq 'SkipTests' -and (! $ret)) {
                        Write-PSUtilLog "Skipping remaining tests (if any) and will continue with ParameterSet as ErrorBehavior is set to 'SkipTests'"
                        break
                    }
                }
                gstat
                Write-PSUtilLog "END ParameterSet"
                Write-PSUtilLog ''
                Write-PSUtilLog ''
            }
        }
        $_depth--
    } catch {
        Write-PSUtilLog $_.Exception.Message -color Red
    }
    Convert-PsTestToTableFormat    
    $null = gstat 
    $testerrors = gfail
    if ($testerrors.Count -gt 0) {
        Write-PSUtilLog 'List of Errors:'
        $testerrors | %{ Write-PSUtilLog $_ ; Write-PSUtilLog ''}
    }
}


Write-Verbose 'Imported Module PsTest'