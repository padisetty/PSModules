Import-Module -Global PSUtil -Force -Verbose:$false

$ResultsFile = 'Results.csv'
<#
function Set-PsTestDefaults ($DefaultOutputFolder)
{
    $script:PsTestDefaults = @{
        DefaultOutputFolder = Get-PSUtilDefaultIfNull $DefaultOutputFolder $PsTestDefaults.DefaultOutputFolder
    }

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
#    Set-PSUtilLogFile "$($PsTestDefaults.DefaultOutputFolder)\$LogFileName.log"
    Set-PSUtilLogFile "$LogFileName.log"
}
#>


function Get-PsTestStatistics ([string]$logfile = $ResultsFile)
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
    [Hashtable]$InputParameters = @{},
    [switch]$StopOnError,
    [string]$LogNamePrefix,
    [int]$Count = 1
    )
{
    $_depth++

    for ($i=1; $i -le $Count; $i++) {
        $obj = New-Object 'system.collections.generic.dictionary[[string],[object]]'
        $obj.Add('Tests', '')
        $obj.Add('Result', '')
        $obj.Add('Message', '')
        $obj.Add('Log', '')
        $testnames = ''
        $InputParameters.Keys | % { $obj.$_ = $InputParameters.$_ }
        foreach ($test in $Tests) {
            if (Test-Path $test) {
                $testname = (Get-Item $test).BaseName
            } else {
                $testname = $test
            }
            if ($_depth -eq 1) {
                $_LogFileName = "$LogNamePrefix$testname.$i"
            }
            if ($testnames.Length -gt 0) {
                $testnames += ', '
            }
            $testnames += $testname

            runTest -Test $test -OnError $OnError -StopOnError:$StopOnError -Index $i -Count $Count -LogFileName $_LogFileName
        }
        $obj.'Tests' = $testnames
        logStat $(Get-PSUtilStringFromObject $obj)
        gstat
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
    [String]$onError, 
    [switch]$StopOnError,
    [int]$Index,
    [int]$Count,
    [string]$LogFileName)
{
    Set-PSUtilLogFile $LogFileName
    $obj.'Log' = $LogFileName
    $Obj.'Obj' = $Obj
    try
    {
        $startTime = Get-Date

        Write-PSUtilLog ''
        Write-PSUtilLog "<<<< BEGIN $Test ($Index of $Count), Log=$LogFileName"
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
    $null = $Obj.Remove('Obj')
    Write-PSUtilLog ">>>> END $Test Result=($($obj.'Result')) ($Index of $Count), Log=$LogFileName `n"
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

    "Executing $FileName"
    & $FileName $Name
    $_depth--
    exit
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

<#
function Get-PsTestName () 
{
    $name = ''
    $stack = Get-PSCallStack
    for ($i=1; $i -lt $stack.count; $i++) {
        if ($stack[$i].ScriptName.Length -gt 0 -and $stack[$i].ScriptName -ne $stack[0].ScriptName) {
            $name = (Get-Item $stack[$i].ScriptName).BaseName
            break
        }
    }
    return $name
}


function New-PsTestOutput ($Key, $Value)
{
    $obj.Add($Key, $Value)
}

function Test-PsTestMain ()
{
    $stack = Get-PSCallStack
    for ($i=1; $i -lt $stack.count; $i++) {
        if ($stack[$i].ScriptName -ne $stack[0].ScriptName) {
            break
        }
    }
    return $i -ge $stack.count - 1
}

function Invoke-PsTestPre ()
{
#    if (Test-PSTestExecuting) {
        Write-Verbose 'Invoke-PsTestPre'
        #cd $MyInvocation.PSScriptRoot
        #$outputFolder = '.\output'
        #Remove-Item $outputFolder -ea 0 -Force -Recurse
        #Set-PsTestDefaults -DefaultOutputFolder $outputFolder

        $VerbosePreference = 'Continue'
        trap { break } #This stops execution on any exception
        $ErrorActionPreference = 'Stop'
#    }
}

function Invoke-PsTestPost ()
{
    if (Test-PsTestMain) {
       Write-Verbose 'Invoke-PsTestPost'
       Convert-PsTestToTableFormat    
    }
}
#>