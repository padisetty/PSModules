trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'

function Convertto-PS ([Parameter(Mandatory=$true)]$obj,
              [Parameter(Mandatory=$false)][int]$space=0)
{
    if ($obj -is [Hashtable]) {
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
    } else {
        $obj.ToString()
    }
}

Write-Verbose 'Imported Module PSUtil'