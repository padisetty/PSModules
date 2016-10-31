#--------------------------------------------------------------------------------------------
#   Copyright 2014 Sivaprasad Padisetty
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http:#www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#--------------------------------------------------------------------------------------------


# Pre requisites
#   Signup for AWS and get the AccessKey & SecretKey. http://docs.aws.amazon.com/powershell/latest/userguide/pstools-appendix-signup.html
#   Read the setup instructions http://docs.aws.amazon.com/powershell/latest/userguide/pstools-getting-set-up.html
#   Install PowerShell module from http://aws.amazon.com/powershell/
#
# set the default credentials by calling something below
#   Initialize-AWSDefaults -AccessKey AKIAIOSFODNN7EXAMPLE -SecretKey wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY -Region us-east-1
#
# You need to add either publicDNSName or * to make PS remoting work for non domain machines
#    Make sure you understand the risk before doing this
#    Set-Item WSMan:\localhost\Client\TrustedHosts "*" -Force
#    It is better if you add full DNS name instead of *. Because * will match any machine name
# 
# This script focuses on on basic function, does not include security or error handling.
#
# Since this is focused on basics, it is better to run blocks of code.
#    if you are running blocks of code from ISE PSScriptRoot will not be defined.
#

Import-Module -Global 'C:\Program Files (x86)\AWS Tools\PowerShell\AWSPowerShell\AWSPowerShell.psd1' -Verbose:$false
Import-Module PSUtil -Force -Global  -Verbose:$false
trap { break } #This stops execution on any exception
$ErrorActionPreference = 'Stop'

$WinEC2Defaults = @{
    }

function Set-WinEC2Defaults ($DefaultKeypairFolder,
                            $DefaultKeypair, 
                            $DefaultSecurityGroup,
                            $DefaultInstanceType, 
                            $DefaultImagePrefix
                            )
{
    $WinEC2Defaults.DefaultKeypairFolder = Get-PSUtilDefaultIfNull $DefaultKeypairFolder $WinEC2Defaults.DefaultKeypairFolder
    $WinEC2Defaults.DefaultKeypair = Get-PSUtilDefaultIfNull $DefaultKeypair $WinEC2Defaults.DefaultKeypair
    $WinEC2Defaults.DefaultSecurityGroup = Get-PSUtilDefaultIfNull $DefaultSecurityGroup $WinEC2Defaults.DefaultSecurityGroup
    $WinEC2Defaults.DefaultInstanceType = Get-PSUtilDefaultIfNull $DefaultInstanceType $WinEC2Defaults.DefaultInstanceType
    $WinEC2Defaults.DefaultImagePrefix = Get-PSUtilDefaultIfNull $DefaultImagePrefix $WinEC2Defaults.DefaultImagePrefix
}

function Get-WinEC2Defaults ()
{
    @{
        DefaultKeypairFolder = $WinEC2Defaults.DefaultKeypairFolder
        DefaultKeypair = $WinEC2Defaults.DefaultKeypair
        DefaultSecurityGroup = $WinEC2Defaults.DefaultSecurityGroup
        DefaultInstanceType = $WinEC2Defaults.DefaultInstanceType
        DefaultImagePrefix = $WinEC2Defaults.DefaultImagePrefix
    }
}

Set-WinEC2Defaults -DefaultKeypairFolder 'c:\keys' `
        -DefaultKeypair 'winec2keypair' `
        -DefaultSecurityGroup 'winec2securitygroup' `
        -DefaultInstanceType 't2.medium' `
        -DefaultImagePrefix 'Windows_Server-2012-R2_RTM-English-64Bit-Base'

function Test-WinEC2 ()
{
    $result = 'Ok'
    'Your Defaults:'
    Get-WinEC2Defaults

    [string]$trustedhosts = (Get-Item WSMan:\localhost\Client\TrustedHosts).value
    if ($trustedhosts.Length -eq 0)
    {
        Write-Warning 'TrustedHosts value is not set, PS remoting for non domain joined machines will not work.'
        Write-Warning ' Add the name of specifc host (more secure) or * wide open (e.g)'
        Write-Warning ' Set-Item WSMan:\localhost\Client\TrustedHosts "*" -Force'
        $result = 'Fail'
    }

    if (!$trustedhosts.Contains('*'))
    {
        Write-Warning 'TrustedHosts does not contain "*", means you need to add the name of each non domain joined host that you will connect using PS'
        $result = 'Fail'
    }

    $list = Get-AWSCredentials -ListStoredCredentials
    if (!$list.Contains('default') -and !$list.Contains('AWS PS Defaults'))
    {
        Write-Warning 'Default credentials are not stored in the profile store. Use "Set-AWSCredentials -AccessKey AKIAIOSFODNN7EXAMPLE -SecretKey wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY -StoreAs default"' 
        $result = 'Fail'
    }

    $keys = Get-WinEC2KeyPair

    if ($keys -and $keys.Status.Contains('Bad'))
    {
        Write-Warning "Some keypairs are not in sync with pem files located in $($WinEC2Defaults.DefaultKeypairFolder)"
        $keys
        $result = 'Fail'
    }

    if (!$keys -or !$keys.KeyName.Contains($WinEC2Defaults.DefaultKeypair))
    {
        Write-Warning "Keypair with name $($WinEC2Defaults.DefaultKeypair) not found"
        $result = 'Fail'
    }

    $groups = Get-EC2SecurityGroup
    if (!$groups.GroupName.Contains($WinEC2Defaults.DefaultSecurityGroup))
    {
        Write-Warning "SecurityGroup with name $($WinEC2Defaults.DefaultSecurityGroup) not found, you can run 'Update-WinEC2FireWallSource' to create it"
        $result = 'Fail'
    }

    ''
    "Result=$result"
}

