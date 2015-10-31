#
# Module manifest for module 'PuppetResource'
#
# Generated on: 1/10/2013
#

@{
    ModuleVersion = '0.01'
    GUID = '9c82e585-22cc-4d25-b387-eab1ba718fc0'
    Author = 'Sivaprasad Padisetty'
    Description = 'Puppet Resource.'
    NestedModules = @("PuppetResource.psm1")

    # Functions to export from this module
    FunctionsToExport = @("Get-TargetResource", "Set-TargetResource", "Test-TargetResource")
}