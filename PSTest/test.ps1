Import-Module -Global PSUtil -Force -Verbose:$false

$ResultsFile = 'Results.csv'
#Remving this enables to inherit global value
Remove-Variable PSDefaultParameterValues -Force -ErrorAction Ignore -Scope local


$_depth = 0
function Invoke-PsTest (
    $Tests, 
    [Hashtable[]]$ParameterSets = @{},
    [Hashtable]$CommonParameters = @{},
    [string]$LogNamePrefix = 'PsTest'
    )
{
    $_depth++
    Set-PSUtilLogFile "$LogNamePrefix.log"

    $set = 0
    foreach ($parameterSet in $ParameterSets) {
        $set++
        $parameterSetRepeat = 1
        if ($parameterSet.PsTestParameterSetRepeat) { 
            $parameterSetRepeat = $parameterSet.PsTestParameterSetRepeat
        }

        for ($j=1; $j -le $parameterSetRepeat; $j++) {
            $obj = New-Object -TypeName ‘System.Collections.Generic.Dictionary[[String],[Object]]’ -ArgumentList @([System.StringComparer]::CurrentCultureIgnoreCase)
            copyKeys -dest $obj -source $CommonParameters
            copyKeys -dest $obj -source $parameterSet
            $obj.PsTestParameterSet = "#$set"
            $obj.PsTestParameterSetRepeat = "$j of $parameterSetRepeat"

            if ($parameterSetRepeat -gt 1 -or $ParameterSets.Count -gt 1) {
                logObject -message "Input Parameters (ParameterSet #$set, ParameterSetRepeat=$j)" -obj $parameterSet
                Write-PSUtilLog ''
            }
            foreach ($test in $Tests) {
                if ($test.PsTestParallelCount -gt 1) {
                    runParallelTest -Test $test  -obj $obj -LogNamePrefix $LogNamePrefix 
                } else {
                    runTest -Test $test -obj $obj
                }
            }
        }
    }
    $_depth--
}

function runParallelTest (
    $Test, 
    $obj,
    [string]$LogNamePrefix)
{
    $testName = getTestName($Test)
    $ps = @()
    for ($i = 1; $i -le $Test.PsTestParallelCount; $i++) {
        $file = "$LogNamePrefix.$testName.$i"

        "`$obj = $(Convertto-PS $obj)" > "$file.ps1"

        "`$test = $(Convertto-PS $Test)" >> "$file.ps1"
        "`$test.ParallelIndex = $i" >> "$file.ps1"
        "`$test.PsTestOutputObjectFile = '$file.out.ps1'" >> "$file.ps1"
        
        "runTest -test `$test -obj `$obj -LogNamePrefix '$file'" >> "$file.ps1"

        'if (-not (gfail) -and -! $Test.PsTestDisableAutoShellExit) { Stop-Process -Id $pid }' >> "$file.ps1"

        $process = Start-Process -FilePath "$PSHOME\powershell.exe" -PassThru -ArgumentList @('-NoExit', '-NoProfile', "-command . '.\$file.ps1'")
        $process.PriorityClass = 'BelowNormal'
        $ps += $process
        Write-PSUtilLog "Started $file"
    }

    for ($i = 1; $i -le $ps.Count; $i++) {
        $file = "$LogNamePrefix.$testName.$i"
        Write-PSUtilLog "Waiting for $file to complete"
        $ps[$i-1].WaitForExit()
        Write-PSUtilLog "Completed $file ExitCode=$($ps[$i-1].ExitCode)"
        cat "$file.log" >> "$LogNamePrefix.log"
        if (Test-Path "$file.out.ps1") {
            $newobjs = cat "$file.out.ps1" -Raw | Invoke-Expression
            foreach ($newobj in $newobjs) {

                #to order the results, a new object is created.
                $tempobj = newTestObject -obj $newobj
                $tempobj.PsTestParallelCount = "$i of $($Test.PsTestParallelCount)"
                $tempobj.Remove('ParallelIndex')
                logResult $tempobj

                copyKeys -dest $obj -source $newobj -keys $Test.PsTestOutputKeys -append $true 
            }
        }
        del "$file.log","$file.out.ps1","$file.ps1" -Force -EA:0
    }

    if ($obj.PsTestMaxError -le (gfail).Count)
    {
        Convert-PsTestToTableFormat    
        gstat
        gfail
        throw "Max errors reached, MaxError=$($obj.PsTestMaxError)"
    }
}