function findInstance
{
    param (
        [Parameter (Position=1)][string]$NameOrInstanceIds = '*',
        [Parameter(Position=2)][string]$DesiredState
    )

    $filters = @()
    $NameOrInstanceIds = $NameOrInstanceIds.Trim()
    if ($NameOrInstanceIds.Length -gt 0 -and $NameOrInstanceIds -ne '*')
    {
        $filter = New-Object Amazon.EC2.Model.Filter
        if ($NameOrInstanceIds.StartsWith('i-'))
        {
            $filter.Name = "instance-id"
        }
        else
        {
            $filter.Name = "tag:Name"
        }
        $NameOrInstanceIds.Split(',') | %{$filter.Values.Add($_.Trim())}
        $filters += $filter
    }

    $DesiredState = $DesiredState.Trim()
    if ($DesiredState.Length -eq 0)
    {
        $DesiredState = 'running,pending,shutting-down,stopping,stopped'
    }
    if ($DesiredState -ne '*')
    {
        $filter = New-Object Amazon.EC2.Model.Filter
        $filter.Name = 'instance-state-name'
        $DesiredState.Split(',') | %{$filter.Values.Add($_.Trim())}
        $filters += $filter
    }

    (Get-EC2Instance -Filter $filters).Instances
}

$DefaultRegion = 'us-east-1'
function getAndSetRegion ([string]$Region)
{
    if ($Region.Length -gt 0) 
    {
        Set-DefaultAWSRegion $Region
    }
    else
    {
        $Region = Get-DefaultAWSRegion
        if ($Region.Length -eq 0) 
        {
            $Region = $DefaultRegion 
            Set-DefaultAWSRegion $Region
        }
    }
    $Region
}

function Get-WinEC2Instance
{
    param (
        [Parameter (Position=1)][string]$NameOrInstanceIds = '*',
        [Parameter(Position=2)][string]$DesiredState,
        [Parameter(Position=3)][string]$Region
    )

    $Region = . getAndSetRegion $Region # Execute in current context for Set-DefaultAWSRegion

    $instances = findInstance -NameOrInstanceIds $NameOrInstanceIds -DesiredState $DesiredState
    foreach ($instance in $instances)
    {
        getWinInstanceFromEC2Instance $instance
    }
}

function Get-WinEC2ConsoleOutput
{
    param (
        [Parameter (Position=1)][string]$NameOrInstanceIds = '*',
        [Parameter(Position=2)][string]$Region
    )
    $Region = . getAndSetRegion $Region # Execute in current context for Set-DefaultAWSRegion

    $instances = findInstance -nameOrInstanceIds $NameOrInstanceIds -DesiredState '*'
    foreach ($instance in $instances)
    {
         $consoleLog = (Get-EC2ConsoleOutput $instance.instanceid).Output
        [System.Text.Encoding]::ascii.GetString([System.Convert]::FromBase64String($consoleLog))
    }
}

