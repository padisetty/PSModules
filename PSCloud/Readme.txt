# Author: Sivaprasad Padisetty
# Copyright 2013, Licensed under Apache License 2.0
#

1. On you Hyper-V machine, where you want to try this. Install Hyper-V feature/role and make sure it works. Test this by trying the cmdlets from elevated PS Shell. GET-VHD, NEW-VHD etc.

2. Copy the multi to a folder say c:\scripts\multi, call it MULTIROOT

3. Add "<MULTIROOT>\Modules" to the system environment variable PSMODUDLESPATH 

4. Create three folders, c:\VHDBase, c:\VHDDiff, c:\VHDData. These are the default locations to save the base VHD, differential VHD and Data VHDX files.

6. Every VM is associated with two disks, one OS disk + one data disk. (OS diff disk & data disk are auto created)

7. OS VHD is actually a diff disk. The parent base disk is located in c:\VHDBase, diff disk is located in c:\VHDDiff.

8. Data disk contains the apps. The data disk can have more than one app. Each app is located inside one folder. There should be a ps1 file associated with each folder, name of this ps1 file should match the folder name. The folder can contain any other payload.

9. Create or acquire a Windows Server VHD (or Windows). Steps for creating a bootable VHD (OS Disk) can be found at http://blogs.technet.com/b/haroldwong/archive/2012/08/18/how-to-create-windows-8-vhd-for-boot-to-vhd-using-simple-easy-to-follow-steps.aspx

10. You need "Standard Server 2012 R2"/Windows 8.1 or other version of Windows Server/Windows with WMF 4.0 installed. http://blogs.msdn.com/b/powershell/archive/2013/10/25/windows-management-framework-4-0-is-now-available.aspx.

11. Copy OS VHD to c:\VHDBase. 

12. Update the parameters defined in "<MULTIROOT>\Sample\*.env" files. 

13. Try the sample located at "<MULTIROOT>\Sample\test.ps1". 

14. Default values for VHDBase, VHDDiff, VHDData can be changed by defining them in the env file. (e.g.) "MultiHypervVHDBaseRoot" : "c:\\VHDBaseNewLocation"