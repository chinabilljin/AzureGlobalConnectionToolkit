# CICD Tool

Continuous Integration Continuous Delivery (CICD) Tool help customers to connect their services in different datacenter, no matter location or environment. 

Given the scenario, one company has a VM in Azure East Asia hosting their website. With business growth, they want to extend their website into China so they want to replicate the VM into China East. Besides, when there is an update in East Asia, they want the change also apply to VM in China East.

CICD Tool is designed to solve this problem when customer want their services can simply replicate/migrate bettwen different Azure datacenter. Moreover, it provides the possibility to integrate into DevOps process. Ulimately, we want CICD tool can help to integrate services in different region as one.

## Features

### ARM VM Migration

* Support ARM VM Migration from/to Azure, Azure in China and Azure in Germany
* Support Data Sync through VHD copy
* Support Validation only mode

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

1. Download the [msi installer]()
2. Install

#### Script Mode

1. Download all the [scripts](https://github.com/Azure/AzureGlobalConnectionToolkit/tree/master/CICD%20Tool/Scripts)
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

__-Validate__

It will perform validation only and return the check result.

__-Prepare__

It will create the resource group and storage accounts for migration.

__-VhdCopy__

It will copy the VHDs of VM to destination. But the storage accounts in destination need to be created before execute this commend.

__-BuildVM__

It will start the VM build up in destination. But the VHD Copy and Resource Group creation need to be done ahead. Performing this command also require to input __-osDiskUri__ and __-dataDiskUris__ if any. Please note it in __-dataDiskUris__, the input array need to matach in lun number to make sure the configuration consistent.

For example, $dataDiskUris is the input of __-dataDiskUris__. $dataDiskUris[0] should the the destination data Disk Lun 0's Uri.


