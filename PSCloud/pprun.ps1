# Author: Sivaprasad Padisetty
# Copyright 2013, Licensed under Apache License 2.0
#


md "$($env:ProgramData)\PuppetLabs\facter\facts.d" -EA 0
Copy "$PSScriptRoot\pprun param.ps1" "$($env:ProgramData)\PuppetLabs\facter\facts.d\param.ps1"

#configuration is like a function defination, you need to invoke main explicitly
configuration puppetMain
{
[Param.MultiApplicuationRun]
}

#invoke the config
puppetMain p
{
}
