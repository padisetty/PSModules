# Author: Sivaprasad Padisetty
# Copyright 2013, Licensed under Apache License 2.0
#


#Converts the content of the file to a JSON object
#Where path can have a wildchar
#$paramKeyScriptBlock is a scriptblock that will return the parameter block

function GetJSONObjectFromFile ([string] $path, [ScriptBlock] $paramBlockScriptBlock = $null)
{
    $file = Get-ChildItem $path -File

    if ($file -is [System.IO.FileInfo])
    {
        Write-Verbose "Processing JSON file: $file"
        $content = Get-Content $file -Raw 
        $json = GetJSONObjectFromString -content $content -paramBlockScriptBlock $paramBlockScriptBlock
    }
    else
    {
        Write-Error "The JSON file='$path' is not found. This should map to a folder."
    }
    $json
}

function GetJSONObjectFromString ([string] $content, [ScriptBlock] $paramBlockScriptBlock = $null)
{
    $json = $content | ConvertFrom-Json

    if ($paramBlockScriptBlock -ne $null)
    {
        $paramBlock = & $paramBlockScriptBlock -JSON $json
        $savedKeys = New-Object -TypeName 'System.Collections.Specialized.StringCollection' # if RHS needs to be substituted, then save it to pass #2


        foreach ($property in $paramBlock | Get-Member -MemberType NoteProperty) # first pass load parameters which does not have references
        {
            $propertyValue = $paramBlock.($property.Name)

            if ($propertyValue -match "\[Param\.[^\]]*\]")
            {
                $savedKeys.Add($property.Name)
            }
            else
            {
                AddParameter -key $property.Name -value $propertyValue
            }
        }
    }
        
    foreach ($param in $global:params.GetEnumerator())
    {
        $key = "[Param.$($param.Key)]"
        $keyValue = $param.Value.ToString().Replace("\", "\\");
        if ($content.Contains($key))
        {
            $content = $content.Replace($key, $keyValue)
            Write-Verbose "  Parameter Substituted Key=$key Value=$($param.Value)"
        }
    }
    $json = $content | ConvertFrom-Json

    if ($paramBlockScriptBlock -ne $null)
    {
        $paramBlock = & $paramBlockScriptBlock -JSON $json
        foreach ($key in $savedKeys)  # second pass
        {
            $propertyValue = $paramBlock.($key)
            AddParameter -key $key -value $propertyValue
        }
    }

    if ($content -match "\[Param\.[^\]]*\]")
    {
        $Matches | % { Write-Verbose "The parameter $($_[0]) is not resolved" }
        Write-Error "Some parameters are still not resolved."
    }

    $json
}


function AddParameter ([string]$key, $value)
{
    if ($global:params.Contains($key))
    {
        Write-Verbose "  Parameter Overwrite $key=$value, OldValue=$($global:params[$key])"
    }
    else
    {
        Write-Verbose "  Parameter Add $key=$value"
    }
    $global:params["$key"] = $value
}

function AddParametersFromPSObject ($paramBlock)
{
    if ($paramBlock)
    {
        foreach ($key in $paramBlock | Get-Member -MemberType NoteProperty)
        {
            $propertyValue = $paramBlock.($key.Name)
            AddParameter -key $key.Name -value $propertyValue
        }
    }
}

function AddParametersFromHashtable ($paramBlock)
{
    if ($paramBlock)
    {
        foreach ($param in $paramBlock.GetEnumerator())
        {
            AddParameter -key $param.Key -value $param.Value
        }
    }
}

function RecursivePrint ([string] $objectName, $psobject, $indent="")
{
    if ($psobject -is [PSCustomObject])
    {
        Write-Verbose "$indent$objectName :"
        foreach ($property in $psobject | Get-Member -MemberType NoteProperty)
        {
            $propertyvalue = $psobject.($property.Name)

            RecursivePrint "$($property.Name)" $propertyvalue "$indent  "
        }
    }
    elseif ($psobject -is [System.Array])
    {
        Write-Verbose "$indent$objectName : Array"
        $index = 0
        foreach ($object in $psobject)
        {
            RecursivePrint "$objectName[$index]" $object  "$indent  "
            $index++;
        }
    }
    elseif ($psobject)
    {
        Write-Verbose "  $indent$objectName=$propertyvalue"
    }
    else
    {
        Write-Verbose "  $indent$objectName=null"
    }
}


$global:ErrorActionPreference = "Stop"
$global:VerbosePreference = "Continue"

#ipmo hyper-v
ipmo "hypervresource" -Force

function LoadDefaultParameters ()
{
    [Hashtable]$global:params = @{}

    AddParameter -key "MultiRoot" -value $PSScriptRoot
    $defaultJSON = GetJSONObjectFromFile -path "$PSScriptRoot\default.json" -paramBlockScriptBlock {param($JSON) $JSON.ParameterValues}
}

function execute ()
{
    param (
        [string]
        $EnvironmentPath,

        [ScriptBlock]
        $sb,

        [Hashtable]
        $OverrideParams = $null
    )
    [System.Collections.Stack]$global:paramstack = New-Object 'System.Collections.Stack'
    LoadDefaultParameters
     
    $environmentFileInfo = Get-Item  $EnvironmentPath

    if ($environmentFileInfo -isnot [System.IO.FileInfo])
    {
        Write-Error "File not found. Please make sure environment definition is found at $EnvironmentPath"
    }

    $applicationRoot = $environmentFileInfo.DirectoryName
    AddParameter -key "MultiApplicationRoot" -value $applicationRoot

    $envJSON = GetJSONObjectFromFile -path $EnvironmentPath -paramBlockScriptBlock {param($JSON) $JSON.ParameterValues}

    RecursivePrint $EnvironmentPath $envJSON

    foreach ($resource in $envJSON.Resources)
    {

        $cloneParams = New-Object 'Hashtable' -ArgumentList $global:params
        $global:paramstack.Push($cloneParams)
        foreach ($resourceExtensionReference in $resource.ResourceExtensionReferences)
        {
            AddParametersFromPSObject $resource.ResourceExtensionReferences.ResourceExtensionParameterValues
        }

        AddParametersFromHashtable -paramBlock $OverrideParams
        RecursivePrint "Resource" $json

        & $sb -resdef $resource

        $global:params = $global:paramstack.Pop()
    }
}

 
function Start-Multicle ()
{
    param (
        [string]
        $EnvironmentPath,

        [Hashtable]
        $OverrideParams = $null
    )

    Write-Verbose "Start-Multi EnvironmentPath=$EnvironmentPath"
    execute $EnvironmentPath {param($resdef) CreateResource -resdef $resdef} -OverrideParams $OverrideParams
}

function Remove-Multicle ()
{
    param (
        [string]
        $EnvironmentPath,

        [Hashtable]
        $OverrideParams = $null
    )

    Write-Verbose "Remove-Multi EnvironmentPath=$EnvironmentPath"
    execute $EnvironmentPath {param($resdef) RemoveResource -resdef $resdef} -OverrideParams $OverrideParams
}

function Clear-Multicle ()
{
    LoadDefaultParameters
    ClearResource
}
