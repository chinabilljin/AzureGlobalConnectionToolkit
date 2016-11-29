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
