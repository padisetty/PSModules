#
# Module manifest for module 'PSTemplate'
#

@{
	ModuleVersion = '0.01'
	GUID = '641c297a-04c0-46f0-af61-0aafc4b4cf09'
	Author = 'Sivaprasad Padisetty'
    	NestedModules="PSTemplate.psm1"
    	FunctionsToExport="Expand-PSTemplateFile", "Expand-PSTemplateString"
}

