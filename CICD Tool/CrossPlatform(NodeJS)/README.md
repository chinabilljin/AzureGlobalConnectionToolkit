# CICD Tool - Cross Platform CLI for MAC, Linux and Windows

[![NPM version](https://badge.fury.io/js/azure-connectiontoolkit-cicd.png)](http://badge.fury.io/js/azure-connectiontoolkit-cicd)

Continuous Integration Continuous Delivery (CICD) Tool help customers to connect their services in different datacenter, no matter location or environment. 

Given the scenario, one company has a VM in Azure East Asia hosting their website. With business growth, they want to extend their website into China so they want to replicate the VM into China East. Besides, when there is an update in East Asia, they want the change also apply to VM in China East.

CICD Tool is designed to solve this problem when customer want their services can simply replicate/migrate bettwen different Azure datacenter. Moreover, it provides the possibility to integrate into DevOps process. Ulimately, we want CICD tool can help to integrate services in different region as one.

CICD tool cross platform version is a node.js based cmdlet tool which can run cross platform.

## Features

### ARM VM Migration

* Support ARM VM migration from/to Azure, Azure in China and Azure in Germany.
* Support data sync through VHD copy.

VM migration will be complete through four phases.

1. __Validate:__ Validation will check the prerequisite and requirement in source/destination environment to make sure the smooth migration.
2. __Prepare:__ Preparation will build up the dependencies of migration in destination including storage accounts and resource groups.
3. __VHDs Copy:__ VHD Copy will start the blob copy between source and destination.
4. __VM Build:__ VM Build will use the source VM configuration to build up the same VM in destination and validate after migration.

## Supported Environment

Before installation, please make sure you have downloaded and installed the [latest Node.js and npm](https://nodejs.org/en/download/package-manager/).

## Installation

### Install from npm

To install CICD cross-platform CLI, run following command to install npm package.

```bash
npm install -g azure-connectiontoolkit-cicd
```

On Linux distributions, you might need to use sudo to successfully run the npm command, as follows:

```bash
sudo npm install -g azure-connectiontoolkit-cicd
```

## Get Started

### ARM VM Migration

To use CICD cross platform CLI, base command is:

```bash
azmigrate vm
```

Meanwhile, you need to input the information for each parameter to make it work. Here is the parameter list and description.

First of all, you need to specify the source environment and destination environment of migration. For example, AzureCloud to AzureChinaCloud.

_-e, --srcEnv_

`source Azure environment (default is AzureCloud if not specified)`

_-E, --destEnv_

`destination Azure environment`

Then, you need to specify the authentication mode you want to use, service principal or username/password. If MFA is enabled, you need to select service principal mode as authentication mode.

In service principal mode, you need to specify following information:

_-i, --srcClientId_

`source AAD application client ID`

_-I, --destClientId_

`destination AAD application client ID`

_-c, --srcSecret_

`source AAD application secret`

_-C, --destSecret_

`destination AAD application secret`

_-d, --srcDomain_

`source domain or tenant id containing the AAD application`

_-D, --destDomain_

`destination domain or tenant id containing the AAD application`

In username/password mode, you need to specify following information:

_-u, --srcUserName_

`source AAD account user name`

_-U, --destUserName_

`destination AAD account user name`

_-p, --srcPassword_

`source AAD account password`

_-P, --destPassword_

`destination AAD account password`

Then, you need to specify the source/destination subscription:

_-s, --srcSubId_

`source subscription ID`

_-S, --destSubId_

`destination subscription ID`

Finally, you need to specify the VM you would like to migrate and the target location:

_-g, --srcGroup_

`source resource group name of the virtual machine`

_-n, --srcName_

`source virtual machine name`

_-L, --destLocation_

`destination location`

For example, a complete command will be like this:

```bash
azmigrate vm -E AzureChinaCloud -d srcTenantId -i srcAppId -c srcAppSecret -D destTenantId -I destAppId -C destAppSecret -s srcSubId -S destSubId -g srcVmRg -n srcVmName -L chinaeast 
```

## Need Help?

Please contact [Azure Global Connection Team](mailto:amcteam@microsoft.com) if you have any issue or feedback.