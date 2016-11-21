# Other Migration Tools#

## Classic VM Migration##

Tools for the migration of IaaS resources or Virtual Machines (VMs) from classic (ASM) to Resource Manager (ARM) was launched publicly in early 2016. You can find the details by clicking on the following links below:
https://azure.microsoft.com/en-us/blog/iaas-migration-ga/
https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-windows-migration-classic-resource-manager/
 
If you have classic ASM IaaS resources, it is highly recommended that you first migrate them to ARM before moving them to China Azure.

## AAD Identity Migration Tool##

To assist you on the migration of AAD Identity from Global Azure to China Azure, we offer theAAD Identity Migration Tool, which is part of the Global Customer Migration Assistant.
 
The goal of the AAD Identity Migration tool is to replicate AAD identities, including AAD users/groups/user memberships, from source AAD to target AAD. The source AAD and the target AAD can either be located on the same Azure cloud or separate Azure clouds. 
 
The typical scenario is to have Global Azure as the source AAD, and China Azure as the target AAD. First, you use the tool to replicate the identities in Global AAD to China AAD.  Based on that, other Azure resources depending on the AAD, and security implementations like RBAC authorization, can be migrated afterwards to China Azure.
 
The AAD Identity Migration Tool is under development, the PowerShell version is available as a private preview. You can contact your Microsoft account representatives for more details.

Back to the [Migration Assistant](https://github.com/Azure/AzureGlobalConnectionCenter/blob/master/PlayBook/Migration%20Assistant/Migration%20Assistant.md) .
