gps msi* | Stop-Process -Force
gps wmi* | Stop-Process -Force
if (Test-Path "c:\temp\test.txt")
{
    del "c:\temp\test.txt"
}
cls

#configuration is like a function defination, you need to invoke main explicitly
configuration main
{
    WindowsFeature iis
    {
        Name = "Web-Server"
        Ensure = "Present"
    }

    Puppet p
    {
        Source = "c:\temp\dsc\puppet\test.pp"
    }
}

#call main to genrate MOF
main -OutputPath C:\temp\config 

#display the MOF file generated
cat C:\temp\config\localhost.mof

#push the MOF file generated to the target node.
Start-DscConfiguration c:\temp\config -ComputerName localhost -Wait -verbose

cat C:\temp\test.txt

