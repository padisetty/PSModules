#Application starting point.

configuration appConfig
{
    Node $AllNodes.Nodename
    {
        Log l1
        {
            Message = "Installing Anti Virus"
        }
    }
}

appConfig app1
{
}