function New-WinEC2Instance
{
    param (
        [string]$InstanceType = $WinEC2Defaults.DefaultInstanceType,
        [string]$ImagePrefix = $WinEC2Defaults.DefaultImagePrefix,
            #'Windows_Server-2012-R2_RTM-English-64Bit-GP2-', 
            # Windows_Server-2008-R2_SP1-English-64Bit-Base
            # Windows_Server-2012-RTM-English-64Bit-SQL_2012_SP1_Standard
            # Windows_Server-2012-RTM-English-64Bit-Base
        [string]$AmiId,
        [string]$KeyPairName = $WinEC2Defaults.DefaultKeypair,
        [string[]]$SecurityGroupName = $WinEC2Defaults.DefaultSecurityGroup,
        [string]$Region,
        [string]$Password = $null, # if the password is already baked in the image, specify the password
        [string]$NewPassword = $null, # change the passowrd to this new value
        [string]$Name = $null,
        [switch]$RenameComputer, # if set, will rename computer to match with $Name
        [string]$PrivateIPAddress = $null,
        [string]$SubnetId = $null,
        [int32]$IOPS = 0,
        [ValidateSet('gp2','io1','standard')][string]$VolumeType = 'gp2',
        [int]$VolumeSize = 0,
        [switch]$DontCleanUp, # Don't cleanup EC2 instance on error
        [string]$Placement_AvailabilityZone = $null,
        [string]$AdditionalInfo,
        [string]$IamRoleName, # InstanceProfile_Id
        [int]$Timeout = 500,
        [switch]$IgnorePing,
        [int]$Port=80,
        [int]$InstanceCount=1,
        [switch]$Linux,
        [switch]$SSMHeartBeat,
        [string]$UserData = @"
<powershell>
Enable-NetFirewallRule FPS-ICMP4-ERQ-In
Set-NetFirewallRule -Name WINRM-HTTP-In-TCP-PUBLIC -RemoteAddress Any
New-NetFirewallRule -Name "WinRM80" -DisplayName "WinRM80" -Protocol TCP -LocalPort 80
Set-Item WSMan:\localhost\Service\EnableCompatibilityHttpListener -Value true
#Set-Item (dir wsman:\localhost\Listener\*\Port -Recurse).pspath 80 -Force
$(if ($Name -eq $null -or (-not $RenameComputer)) { 'Restart-Service winrm' }
  else {"Rename-Computer -NewName '$Name';Restart-Computer" }
)
</powershell>
"@

        )

    trap { break } #This stops execution on any exception
    $ErrorActionPreference = 'Stop'
    $Region = . getAndSetRegion $Region # Execute in current context for Set-DefaultAWSRegion
    Write-Verbose ("New-WinEC2Instance InstanceType=$InstanceType, " + 
            "AmiId=$AmiId, ImagePrefix=$ImagePrefix, Region=$Region, " +
            "KeyPairName=$KeyPairName, SecurityGroupName=$SecurityGroupName, " +
            "Name=$Name, RenameComputer=$RenameComputer, " + 
            "SubnetId=$SubnetId, PrivateIPAddress=$PrivateIPAddress, " +
            "IOPS=$IOPS, VolumeType=$VolumeType, VolumeSize=$VolumeSize, DontCleanUp=$DontCleanUp, " + 
            "Placement_AvailabilityZone=$Placement_AvailabilityZone, AdditionalInfo=$AdditionalInfo, " + 
            "IamRoleName(InstanceProfile_Id)=$IamRoleName, Timeout=$Timeout")
    $instanceid = $null
    try
    {
        if (-not $Password)
        {
            $keyfile = Get-WinEC2KeyFile $KeyPairName
        }
        #Find the image name
        if ($AmiId.Length -gt 0)
        {
            $a = Get-EC2Image $AmiId
            Write-Verbose $a[$a.Length-1].Name
        }
        else
        {
            $a = Get-EC2Image -Filters @{Name = "name"; Values = "$imageprefix*"} | sort -Property CreationDate -Descending | select -First 1
        }
        if ($a -eq $null)
        {
            Write-Error "AMI not found. AmiId=$AmiId, ImagePrefix=$imageprefix"
            return
        }
        $imageid = $a.ImageId
        $imagename = $a.Name
        Write-Verbose "imageid=$imageid, imagename=$imagename"

        #Launch the instance
        $userdataBase64Encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userdata))
        $parameters = @{
            ImageId = $imageid
            MinCount = $InstanceCount
            MaxCount = $InstanceCount
            AssociatePublicIp = $true
            InstanceType = $InstanceType
            KeyName = $KeyPairName
            #SecurityGroupIds = (Get-EC2SecurityGroup -Filter @{Name='group-name'; Value=$SecurityGroupName}).GroupId
            UserData = $userdataBase64Encoded
            SubnetId = $SubnetId
        }
        if ($Placement_AvailabilityZone)
        {
            $parameters.'Placement_AvailabilityZone' = $Placement_AvailabilityZone
        }
        if ($AdditionalInfo)
        {
            $parameters.'AdditionalInfo' = $AdditionalInfo
        }
        if ($PrivateIPAddress)
        {
            $parameters.'PrivateIPAddress' = $PrivateIPAddress
            foreach ($subnet in Get-EC2Subnet)
            {
                if (checkSubnet $subnet.CidrBlock $PrivateIPAddress)
                {
                    $parameters.'SubnetId' = $subnet.SubnetId
                    break
                }
            }
            if (-not $parameters.ContainsKey('SubnetId'))
            {
                throw "Matching subnet for $PrivateIPAddress not found"
            }
        }

        #EBS Volume
        $Volume = New-Object Amazon.EC2.Model.EbsBlockDevice
        $Volume.DeleteOnTermination = $True
        if ($VolumeSize -gt 0)
        {
            $Volume.VolumeSize = $VolumeSize
        }
        
        if ($IOPS -eq 0)
        {
            $Volume.VolumeType = $volumetype
        }
        else
        {
            $Volume.VolumeType = 'io1'
            $volume.IOPS = $IOPS
            $parameters.'EbsOptimized' = $True
        }
        $Mapping = New-Object Amazon.EC2.Model.BlockDeviceMapping
        #$Mapping.DeviceName = '/dev/sda1'
        $Mapping.DeviceName = $a.RootDeviceName
        $Mapping.Ebs = $Volume
        $parameters.'BlockDeviceMapping' = $Mapping

        #Network
        $interface = New-Object Amazon.EC2.Model.InstanceNetworkInterfaceSpecification
        $interface.Groups = (Get-EC2SecurityGroup -Filter @{Name='group-name'; Value=$SecurityGroupName}).GroupId
        $interface.DeleteOnTermination = $true
        $interface.DeviceIndex = 0
        $interface.AssociatePublicIpAddress = $true
        $parameters.'NetworkInterface' = $interface


        if ($IamRoleName)
        {
            $parameters.'InstanceProfile_Id' = $IamRoleName
        }

        $startTime = Get-Date
        $instances = (New-EC2Instance @parameters).Instances

        $time = @{}
        #$awscred = (Get-AWSCredentials -StoredCredentials 'AWS PS Default').GetCredentials()
        #$ec2clinet = New-Object Amazon.EC2.AmazonEC2Client($awscred.AccessKey,$awscred.SecretKey,$DefaultRegionEndpoint)
        #$resp = $ec2clinet.RunInstances($parameters)
        #$instance = $resp.RunInstancesResult.Reservation.Instances[0]
        #$ec2clinet = $null

        Write-Verbose "instanceid=$($instances.InstanceId)"

        if ($Name)
        {
            Invoke-PSUtilRetryOnError {New-EC2Tag -ResourceId $instances.InstanceId -Tag @{Key='Name'; Value=$Name}}
        }

        foreach ($instance in $instances) {
            $instanceId = $instance.InstanceId
            Write-Verbose "InstanceId=$instanceId"


            $cmd = { $(Get-EC2Instance -Filter @{Name = "instance-id"; Values = $instanceid}).Instances[0].State.Name -eq "Running" }
            $a = Invoke-PSUtilWait $cmd "New-WinEC2Instance - running state" $Timeout
            $time.'Running' = (Get-Date) - $startTime
            Write-Verbose ('New-WinEC2Instance - {0:mm}:{0:ss} - to running state' -f ($time.Running))
        
            #Wait for ping to succeed
            $a = Get-EC2Instance -Filter @{Name = "instance-id"; Values = $instanceid}
            $PublicIpAddress = $a.Instances[0].PublicIpAddress

            if (-not $IgnorePing) {
                $cmd = { ping $PublicIpAddress; $LASTEXITCODE -eq 0}
                $a = Invoke-PSUtilWait $cmd "New-WinEC2Instance - ping" $Timeout
                $time.'Ping' = (Get-Date) - $startTime
                Write-Verbose ('New-WinEC2Instance - {0:mm}:{0:ss} - to ping to succeed' -f ($time.Ping))
            }

            if (-not $Linux) {
                #Wait until the password is available
                if (-not $Password)
                {
                    $cmd = {Get-EC2PasswordData -InstanceId $instanceid -PemFile $keyfile -Decrypt}
                    $Password = Invoke-PSUtilWait $cmd "New-WinEC2Instance - retreive password" $Timeout
                    $time.'Password' = (Get-Date) - $startTime
                    Write-Verbose ('New-WinEC2Instance - {0:mm}:{0:ss} - to retreive password' -f ($time.Password))
                }

                $securepassword = ConvertTo-SecureString $Password -AsPlainText -Force
                $creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)

                $cmd = {New-PSSession $PublicIpAddress -Credential $creds -Port $Port}
                $s = Invoke-PSUtilWait $cmd "New-WinEC2Instance - remote connection" $Timeout

                if ($NewPassword)
                {
                    #Change password
                    $cmd = { param($password)	
                                $admin=[adsi]("WinNT://$env:computername/administrator, user")
                                $admin.psbase.invoke('SetPassword', $password) }
        
                    try
                    {
                        $null = Invoke-Command -Session $s $cmd -ArgumentList $NewPassword 2>$null
                    }
                    catch # sometime it gives access denied error. ok to mask this error, the next connect will fail if there is an issue.
                    {
                    }
                    Write-Verbose 'Completed setting the new password.'
                    Remove-PSSession $s
                    $securepassword = ConvertTo-SecureString $NewPassword -AsPlainText -Force
                    $creds = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)
                    $s = New-PSSession $PublicIpAddress -Credential $creds -Port $Port
                    Write-Verbose 'Test connection established using new password.'
                }
                Remove-PSSession $s
                $time.'Remote' = (Get-Date) - $startTime
                Write-Verbose ('New-WinEC2Instance - {0:mm}:{0:ss} - to establish remote connection' -f ($time.Remote))
            }

            if ($SSMHeartBeat) {
                $cmd = { (Get-SSMInstanceInformation -InstanceInformationFilterList @{ Key='InstanceIds'; ValueSet=$instanceid}).Count -eq 1}
                $null = Invoke-PSUtilWait $cmd 'Instance Registration' $Timeout
                $time.'SSMHeartBeat' = (Get-Date) - $startTime
                Write-Verbose ('New-WinEC2Instance - {0:mm}:{0:ss} - for SSM Heart Beat' -f ($time.SSMHeartBeat))
            }
        }

        $wininstancce = Get-WinEC2Instance ($instances.InstanceId -join ',')

        $wininstancce | Add-Member -NotePropertyName 'Time' -NotePropertyValue $time
        $wininstancce
    }
    catch
    {
        Write-Warning "Error: $($_.Exception.Message)"
        if ($instanceid -ne $null -and (-not $DontCleanUp))
        {
            Write-Verbose "Terminate InstanceId=$instanceid"
            $null = Remove-EC2Instance -Instance $instanceid -Force
        }
        throw $_.Exception
    }
}

