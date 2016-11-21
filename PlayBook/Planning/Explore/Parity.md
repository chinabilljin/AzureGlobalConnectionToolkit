#Parity#

##Differences from a Developer Perspective##


Since most of the technical content that Microsoft currently provides assumes that the application is developed for Global Azure, rather than China Azure, it is important to ensure that developers understand the differences in services hosted in China.
 
First, there are functional differences, which means that the global service has some features that are not available in China, as summarized in the previous section on Parity .Secondly, there are differences contributed by the difference in operations in China, in particular the Azure service endpoints, which you must customize by yourself for any sample code and steps published in the technical content for Global Azure.
 
Please refer to the link below for details on the Developer Notes (in Chinese):
https://www.azure.cn/documentation/articles/developerdifferences/#dev-guide

##Differences in Service Pricing##
 
Due to the functional differences as summarized in the previous section on Parity , and the operating model differences comparing Global Azure and China Azure, you might notice that there are differences in the service price structure.
 
This may impact your business planning and we recommended you to do an estimation of the required costs. For more details, please check out the following link regarding the China Azure service price list: https://www.azure.cn/pricing/overview/.
 
If you need an English translation, please refer to this link:
https://translate.google.com.hk/translate?hl=zh-CN&sl=zh-CN&tl=en&u=https%3A%2F%2Fwww.azure.cn%2Fpricing%2Foverview%2F

##Application Migration Design Scenarios##
 
In order to serve as a guide on the migration of your applications from an application architecture perspective, we focused on the application migration design for 2 scenarios: Rehost and Refactor.
 
- Rehost - Covers the scenario for redeploying the application to a different cloud environment. This is to serve as a guide on the migration design for your applications or workload that runs on Global Azure, and to have them migrated to China Azure.
 
- Refactor - Covers the scenario that you are deploying new applications on China Azure, which you may have these applications already running on other cloud providers, and would like to look for solutions for a better and faster migration to China Azure.
 
For details, please refer to the [Application Migration Design Scenarios](https://github.com/Azure/AzureGlobalConnectionCenter/blob/master/PlayBook/Planning/Guidance/Parity/Application%20Migration%20Design%20Scenarios.md) guide.

#Migration Assistant#
 
The Global Customer Migration Assistant supports migrating your applications with the Virtual Machine (VM) from Global Azure ARM to China Azure ARM.
 
When migrating your application and/or workload to China Azure, you can leverage the Global Customer Migration Assistant to automate the migration in your production environment.
 
For details, please check out the [Migration Assistant guide](https://github.com/Azure/AzureGlobalConnectionCenter/blob/master/PlayBook/Migration%20Assistant/Migration%20Assistant.md).

Let's move to the next section - [Performance](https://github.com/Azure/AzureGlobalConnectionCenter/edit/master/PlayBook/Planning/Explore/Performance.md).
 
