# Author: Sivaprasad Padisetty
# Licensed under Apache 2.0
#
echo Specialization is complete > d:\run.log
echo Doing post specialization steps ... >> d:\run.log
echo Changing the execution policy to unrestricted ... >> d:\run.log

Powershell.exe -command set-executionpolicy unrestricted -force  >> d:\run.log
echo "" >> d:\run.log

echo Executing PS1 file ... >> d:\run.log
Powershell.exe -file d:\run.ps1   >> d:\run.log
echo "" >> d:\run.log

echo Done >> d:\run.log