function Remove-WinEC2Instance (
        [Parameter (Position=1, Mandatory=$true)][string]$NameOrInstanceIds,
        [Parameter (Position=2)][string]$DesiredState,
        [Parameter (Position=3)][switch]$NoWait,
        [Parameter (Position=4)][string]$Region
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    $Region = . getAndSetRegion $Region # Execute in current context for Set-DefaultAWSRegion
    Write-Verbose "Remove-WinEC2Instance - NameOrInstanceIds=$NameOrInstanceIds, Region=$Region"

    $instances = findInstance -nameOrInstanceIds $NameOrInstanceIds -DesiredState $DesiredState 
    foreach ($instance in $instances)
    {
        $a = Remove-EC2Instance -Instance $instance.InstanceId -Force

        if (!$NoWait)
        {
            $cmd = { $(Get-EC2Instance -Instance $instance.InstanceId).Instances[0].State.Name -eq 'terminated' }
            $a = Invoke-PSUtilWait $cmd "Remove-WinEC2Instance NameOrInstanceId=$($instance.InstanceId) - terminate state" 1500
        }
        Write-Verbose "Remove-WinEC2Instance - Removed InstanceId=$($instance.InstanceId)"
    }
}

function Stop-WinEC2Instance (
        [Parameter (Position=1, Mandatory=$true)][string]$NameOrInstanceIds,
        [Parameter (Position=2)][switch]$NoWait,
        [Parameter(Position=3)][string]$Region
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    $Region = . getAndSetRegion $Region # Execute in current context for Set-DefaultAWSRegion
    Write-Verbose "Stop-WinEC2Instance - NameOrInstanceIds=$NameOrInstanceIds, Region=$Region"

    $instances = findInstance $NameOrInstanceIds
    foreach ($instance in $instances)
    {
        if ($instance.State.Name -ne 'running')
        {
            throw "$($instance.InstanceId) is in $($instance.State.Name), only instance in running state can be stopped"
        }

        $InstanceId = $instance.InstanceId

        $a = Stop-EC2Instance -Instance $InstanceId -ForceStop

        if (! $NoWait)
        {
            $cmd = { (Get-EC2Instance -Instance $InstanceId).Instances[0].State.Name -eq "Stopped" }
            $a = Invoke-PSUtilWait $cmd "Stop-WinEC2Instance InstanceId=$InstanceId- Stopped state" 450
        }
    }
}

