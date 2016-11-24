# AzureGlobalConnectionCenter
The goal of Azure Global Connection Center is to connect different national clouds that eliminate the friction to migrate different Azure national clouds.

Typically, migration / integration between different Cloud environment has three phases:

1. **Plan**:
Users need to spend time to investigate what is the difference and cost between different cloud environment. Also, there will be some risks and considerations in new environment. The uncertainty and unfamiliarity will spend lots of time and block the migration. 

2. **Validate**:
Users need to validate if the services are able to run in target environment. Usually we need a PoC or lots of research to understand the limitation and what will it looks like. The difficulty to get and use a trial account also blocks users to move on.

3. **Migrate**:
After planning and validating, users need to investigate how to migrate/clone thier current workload into new environment. The complexity of technologies and steps block user to perform a migration.

In order to help users in each step, Azure Global Connection Center offers three components:

- **Playbook**:
Playbook is a step by step guide as well as a troubleshooting wizard to help Business decision makers/IT admins/Solution Architects to fully comprehend the proper procedures to setup services in Azure China as well issues that may come up during the process and how to resolve them with minimum efforts. Regulatory considerations, Azure China technology platform, Azure China partner solution offerings, application and service migration guidance such as design patterns samples and scenario based tips are some of the topics covered in depth.

- **Assessment Toolkit**:
Assessment Toolkit is a quick and simple tool to generate report and answer "Frequent Asked Question" when migrating Azure Services between different environment like service parity, cost estimation and considerations. It is a PowerShell Module and after install you can start assessment your subscription to make sure the plan and validation of migration.

- **CICD Toolkit**:
CICD (Continuous Integration Continuous Deliver) Toolkit is a quick and simple tool to validate and perform the actual migration as script base. For example, you can leverage the toolkit to migrate your VMs from East Asia to China East. The toolkit will sync your data and configuration so that everything is as same as original. Moreover, the scripts is opensource so you can just integrate into your own DevOps process to perform CICD between Azure Environments.

![Connection Center](https://globalconnectioncenter.blob.core.windows.net/githubpics/globalconnectioncenterchart.png)
