#Parity#

##Differences from a Developer Perspective##


Since most of the technical content that Microsoft currently provides assumes that the application is developed for Global Azure, rather than China Azure, it is important to ensure that developers understand the differences in services hosted in China.
 
First, there are functional differences, which means that the global service has some features that are not available in China, as summarized in the previous section on [Parity](https://github.com/Azure/AzureGlobalConnectionCenter/blob/master/PlayBook/Envisioning/Guidance/Parity.md) .Secondly, there are differences contributed by the difference in operations in China, in particular the Azure service endpoints, which you must customize by yourself for any sample code and steps published in the technical content for Global Azure.
 
The table below summarizes the differences in Azure Service endpoint mapping:

Service Category | Global Azure URI | China Azure URI
---------------- | ---------------- | ----------------
Azure – In General | *.windows.net | *.chinacloudapi.cn
Azure - Compute | *.cloudapp.net | *.chinacloudapp.cn
Azure - Storage | *.blob.core.windows.net *.queue.core.windows.net *.table.core.windows.net | *.blob.core.chinacloudapi.cn *.queue.core.chinacloudapi.cn *.table.core.chinacloudapi.cn
Azure – Service Management | https://management.core.windows.net | https://management.core.chinacloudapi.cn
Azure - ARM | https://management.azure.com | https://management.chinacloudapi.cn
SQL Database | *.database.windows.net | *.database.chinacloudapi.cn
Azure – Management Portal | http://manage.windowsazure.com | http://manage.windowsazure.cn
SQL Azure DB Management API | https://management.database.windows.net | https://management.database.chinacloudapi.cn
Service Bus | *.servicebus.windows.net | *.servicebus.chinacloudapi.cn
ACS | *.accesscontrol.windows.net | *.accesscontrol.chinacloudapi.cn
HDInsight | *.azurehdinsight.net | *.azurehdinsight.cn
SQL DB Import/Export Service Endpoint |  | 1. China East： https://sh1prod-dacsvc.chinacloudapp.cn/dacwebservice.svc  2. China North：https://bj1prod-dacsvc.chinacloudapp.cn/dacwebservice.svc

Please refer to the link below for details on the Developer Notes (in Chinese):
https://www.azure.cn/documentation/articles/developerdifferences/#dev-guide

##Differences in Service Pricing##

Due to the functional differences as summarized in the previous section on [Parity](https://github.com/Azure/AzureGlobalConnectionCenter/blob/master/PlayBook/Envisioning/Guidance/Parity.md), and the operating model differences comparing Global Azure and China Azure, you might notice that there are differences in the service price structure.
 
This may impact your business planning and we recommended you to do an estimation of the required costs. For more details, please check out the following link regarding the China Azure service price list: https://www.azure.cn/pricing/overview/.
 
If you need an English translation, please refer to this link:
https://translate.google.com.hk/translate?hl=zh-CN&sl=zh-CN&tl=en&u=https%3A%2F%2Fwww.azure.cn%2Fpricing%2Foverview%2F

##Application Migration Design Scenarios##
 
As a guide on the migration of your applications in the application architecture perspective, please refer to the [Application Migration Design Scenarios](https://github.com/Azure/AzureGlobalConnectionCenter/blob/master/PlayBook/Planning/Guidance/Parity/Application%20Migration%20Design%20Scenarios.md) guide.

##Migration Assistant##
 
The Global Customer Migration Assistant supports migrating your applications with the Virtual Machine (VM) from Global Azure ARM to China Azure ARM.
 
When migrating your application and/or workload to China Azure, you can leverage the Global Customer Migration Assistant to automate the migration in your production environment.
 
For details, please check out the [Migration Assistant](https://github.com/Azure/AzureGlobalConnectionCenter/blob/master/PlayBook/Migration%20Assistant/Migration%20Assistant.md) guide.

Let's move to the next section - [Performance](https://github.com/Azure/AzureGlobalConnectionCenter/blob/master/PlayBook/Planning/Guidance/Performance.md).






















































