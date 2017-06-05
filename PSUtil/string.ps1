trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'

#Remving this enables to inherit global value
Remove-Variable PSDefaultParameterValues -Force -ErrorAction Ignore -Scope local


function Convertto-PS ($obj,
              [Parameter(Mandatory=$false)][int]$space=0)
{
    if ($obj -eq $null) {
        '$null'
    } elseif ($obj.Keys) {
        $sb = New-Object System.Text.StringBuilder
        $null = $sb.AppendLine('@{')
            foreach ($key in $obj.Keys) {
                $null = $sb.AppendLine("$(' '*$($space+4))'$key' = $(Convertto-PS $obj.$key ($space+4))")
            }
        $null = $sb.AppendLine("$(' '*$space)}")
        return $sb.ToString()
    } elseif ($obj -is [System.Array]) {
        $sb = New-Object System.Text.StringBuilder
        $null = $sb.Append('@(')
        foreach ($o in ($obj)) {
            if ($sb.Length -gt 2) {
                $null = $sb.Append(', ')
            }
            $null = $sb.Append((Convertto-PS $o ($space+4)))
        }
        $null = $sb.Append(')')
        return $sb.ToString()
    } elseif ($obj -is [String]) {
        "'$obj'"
    } elseif ($obj -is [Boolean] -or $obj -is [System.Management.Automation.SwitchParameter]) {
        '$' + $obj.ToString()
    } else {
        $obj.ToString()
    }
}


function Get-PSUtilStringFromObject ($obj, $splitchar = "`t")
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
            $st = "$st$splitchar$key=$value"
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



Write-Verbose 'Imported Module PSUtil'