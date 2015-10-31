ipmo multicle -Force

# WARNING
#   This is a dangerous command. 
#   This will delete all VMs, delete all the files located in VHDDiff folder and VHDData folder.
Clear-Multicle
 

# Parameters used in unattend.pstemplate
#   AdministratorPassword - password for the administrator account. should be a secure string.
#   AutoLogon - to enable auto admin login.
#   DomainUserCredential - PSCredential object, points to a domain user with password. If not specified it will not domain join


#SECURITY WARNING
#Uncomment the following line to specify the password interactively and comment the hardcoded password
#$admincred = New-Object System.Management.Automation.PSCredential -ArgumentList "Administrator"
$admincred = New-Object System.Management.Automation.PSCredential -ArgumentList "Administrator", (ConvertTo-SecureString -String "Secret." -AsPlainText -Force)

$overrideParams = @{
    AdministratorPassword = $admincred.Password
}

# dev.env creates a single VM, installs both frontend and backend to this one
# frontend and backend, are just place hoders representing frontend and backend. 
# It is really a hello world app, to introduce the concept.

$env = "$PSScriptRoot\dev.env"

# test.env creates a creates two VMs. one for frontend and second one for backend.
#$env = "$PSScriptRoot\test.env"

# production.env creates three VMs, two for front end, one for backend.
#$env = "$PSScriptRoot\production.env"

#This will delete VMs defined in the $env and the associated VHD files.
Remove-Multicle -EnvironmentPath $env

#Create the VMs
Start-Multicle -EnvironmentPath $env -OverrideParams $overrideParams