function Start-WinEC2Instance (
        [Parameter (Position=1, Mandatory=$true)]$NameOrInstanceIds,
        [System.Management.Automation.PSCredential][Parameter(Position=2)]$Credential,
        [switch]$IsReachabilityCheck,
        [int]$WaitTime = 600,
        [int]$Port = 80,
        [Parameter(Position=3)]$Region
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    $Region = . getAndSetRegion $Region # Execute in current context for Set-DefaultAWSRegion
    Write-Verbose "Start-WinEC2Instance - NameOrInstanceId=$NameOrInstanceIds, Region=$Region"
    $parameters = @{}
    if ($Credential)
    {
        $parameters.'Credential' = $Credential
    }

    $instances = findInstance $NameOrInstanceIds

    foreach ($instance in $instances)
    {
        if ($instance.State.Name -ne 'stopped')
        {
            throw "$($instance.InstanceId) is in $($instance.State.Name), only instance in stopped state can be started"
        }

        $startTime = Get-Date

        $InstanceId = $instance.InstanceId
 
        $a = Start-EC2Instance -Instance $InstanceId

        $cmd = { $(Get-EC2Instance -Instance $InstanceId).Instances[0].State.Name -eq "running" }
        $a = Invoke-PSUtilWait $cmd "Start-WinEC2Instance - running state" $WaitTime

        #Wait for ping to succeed
        $instance = (Get-EC2Instance -Instance $InstanceId).Instances[0]
        $PublicIpAddress = $instance.PublicIpAddress

        Write-Verbose "PublicIpAddress = $($instance.PublicIpAddress)"

        $cmd = { ping  $PublicIpAddress; $LASTEXITCODE -eq 0}
        $a = Invoke-PSUtilWait $cmd "Start-WinEC2Instance - ping" $WaitTime

        $cmd = {New-PSSession $PublicIpAddress @parameters -Port $Port}
        $s = Invoke-PSUtilWait $cmd "Start-WinEC2Instance - Remote connection" $WaitTime
        Remove-PSSession $s

        if ($IsReachabilityCheck)
        {
            $cmd = { $(Get-EC2InstanceStatus $InstanceId).Status.Status -eq 'ok'}
            $a = Invoke-PSUtilWait $cmd "Start-WinEC2Instance - Reachabilitycheck" $WaitTime
        }

        Write-Verbose ('Start-WinEC2Instance - {0:mm}:{0:ss} - to start' -f ((Get-Date) - $startTime))
    }
}

function ReStart-WinEC2Instance (
        [Parameter (Position=1, Mandatory=$true)]$NameOrInstanceIds,
        [System.Management.Automation.PSCredential][Parameter(Position=2)]$Credential,
        [switch]$IsReachabilityCheck,
        [int]$Port = 80,
        [Parameter(Position=3)]$Region
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    $Region = . getAndSetRegion $Region # Execute in current context for Set-DefaultAWSRegion
    Write-Verbose "ReStart-WinEC2Instance - NameOrInstanceId=$NameOrInstanceIds, Region=$Region"
    $parameters = @{}
    if ($Credential)
    {
        $parameters.'Credential' = $Credential
    }

    $instances = findInstance $NameOrInstanceIds 'running'

    foreach ($instance in $instances)
    {
        $startTime = Get-Date
        $InstanceId = $instance.InstanceId
        $PublicIpAddress = $instance.PublicIpAddress
 
        $a = Restart-EC2Instance -Instance $InstanceId

        #Wait for ping to fail
        $cmd = { ping  $PublicIpAddress; $LASTEXITCODE -ne 0}
        $a = Invoke-PSUtilWait $cmd "ReStart-WinEC2Instance - ping to fail" 450

        #Wait for ping to succeed
        $cmd = { ping  $PublicIpAddress; $LASTEXITCODE -eq 0}
        $a = Invoke-PSUtilWait $cmd "ReStart-WinEC2Instance - ping to succeed" 450

        #wait for remote PS connection to establish
        $cmd = {New-PSSession $PublicIpAddress @parameters -Port $Port}
        $s = Invoke-PSUtilWait $cmd "ReStart-WinEC2Instance - Remote connection" 300
        Remove-PSSession $s
        
        if ($IsReachabilityCheck) {
            $cmd = { $(Get-EC2InstanceStatus $InstanceId).Status.Status -eq 'ok'}
            $a = Invoke-PSUtilWait $cmd "ReStart-WinEC2Instance - Reachabilitycheck" 600
        }
        Write-Verbose ('ReStart-WinEC2Instance - {0:mm}:{0:ss} - to restart' -f ((Get-Date) - $startTime))
    }
}

function Invoke-WinEC2Command (
        [Parameter (Position=1, Mandatory=$true)][string]$NameOrInstanceIds,
        [Parameter(Position=2, Mandatory=$true)][ScriptBlock]$sb,
        [Parameter(Position=3)][PSCredential]$Credential,
        [Object[]]$ArguementList,
        [int]$Port=80,
        [Parameter(Position=4)][string]$Region
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    $Region = . getAndSetRegion $Region # Execute in current context for Set-DefaultAWSRegion
    Write-Verbose "Invoke-WinEC2Command - NameOrInstanceIds=$NameOrInstanceIds, ScriptBlock=$sb, Region=$Region"

    $parameters = @{}
    $instances = findInstance $NameOrInstanceIds 'running'
    foreach ($instance in $instances)
    {
        if ($Credential)
        {
            $parameters.'Credential' = $Credential
        } else {
            $data = Get-WinEC2Password $instance.InstanceId
            $parameters.'Credential' = $data.Credential
        }
        Invoke-Command -ComputerName $instance.PublicIpAddress -Port $Port -ScriptBlock $sb @parameters -ArgumentList $ArguementList
    }
}

function Connect-WinEC2Instance (
        [Parameter (Position=1, Mandatory=$true)]$NameOrInstanceId,
        $Region
    )
{
    trap { break }
    $Region = . getAndSetRegion $Region # Execute in current context for Set-DefaultAWSRegion

    $instance = findInstance $NameOrInstanceId 'running'
    mstsc /v:$($instance.PublicIpAddress)
}

function checkSubnet ([string]$cidr, [string]$ip)
{
    $network, [int]$subnetlen = $cidr.Split('/')
    $a = [uint32[]]$network.split('.')
    [uint32] $unetwork = ($a[0] -shl 24) + ($a[1] -shl 16) + ($a[2] -shl 8) + $a[3]
    $mask = (-bnot [uint32]0) -shl (32 - $subnetlen)

    $a = [uint32[]]$ip.split('.')
    [uint32] $uip = ($a[0] -shl 24) + ($a[1] -shl 16) + ($a[2] -shl 8) + $a[3]

    $unetwork -eq ($mask -band $uip)
}

