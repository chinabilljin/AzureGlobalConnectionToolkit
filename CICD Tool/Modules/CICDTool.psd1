@{
RootModule = 'CICDTool.psm1'
ModuleVersion = '0.2.2'
GUID = '6cee1522-3669-4bba-b537-c1b3ae4f10c3'
Author = 'Microsoft Corporation'
CompanyName = 'Microsoft Corporation'
Copyright = '(c) Microsoft Corporation. All rights reserved.'
Description = 'Azure Global Connection Center is to connect different national clouds that eliminate the friction to migrate different Azure national clouds. It provides scripts that can help to orchestrate the migration process.'
FunctionsToExport = @('Start-AzureRmVMMigration')
VariablesToExport = "*"
AliasesToExport = '*'
FileList = @('CICDTool.psm1',
             'CICDTool.psd1')
RequiredModules = @()
HelpInfoURI = 'https://github.com/Azure/AzureGlobalConnectionToolkit'
}