function runTest (
    $test, 
    $obj, 
    [string]$LogNamePrefix)
{
    if ($LogNamePrefix.Length -gt 0) {
        Set-PSUtilLogFile "$LogNamePrefix.log"
    }

    $sb, $parameters, $testname, $testRepeat = getExecutionContext($Test)

    for ($i = 1; $i -le $testRepeat; $i++) {
        $newobj = cloneTestObject $obj $Test
        $newobj.PsTestRepeat = "$i of $testRepeat"
        Write-PSUtilLog ''
        Write-PSUtilLog "**BEGIN '$TestName' ($i of $testRepeat)"
    
        logObject 'Before State' $newobj

        $startTime = Get-Date
        $ret = runFunction $sb $parameters $newobj
        $newobj.PsTestExecutionTime = ((Get-Date) - $startTime).ToString()

        if ($ret) {
            $newobj.PsTestResult = 'Success'
        } elseif ($newobj.OnError.Length -gt 0) {
            $sb, $parameters, $null = getExecutionContext($newobj.OnError)
            $null = runFunction $sb $parameters $newobj
        }

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

        Write-PSUtilLog "END ErrorCount = $((gfail).Count) '$testName'`r`n`r`n"

        if ($newobj.PsTestMaxError -le (gfail).Count -and $newobj.PsTestResult -ne 'Success')
        {
            gstat

            Convert-PsTestToTableFormat    
            throw "$TestName`:$($newobj.Message)"
        }

        copyKeys -dest $obj -source $newobj -keys $Test.PsTestOutputKeys -append $true
    }
}

function runFunction ($sb, $parameters, $obj) {
    foreach ($parameter in $parameters)
    {
        $paramname = $parameter.Name.VariablePath.UserPath
        if ($obj.ContainsKey($paramname)) {
            Write-PSUtilLog "    Parameter $paramname=$($obj[$paramname]) (Overritten)"
        } else {
            Write-PSUtilLog "    Parameter $paramname=$($parameter.DefaultValue) (Default Value)"
        }
    }

    try {
        $result = & { $VerbosePreference='Continue'; . $sb @obj 4>&1 3>&1 5>&1 } | extractMetric
        #$result = $sb.InvokeWithContext($null,@(), $p) 4>&1 3>&1 5>&1 | extractMetric

        if ($result -is [hashtable]) {
            logObject -message 'Return Value' -obj $result
            copyKeys -dest $obj -source $result
        }
        $ret = $true
    } catch {
        $obj.PsTestResult = 'Fail'

        $ex = $_.Exception
        $line = $_.InvocationInfo.ScriptLineNumber
        $script = (Get-Item $_.InvocationInfo.ScriptName).Name
        $message = "Error: $($ex.Message) ($script, Line #$line)" 

        Write-PSUtilLog $message -color Red

        if ($obj.PsTestMessage.Length -eq 0) {
            $obj.PsTestMessage = $message
        }
        $ret = $false        
    }
    $ret
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
    $newobj.Add('PsTestParameterSet', '')
    $newobj.Add('PsTestParameterSetRepeat', 1)
    $newobj.Add('PsTest', '')
    $newobj.Add('PsTestParallelCount', '')
    $newobj.Add('PsTestRepeat', '')
    $newobj.Add('PsTestResult', '')
    $newobj.Add('PsTestMessage', '')
    $newobj.Add('PsTestExecutionTime', '')

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
        "Test Summary so far: Success=$success, Fail=$fail percent success=$percent%"
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


function Test-PsTestExecuting ()
{
    return $_depth -gt 0
}

New-Alias -Name gstat -Value Get-PsTestStatistics -EA 0
New-Alias -Name gfail -Value Get-PsTestFailedResults -EA 0
New-Alias -Name gpass -Value Get-PsTestPassedResults -EA 0
New-Alias -Name gresults -Value Get-PsTestResults -EA 0
Export-ModuleMember -Alias * -Function * -Verbose:$false

function logResult ($obj, 
                  [ConsoleColor]$color = 'White'
)
{
    $skipkeys = @{}
    @('PsTestOnError', 'PsTestStopOnError', 'PsTestDisableAutoShellExit', 'PsTestOutputKeys', 'PsTestOutputObjectFile') | % { $skipkeys.$_ = ''}
    
    $newobj = New-Object -TypeName ‘System.Collections.Generic.Dictionary[[String],[Object]]’ -ArgumentList @([System.StringComparer]::CurrentCultureIgnoreCase)
    
    $keyorder = @()
    $obj.Keys | % { if (! $skipkeys.ContainsKey($_)) { $keyorder += $_ } }
    $skipkeys.Keys | % { if ($obj.ContainsKey($_)) { $keyorder += $_ } }

    $keyorder | % { $newobj.$_ = $obj.$_ }
    $newobj.PsTest = getTestName($newobj.PsTest)

    $st = Get-PSUtilStringFromObject $newobj
    Invoke-PSUtilRetryOnError {$st >> $ResultsFile} -RetryCount 5 -SleepTimeInMilliSeconds 10
}

function logObject ( [string]$message,
        $obj, 
        [ConsoleColor]$color = 'White'
)
{
    $st = Get-PSUtilStringFromObject $obj
    Write-PSUtilLog "$message`:`r`n    $($st.Replace("`t","`r`n    "))" $color
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
            if ($st.StartsWith('#PSTEST#', [System.StringComparison]::CurrentCultureIgnoreCase)) 
            { 
                $a = $st.Substring(8).Trim().Split('=')
                $key = ([string]$a[0]).Trim()
                $value = ([string]$a[1]).Trim()
                if ($a.Count -ne 2 -or $key.Length -eq 0 -or $value.Length -eq 0)
                {
          
                    Write-Error '#PsTest# invalid format, it has to be of the form #PsTest# x=y'
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
Write-Verbose 'Imported Module PsTest'