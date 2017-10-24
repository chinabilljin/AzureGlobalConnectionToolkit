@{
NestedModules = @('.\Microsoft.Azure.CAT.Migration.PowerShell.dll')
ModuleVersion = '0.2.3'
GUID = 'c668326f-e44f-446d-a4e3-00ee4633963d'
Author = 'Microsoft Corporation'
CompanyName = 'Microsoft Corporation'
Copyright = '(c) Microsoft Corporation. All rights reserved.'
Description = 'Azure Global Connection Center is to connect different national clouds that eliminate the friction to migrate different Azure national clouds. It provides scripts that can help to orchestrate the migration process.'
FunctionsToExport = @('New-AzureRmMigrationReport')
VariablesToExport = "*"
AliasesToExport = '*'
FileList = @('Microsoft.Azure.CAT.Migration.PowerShell.dll',
             'AssessmentTool.psd1')
RequiredModules = @()
HelpInfoURI = 'https://github.com/Azure/AzureGlobalConnectionToolkit'
}
