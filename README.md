# AzureGlobalConnectionToolkit
The goal of Azure Global Connection Center is to connect different national clouds that eliminate the friction to migrate different Azure national clouds.

Typically, migration / integration between different Cloud environment has three phases:

1. **Plan**:
Users need to spend time to investigate what is the difference and cost between different cloud environment. Also, there will be some risks and considerations in new environment. The uncertainty and unfamiliarity will spend lots of time and block the migration. 

2. **Validate**:
Users need to validate if the services are able to run in target environment. Usually we need a PoC or lots of research to understand the limitation and what will it looks like. The difficulty to get and use a trial account also blocks users to move on.

3. **Migrate**:
After planning and validating, users need to investigate how to migrate/clone thier current workload into new environment. The complexity of technologies and steps block user to perform a migration.

In order to help users in each step, Azure Global Connection Center offers two components:

- **Assessment Tool**:
Assessment Tool is a quick and simple tool to generate report and answer "Frequent Asked Question" when migrating Azure Services between different environment like service parity, cost estimation and considerations. It is a PowerShell Module and after install you can start assessment your subscription to make sure the plan and validation of migration.

- **CICD Tool**:
CICD (Continuous Integration Continuous Deliver) Tool is a quick and simple tool to validate and perform the actual migration as script base. For example, you can leverage the toolkit to migrate your VMs from East Asia to China East. The toolkit will sync your data and configuration so that everything is as same as original. Moreover, the scripts is opensource so you can just integrate into your own DevOps process to perform CICD between Azure Environments.


![Connection Toolkit](https://globalconnectioncenter.blob.core.windows.net/githubpics/connectiontoolkitchart.png)


##Features

###Assessment Tool

* Support the assessment from Global Azure to China Azure.
* Support the assessment for entire subscription.
* Support the service parity check.
* Support only limited item for cost estimation.

###CICD Tool

* Support ARM VM migration only. (no classic VM support)
* Support different Cloud Environment Migration.
* Support validation only mode.
* Support data and configuration migration. (no extension support)

## Supported Environments

###Assessment Tool

* Cloud Environment
  * Microsoft Azure as reference environment 
  * Microsoft Azure in China as target environment
  
* Client Environment
  * Windows PowerShell 3.0+
  
###CICD Tool

* Cloud Environment
  * Microsoft Azure
  * Microsoft Azure in China
  * Microsoft Azure in Germany
  * Microsoft Azure in US Government

* Client Environment
  * Windows PowerShell 3.0+
  * AzureRm.Profile 1.7.0+
  * AzureRm.Compute 1.7.0+
  * AzureRm.Network 1.7.0+
  * AzureRm.Storage 1.7.0+

## Installation

###MSI Installer

1. Download latest [MSI Installer](https://github.com/Azure/AzureGlobalConnectionToolkit/releases/download/0.1.0/GlobalConnectionCenter.msi) .
2. Run and Install.

You can also find all the previous releases in [Azure Global Connection Toolkit Release](https://github.com/Azure/AzureGlobalConnectionToolkit/releases/tag/0.1.0)

## Get Started

###Assessment Tool

After installation, run cmdlet in your PoowerSehll.

```powershell
New-AzureRmMigrationReport
```

After executing the cmdlet, it will follow the steps to generate report:

1. Ask your credential.
2. Select reference subscription.
3. Generate the report.

###CICD Tool

After installation, run cmdlet in your PowerShell if you want to perform a migration.

```powershell
Start-AzureRmVMMigration
```

Run cmdlet if you only want to validate.

```powershell
Start-AzureRmVMMigration -Validate
```

After executing the cmdlet, it will follow the steps to perform VM migration:

1. Ask your source credential.
2. Select source subscription.
3. Ask your destination credential.
4. Select destination subscription.
5. Select the VM to migrate.
6. Select the VM destination location.
7. Confirm the VM Migration.
8. Start the VM Migration.

## Need Help?

Please contact [Azure Global Connection Team](mailto:amcteam@microsoft.com) if you have any issue or feedback.