function Get-WinEC2Password (
        [Parameter (Position=1)]$NameOrInstanceId = '*',
        [Parameter (Position=2)][Switch]$PlainText,
        [Parameter(Position=3)][string]$Region
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    $Region = . getAndSetRegion $Region # Execute in current context for Set-DefaultAWSRegion
    Write-Verbose "Get-WinEC2Password - NameOrInstanceId=$NameOrInstanceId, Region=$Region"

    $instances = findInstance $NameOrInstanceId
    foreach ($instance in $instances)
    {
        $data = New-Object 'PSObject'
        $wininstance = getWinInstanceFromEC2Instance $instance
        $data | Add-Member -NotePropertyName 'InstanceId' -NotePropertyValue $wininstance.InstanceId
        if ($wininstance.TagName -ne $null)
        {
            $data | Add-Member -NotePropertyName 'Name' -NotePropertyValue $wininstance.TagName
        }
        $password = Get-EC2PasswordData -InstanceId $instance.InstanceId -PemFile (Get-WinEC2KeyFile $instance.KeyName) -Decrypt
        $securepassword = ConvertTo-SecureString $password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ("Administrator", $securepassword)
        if ($PlainText) {
            $data | Add-Member -NotePropertyName 'Password' -NotePropertyValue $password
        }
        $data | Add-Member -NotePropertyName 'PublicIPAddress' -NotePropertyValue $wininstance.PublicIPAddress
        $data | Add-Member -NotePropertyName 'Credential' -NotePropertyValue $credential


        $data
    }
}

function getWinInstanceFromEC2Instance ($instance)
{
    $obj = New-Object PSObject 
    $obj | Add-Member -NotePropertyName 'InstanceId' -NotePropertyValue $instance.InstanceId
    $obj | Add-Member -NotePropertyName 'State' -NotePropertyValue $instance.State.Name
    $obj | Add-Member -NotePropertyName 'PublicIpAddress' -NotePropertyValue $instance.PublicIpAddress
    $obj | Add-Member -NotePropertyName 'PublicDNSName' -NotePropertyValue $instance.PublicDNSName
    $obj | Add-Member -NotePropertyName 'PrivateIpAddress' -NotePropertyValue $instance.PrivateIpAddress
    $obj | Add-Member -NotePropertyName 'NetworkInterfaces' -NotePropertyValue $instance.NetworkInterfaces
    $obj | Add-Member -NotePropertyName 'InstanceType' -NotePropertyValue $instance.InstanceType
    $obj | Add-Member -NotePropertyName 'KeyName' -NotePropertyValue $instance.KeyName
    $obj | Add-Member -NotePropertyName 'ImageId' -NotePropertyValue $instance.ImageId
    $obj | Add-Member -NotePropertyName 'Instance' -NotePropertyValue $instance

    foreach ($tag in $instance.Tag)
    {
        $obj | Add-Member -NotePropertyName ('Tag' + $tag.Key) -NotePropertyValue $tag.Value
    }

    $obj
}

function New-WinEC2KeyPair (
        [Parameter (Position=1)]$KeyPairName = $WinEC2Defaults.DefaultKeypair,
        [Parameter(Position=2)]$Region
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    $Region = . getAndSetRegion $Region # Execute in current context for Set-DefaultAWSRegion

    $KeyFile="$($WinEC2Defaults.DefaultKeypairFolder)\$KeyPairName"

    if (Get-EC2KeyPair  | ? { $_.KeyName -eq $KeyPairName }) { 
        Write-Verbose "Skipping as keypair ($KeyPairName) already present." 
        return
    }

    if (Test-Path "$KeyFile.pub") {
        $publicKeyMaterial = cat "$KeyFile.pub" -Raw
        $encodedPublicKeyMaterial = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($publicKeyMaterial))
        Import-EC2KeyPair -KeyPairName $KeyPairName -PublicKeyMaterial $encodedPublicKeyMaterial
        Write-Verbose "Importing KeyPairName=$KeyPairName, keyfile=$KeyFile"
    } else {
        Write-Verbose "Creating KeyPairName=$KeyPairName, keyfile=$KeyFile"
        $keypair = New-EC2KeyPair -KeyName $KeyPairName
        "$($keypair.KeyMaterial)" | Out-File -encoding ascii -filepath "$KeyFile.pem"
        "$($keypair.KeyFingerprint)" | Out-File -encoding ascii -filepath "$KeyFile.fingerprint"
    }
}

function Remove-WinEC2KeyPair (
        [string][Parameter (Position=1)]$KeyPairName = $WinEC2Defaults.DefaultKeypair,
        [string]$Region
    )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    $Region = . getAndSetRegion $Region # Execute in current context for Set-DefaultAWSRegion
    Write-Verbose "Remove-WinEC2KeyPair - KeyPairName=$KeyPairName"

    if (Get-EC2KeyPair -KeyNames $KeyPairName)
    {
        Remove-EC2KeyPair -KeyName $KeyPairName -Force
    }
}


