#
# Module manifest for module 'HyperVResource'
#

@{
	ModuleVersion = '0.01'
	GUID = '3ca7dcc0-f27b-4f0c-a7aa-c5f15c5ba936'
	Author = 'Sivaprasad Padisetty'
	NestedModules="HyperVResource.psm1"
	FunctionsToExport = "CreateResource", "RemoveResource", "ClearResource"
}

