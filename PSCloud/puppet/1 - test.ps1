gps msi* | Stop-Process -Force
gps wmi* | Stop-Process -Force
del "c:\temp\test.txt" -EA 0
cls

ipmo puppet

#configuration is like a function defination, you need to invoke main explicitly
configuration main
{
    Puppet p
    {
        Source = "$psscriptroot\test.pp"
    }
}

#call main to genrate MOF
main -OutputPath C:\temp\config 

#display the MOF file generated
cat C:\temp\config\localhost.mof

#push the MOF file generated to the target node.
Start-DscConfiguration c:\temp\config -ComputerName localhost -Wait -verbose

cat C:\temp\test.txt