function Get-WinEC2KeyPair (
        [string][Parameter (Position=1)]$KeyPairName,
        [string]$Region
        )
{
    trap { break }
    $ErrorActionPreference = 'Stop'
    $Region = . getAndSetRegion $Region # Execute in current context for Set-DefaultAWSRegion

    if ($KeyPairName)
    {
        $keys = Get-EC2KeyPair $KeyPairName
    }
    else
    {
        $keys = Get-EC2KeyPair
    }
    
    foreach ($key in $keys)
    {
        $obj = New-Object PSObject
        $obj | Add-Member -MemberType NoteProperty -Name 'KeyName' -Value $key.KeyName
        $obj | Add-Member -MemberType NoteProperty -Name 'Status' -Value 'Bad'
        $obj | Add-Member -MemberType NoteProperty -Name 'PemFile' -Value 'NOT Found'
        $obj | Add-Member -MemberType NoteProperty -Name 'KeyFingerprint' -Value $key.KeyFingerprint

        $file = "$($WinEC2Defaults.DefaultKeypairFolder)\$($key.KeyName).pem"
        if (Test-Path $file)
        {
            $obj.PemFile = $file
            if (!(cat $file | Select-String $key.KeyFingerprint))
            {
                $obj.KeyFingerPrint = 'Finger print mismatched'
            }
            else
            {
                $obj.Status = 'Good'
            }
        }
        $obj
    }
}


function Get-WinEC2KeyFile (
        [string][Parameter (Position=1)]$KeyPairName = $WinEC2Defaults.DefaultKeypair
    )
{
    trap { break }
    $keyfile = "$($WinEC2Defaults.DefaultKeypairFolder)\$KeyPairName.pem"
    Write-Verbose "Test-WinEC2KeyPair - Keyfile=$keyfile"

    if (-not (Test-Path $keyfile -PathType Leaf))
    {
        throw "Test-WinEC2KeyPair - Keyfile=$keyfile Not Found"
    }

    if (-not (Get-EC2KeyPair -KeyNames $KeyPairName))
    {
        $keyfile = $null
        throw "Test-WinEC2KeyPair - KeyPair with name=$KeyPairName not found in Folder=$($WinEC2Defaults.DefaultKeypairFolder)"
    }

    $keyfile
}

function Update-WinEC2FireWallSource
{
    param (
        $SecurityGroupName = 'allow-my-ip',
        $Region,
        [Amazon.EC2.Model.IpPermission[]] $IpCustomPermissions = @() #Not implemented yet
    )

    trap {break }
    $ErrorActionPreference = 'Stop'
    $Region = . getAndSetRegion $Region # Execute in current context for Set-DefaultAWSRegion

    if ($securityGroup = (Get-EC2SecurityGroup | ? { $_.GroupName -eq $securityGroupName })) {
        Write-Verbose "Skipping as SecurityGroup ($securityGroupName) already present."
        $securityGroupId = $securityGroup.GroupId
    } else {
        #Security group and the instance should be in the same network (VPC)
        $vpc = Get-EC2Vpc | ? { $_.IsDefault } | select -First 1
        $securityGroupId = New-EC2SecurityGroup $securityGroupName  -Description "$securityGroupName Securitygroup" -VpcId $vpc.VpcId
        $securityGroup = Get-EC2SecurityGroup -GroupName $securityGroupName 
        Write-Verbose "Security Group $securityGroupName created"
    }

    #Compute new ip ranges
    $bytes = (Invoke-WebRequest 'http://checkip.amazonaws.com/').Content
    $myIP = @(([System.Text.Encoding]::Ascii.GetString($bytes).Trim() + "/32"))
    Write-Verbose "$myIP retreived from checkip.amazonaws.com"
    $ips = @($myIP)
    $ips += (Get-EC2Vpc).CidrBlock

    $SourceIPRanges = @()
    foreach ($ip in $ips) {
        $SourceIPRanges += @{ IpProtocol="tcp"; FromPort="80"; ToPort="5986"; IpRanges=$ip}
        $SourceIPRanges += @{ IpProtocol='icmp'; FromPort = -1; ToPort = -1; IpRanges = $ip}
    }

    #Current expanded list
    $currentIPRanges = @()
    foreach ($ipPermission in $securityGroup.IpPermission) {
        foreach ($iprange in $ipPermission.IpRange) {
            $currentIPRanges += @{ IpProtocol=$ipPermission.IpProtocol; FromPort =$ipPermission.FromPort; ToPort = $ipPermission.ToPort; IpRanges = $iprange}
        }
    }

    # Remove IPRange from current, if it should not be
    foreach ($currentIPRange in $currentIPRanges) {
        $found = $false
        foreach ($SourceIPRange in $SourceIPRanges) {
            if ($SourceIPRange.IpProtocol -eq $currentIPRange.IpProtocol -and
                $SourceIPRange.FromPort -eq $currentIPRange.FromPort -and
                $SourceIPRange.ToPort -eq $currentIPRange.ToPort -and
                $SourceIPRange.IpRanges -eq $currentIPRange.IpRanges) {
                    $found = $true
                    break
            }
        }
        if ($found) {
            Write-Verbose "Skipping protocol=$($currentIPRange.IpProtocol) IPRange=$($currentIPRange.IpRanges)"
        } else {
            Revoke-EC2SecurityGroupIngress -GroupId $securityGroupId -IpPermission $currentIPRange
            Write-Verbose "Revoked permissions protocol=$($currentIPRange.IpProtocol) IPRange=$($currentIPRange.IpRanges)"
        }
    }

    # Add IPRange to current, if it is not present
    foreach ($SourceIPRange in $SourceIPRanges) {
        $found = $false
        foreach ($currentIPRange in $currentIPRanges) {
            if ($SourceIPRange.IpProtocol -eq $currentIPRange.IpProtocol -and
                $SourceIPRange.FromPort -eq $currentIPRange.FromPort -and
                $SourceIPRange.ToPort -eq $currentIPRange.ToPort -and
                $SourceIPRange.IpRanges -eq $currentIPRange.IpRanges) {
                    $found = $true
                    break
            }
        }
        if (! $found) {
            Grant-EC2SecurityGroupIngress -GroupId $securityGroupId -IpPermissions $SourceIPRange
            Write-Verbose "Granted permissions for $($SourceIPRange.IpProtocol) ports $($SourceIPRange.FromPort) to $($SourceIPRange.ToPort), IP=($SourceIPRange.IpRanges[0])"
        }
    }
}

