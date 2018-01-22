# CICD Tool

Continuous Integration Continuous Delivery (CICD) Tool help customers to connect their services in different datacenter, no matter location or environment. 

Given the scenario, one company has a VM in Azure East Asia hosting their website. With business growth, they want to extend their website into China so they want to replicate the VM into China East. Besides, when there is an update in East Asia, they want the change also apply to VM in China East.

CICD Tool is designed to solve this problem when customer want their services can simply replicate/migrate bettwen different Azure datacenter. Moreover, it provides the possibility to integrate into DevOps process. Ulimately, we want CICD tool can help to integrate services in different region as one.

## Features

### ARM VM Migration

* Support ARM VM migration from/to Azure, Azure in China and Azure in Germany.
* Support data sync through VHD copy.
* Support validation only mode.
* Support rename for resource and DNS.
* Support resize

VM migration will be complete through four phases.

1. __Validate:__ Validation will check the prerequisite and requirement in source/destination environment to make sure the smooth migration.
2. __Prepare:__ Preparation will build up the dependencies of migration in destination including storage accounts and resource groups.
3. __VHDs Copy:__ VHD Copy will start the blob copy between source and destination.
4. __VM Build:__ VM Build will use the source VM configuration to build up the same VM in destination and validate after migration.

ARM VM Migration has two mode:

* __Module Mode:__ Module Mode is quick and simple solution and you can use it as a built-in PowerShell module. This is the best option if you need a just work solution.

* __Script Mode:__ Script Mode is open source solution composed by the scripts of each phase. You can download the script and modify by yourself. This is the best option if you need a customized solution.

## Installation

### ARM VM Migration

#### Module Mode

1. Download the [msi installer](https://github.com/Azure/AzureGlobalConnectionToolkit/releases/download/0.2.2/AzureGlobalConnectionToolkit.0.2.2.msi)
2. Install

#### Script Mode

1. Download all the [scripts](https://github.com/Azure/AzureGlobalConnectionToolkit/tree/master/CICD%20Tool/PowerShell/Scripts)
2. Put them into same folder

## Get Started

### ARM VM Migration

#### Module Mode

Base command in module mode:

```powershell
Start-AzureRmVMMigration
```

If you use this command without any parameter, there will be a GUI to guide you input the information step by step.

For the customer want to input the information programatically through parameter, here is the parameter list and description.

__-VM__

The VM context which you want to migrate, you can get the context through 

```powershell
$vm = Get-AzureRmVM -name VMName -ResourceGroupName RGName
```

Then use $vm as parameter input.

__-SrcContext__

The credential from source subscription, you can get the context after you input the credential (like after Add-AzureRmAccount) through

```powershell
$SrcContext = Get-AzureRmContext
```

Then use $SrcContext as parameter input

__-DestContext__

The credential from destination subscription, you can get the context after you input the credential (like after Add-AzureRmAccount) through

```powershell
$DestContext = Get-AzureRmContext
```

Then use $DestContext as parameter input

__-TargetLocation__

The target location VM migrate to. you can use Get-AzureRmLocation to get the full location list.

If you want to perform specific phase only rather than the whole migration, you can use following parameters:

__-JobType__

If you want to execute the specific job only, you can specify the job in this parameter including:

* __Rename__

Get the output of the rename function and it can be the input for other jobs.

* __Validate__

It will perform validation only and return the check result.

* __Prepare__

It will create the resource group and storage accounts for migration.

* __VhdCopy__

It will copy the VHDs of VM to destination. But the storage accounts in destination need to be created before execute this commend.

* __VMBuild__

It will start the VM build up in destination. But the VHD Copy and Resource Group creation need to be done ahead. Performing this command also require to input __-osDiskUri__ and __-dataDiskUris__ if any. Please note it in __-dataDiskUris__, the input array need to matach in lun number to make sure the configuration consistent.

For example, $dataDiskUris is the input of __-dataDiskUris__. $dataDiskUris[0] should the the destination data Disk Lun 0's Uri.



#### Script Mode

The Script mode consists by five scripts:

1. __VMMigration.ps1:__ All up integrated script for the VM migration. Execute it if you want the end-to-end migration.
2. __Validate.ps1:__ Validate only script.
3. __Prepare.ps1:__ Prepare only script.
4. __CopyVhd.ps1:__ Vhd copy only script.
5. __VMBuild.ps1:__ VM build only script.
6. __Rename.ps1:__ Perform the rename and it can be the input for other script.

All the script use the same parameter as Module Mode. You can see the parameter description in Module Mode section above.

Also, it has a simple validation function for your PowerShell Environment:

* __CheckAzurePSVersion:__ Check if Azure PS meet the requirement.

Also, if you want to customize the script. We also put comments inside the script so you can understand the logic of each block and make your version or integrate into your DevOps Process!

## Need Help?

Please contact [Azure Global Connection Team](mailto:amcteam@microsoft.com) if you have any issue or feedback.
