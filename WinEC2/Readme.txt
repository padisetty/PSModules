# Author: Siva Padisetty
# Copyright 2014, Licensed under Apache License 2.0
#

1. Save your credentials in the default profile 

Set-AWSCredentials -AccessKey AKIAIOSFODNN7EXAMPLE -SecretKey wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY -StoreAs default

2. You need to add either publicDNSName or * to make PS remoting work for non domain machines
  Make sure you understand the risk before doing this. In the elevated PS prompt
  
  Set-Item WSMan:\localhost\Client\TrustedHosts "*" -Force

  It is better if you add full DNS name instead of *. Because * will match any machine name

3. Install the WinEC2 Module, Copy the content of "multicle" folder to say "c:\multicle" 

Execute in elevated PS "c:\multicle\install.ps1"

4. Check if you are happy with the defaults by running "Get-WinEC2Defaults"

5. Change defaults "Set-WinEC2Defaults"

6. Create the folder "c:\temp\keys" to save the pem keys associated with the keypairs

7. "New-WinEC2Keypair" to create the default keypair without any parameters

8. Create default security group (with name sg_winec2) using one of the following options

Update-WinEC2FireWallSource

or 

"Update-WinEC2FireWallSource -IpCustomPermissions  @( @{IpProtocol = 'icmp'; FromPort = -1; ToPort = -1; IpRanges = '10.0.0.0/8', '11.0.0.0/8'})"

or

manually create it.

9. "Test-WinEC2", to test for basics

10. "Get-WinEC2Instance" to list the instances

11. Create an instance

New-WinEC2Instance -NewPassword '...' -Name 'test1'