function Update-WinEC2FireWallSourceOld
{
    param (
        $SecurityGroupName = $WinEC2Defaults.DefaultSecurityGroup,
        $Region,
        $VpcId,
        [switch] $DontIncludeMyIP,
        [Amazon.EC2.Model.IpPermission[]] $IpCustomPermissions = @()
    )
    trap {break }
    $ErrorActionPreference = 'Stop'
    $Region = . getAndSetRegion $Region # Execute in current context for Set-DefaultAWSRegion

    if ($VpcId -eq $null)
    {
        $VpcId  = (Get-EC2Vpc | ? {$_.IsDefault}).VpcId    
    }

    if (!$DontIncludeMyIP)
    {
        $bytes = (Invoke-WebRequest 'http://checkip.amazonaws.com/').Content
        $SourceIPRange = @(([System.Text.Encoding]::Ascii.GetString($bytes).Trim() + "/32"))
        Write-Verbose "$sourceIPRange retreived from checkip.amazonaws.com"

        $myPermissions = @(
            @{IpProtocol = 'tcp'; FromPort = 3389; ToPort = 3389; IpRanges = $SourceIPRange},
            @{IpProtocol = 'tcp'; FromPort = 5985; ToPort = 5986; IpRanges = $SourceIPRange},
            @{IpProtocol = 'tcp'; FromPort = 80; ToPort = 80; IpRanges = $SourceIPRange},
            @{IpProtocol = 'icmp'; FromPort = -1; ToPort = -1; IpRanges = $SourceIPRange}
        )

        if ($VpcId)
        {
            $CIDRs = (Get-EC2Subnet -Filters @{Name='vpc-id'; value=$VpcId}).CidrBlock
            if ($CIDRs)
            {
                $myPermissions += @{IpProtocol = -1; FromPort = 0; ToPort = 0; IpRanges = @($CIDRs)}
            }
        }

        #Merge permissions if possible
        foreach ($ipPermission in $myPermissions)
        {
            $merge = $false
            for ($i = 0; $i -lt $IpCustomPermissions.Length; $i++)
            {
                $ipCustomPermission = $IpCustomPermissions[$i]
                if ($ipPermission.IpProtocol -eq $ipCustomPermission.IpProtocol -and 
                    $ipPermission.FromPort -eq $ipCustomPermission.FromPort -and 
                    $ipPermission.ToPort -eq $ipCustomPermission.ToPort)
                {
                    $merge = $true
                    foreach ($ipRange in $ipPermission.IpRanges)
                    {
                        if (! $ipCustomPermission.IpRanges.Contains($ipRange))
                        {
                            $ipCustomPermission.IpRanges += $ipRange
                        }
                    }
                }
            }
            if (! $merge)
            {
                $IpCustomPermissions  += $ipPermission
            }
        }
    }

    $sg = Get-EC2SecurityGroup | ? { $_.GroupName -eq $SecurityGroupName}
    if ($sg -eq $null)
    {
        #Create the firewall security group
        $null = New-EC2SecurityGroup $SecurityGroupName  -Description "WinEC2"
    }
    
    foreach ($ipPermission in $sg.IpPermissions)
    {
        $found = $false
        for ($i = 0; $i -lt $IpCustomPermissions.Length; $i++)
        {
            $ipCustomPermission = $IpCustomPermissions[$i]
            if ($ipPermission.IpProtocol -eq $ipCustomPermission.IpProtocol -and 
                $ipPermission.FromPort -eq $ipCustomPermission.FromPort -and 
                $ipPermission.ToPort -eq $ipCustomPermission.ToPort)
            {
                if ($match = $ipPermission.IpRanges.Count -eq $ipCustomPermission.IpRanges.Count)
                {
                    foreach ($ipRange in $ipCustomPermission.IpRanges)
                    {
                        if (-not $ipPermission.IpRanges.Contains($ipRange))
                        {
                            $match = $false
                            break
                        }
                    }
                }
                if ($match)
                {
                    Write-Verbose ('Update-WinEC2FireWallSource - Skipped Protocol=' + $ipPermission.IpProtocol + `
                                    ', FromPort=' + $ipPermission.FromPort + ', ToPort=' + $ipPermission.ToPort + `
                                    ', IpRanges=' + $ipPermission.IpRanges)
                    $IpCustomPermissions[$i] = $null
                    $found = $true
                    break
                }
            }
        }
        if ($found)
        {
        }
        else
        {
            Revoke-EC2SecurityGroupIngress -GroupName $SecurityGroupName `
                -IpPermissions $ipPermission
            Write-Verbose ('Update-WinEC2FireWallSource - Revoked Protocol=' + $ipPermission.IpProtocol + `
                            ', FromPort=' + $ipPermission.FromPort + ', ToPort=' + $ipPermission.ToPort + `
                            ', IpRanges=' + $ipPermission.IpRanges)
        }
    }
    foreach ($IpCustomPermission in $IpCustomPermissions)
    {
        if ($IpCustomPermission)
        {
            Write-Verbose ('Update-WinEC2FireWallSource - Granted Protocol=' + $IpCustomPermission.IpProtocol + `
                            ', FromPort=' + $IpCustomPermission.FromPort + ', ToPort=' + $IpCustomPermission.ToPort + `
                            ', IpRanges=' + $IpCustomPermission.IpRanges)
            Grant-EC2SecurityGroupIngress -GroupName $SecurityGroupName `
                -IpPermissions $IpCustomPermission
        }
    }

    Write-Verbose "Update-WinEC2FireWallSource - Updated $SecurityGroupName"
}

Set-Alias gwin Get-WinEC2Instance
Set-Alias cwin Connect-WinEC2Instance
Set-Alias nwin New-WinEC2Instance
Set-Alias rwin Remove-WinEC2Instance
Set-Alias icmwin Invoke-WinEC2Command

Export-ModuleMember -Alias * -Function * -Cmdlet * -Verbose:$false

Write-Verbose 'Imported Module WinEC2'