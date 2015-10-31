# Author: Sivaprasad Padisetty
# Copyright 2013, Licensed under Apache License 2.0
#

# convert <%= ... %> to $( ... )
function expandExpression ([string] $PSTemplate)
{
    $ast = ""
    $i = 0

    [Regex] $patternBegin = New-Object Regex('<%=')
    [Regex] $patternEnd = New-Object Regex('%>')
    while ($true)
    {
        $matchBegin = $patternBegin.Match($PSTemplate, $i)

        if (! $matchBegin.Success)
        {
            break;
        }

        $matchEnd = $patternEnd.Match($PSTemplate, $matchBegin.Index+2)
        if (! $matchEnd.Success)
        {
            Write-Error "%> not found at $($matchBegin.Index) for $($PSTemplate.Substring($matchBegin.Index))"
            return ""
        }

        $ast += $PSTemplate.Substring($i, $matchBegin.Index - $i)
        $ast += "`$("
        $ast += $PSTemplate.Substring($matchBegin.Index+3, $matchEnd.Index - $matchBegin.Index - 3).TrimEnd()
        $ast += ")"

        $i = $matchEnd.Index+2
    }

    #dump final block
    $ast += $PSTemplate.Substring($i, $PSTemplate.Length - $i)
    
    $ast
}

function Expand-PSTemplateString
{
    param (
        [string]
        $PSTemplate,

        [Hashtable]
        $params
    )

    if ($params)
    {
        foreach ($param in $params.GetEnumerator())
        {
            Set-Variable -Name $param.Key -Value $param.Value
        }
    }

    $ast = ""
    $i = 0

    [Regex] $patternBegin = New-Object Regex('<%[^=]')
    [Regex] $patternEnd = New-Object Regex('-%>')
    while ($true)
    {
        $matchBegin = $patternBegin.Match($PSTemplate, $i)

        if (! $matchBegin.Success)
        {
            break;
        }

        $matchEnd = $patternEnd.Match($PSTemplate, $matchBegin.Index+2)
        if (! $matchEnd.Success)
        {
            Write-Error "-%> not found at $($matchBegin.Index) for $($PSTemplate.Substring($matchBegin.Index))"
            break;
        }

        #here string
        $st = $PSTemplate.Substring($i, $matchBegin.Index - $i).TrimEnd()
        if ($st.Length -gt 0)
        {
            $ast += "@`"`n"
            #if the string has a new line as part of the begining space, get rid of it.
            $ast += expandExpression([Regex]::Replace($st, "^ *(\r\n|\n)", ""))
            $ast += "`n`"@`n"
        }

        #code fragment
        $ast += $PSTemplate.Substring($matchBegin.Index+2, $matchEnd.Index - $matchBegin.Index - 2).TrimEnd()
        $ast += "`n"

        $i = $matchEnd.Index+3
    }

    #dump final block
    $st = $PSTemplate.Substring($i, $PSTemplate.Length - $i).TrimEnd()
    if ($st.Length -gt 0)
    {
        $ast += "@`"`n"
        $ast += expandExpression([Regex]::Replace($st, "^ *(\r\n|\n)", ""))
        $ast += "`n`"@`n"
    }
    
    Invoke-Expression $ast
}

function Expand-PSTemplateFile
{
    param (
        [string]
        $InPSTemplateFile,

        [string]
        $OutFile,

        [HashTable]
        $params
    )

    if (!(Test-Path $InPSTemplateFile))
    {
        Write-Error "InPSTemplateFile $InPSTemplateFile not found"
    }

    Expand-PSTemplateString -PSTemplate (Get-Content $InPSTemplateFile -Raw) -params $params  | Out-File $OutFile
}
