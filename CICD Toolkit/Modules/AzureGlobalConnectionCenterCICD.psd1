@{
RootModule = 'AzureGlobalConnectionCenterCICD.psm1'
ModuleVersion = '0.1.0'
GUID = '6cee1522-3669-4bba-b537-c1b3ae4f10c3'
Author = 'Microsoft Corporation'
CompanyName = 'Microsoft Corporation'
Copyright = '(c) Microsoft Corporation. All rights reserved.'
Description = 'Azure Global Connection Center is to connect different national clouds that eliminate the friction to migrate different Azure national clouds. It provides scripts that can help to orchestrate the migration process.'
FunctionsToExport = @('Start-AzureRmVMMigration',
                      'Start-AzureRmVMMigrationValidate',
                      'Start-AzureRmVMMigrationPrepare',
                      'Start-AzureRmVMMigrationVhdCopy',
                      'Start-AzureRmVMMigrationBuild')
VariablesToExport = "*"
AliasesToExport = '*'
FileList = @('AzureGlobalConnectionCenterCICD.psm1',
             'AzureGlobalConnectionCenterCICD.psd1')
RequiredModules = @()
HelpInfoURI = 'https://github.com/Azure/AzureGlobalConnectionCenter'
}
