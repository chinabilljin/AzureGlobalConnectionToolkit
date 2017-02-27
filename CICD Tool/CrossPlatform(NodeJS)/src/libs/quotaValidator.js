'use strict';

const exceptions = require('./exceptions'),
    azureEx = require('./azureExtensions'),
    ResourceType = require('./ResourceType'),
    utils = require('./utils');

const Ex = exceptions.ValidationFailureException;

/**
 * @param {string} vmSize - VM Size string, such as Standard_A1
 */
function GetAzureRmVmCoreFamily(vmSize) {
    if (typeof vmSize === "string") {
        if (vmSize.match(/^Basic_A[0-4]$/)) {
            return "basicAFamily";
        }
        if (vmSize.match(/^Standard_A[0-7]$/)) {
            return "standardA0_A7Family";
        }
        if (vmSize.match(/^Standard_A([89]|1[01])$/)) {
            return "standardA8_A11Family";
        }
        if (vmSize.match(/^Standard_D1?[1-4]$/)) {
            return "standardDFamily";
        }
        if (vmSize.match(/^Standard_D1?[1-5]_v2$/)) {
            return "standardDv2Family";
        }
        if (vmSize.match(/^Standard_G[1-5]$/)) {
            return "standardGFamily";
        }
        if (vmSize.match(/^Standard_DS1?[1-4]$/)) {
            return "standardDSFamily";
        }
        if (vmSize.match(/^Standard_DS1?[1-5]_v2$/)) {
            return "standardDSv2Family";
        }
        if (vmSize.match(/^Standard_GS[1-5]$/)) {
            return "standardGSFamily";
        }
        if (vmSize.match(/^Standard_F([1248]|16)]$/)) {
            return "standardFFamily";
        }
        if (vmSize.match(/^Standard_F([1248]|16)s$/)) {
            return "standardFSFamily";
        }
        if (vmSize.match(/^Standard_NV(6|12|24)$/)) {
            return "standardNVFamily";
        }
        if (vmSize.match(/^Standard_NC(6|12|24)$/)) {
            return "standardNCFamily";
        }
        if (vmSize.match(/^Standard_H(8m?|16m?r?)$/)) {
            return "standardHFamily";
        }
        if (vmSize.match(/^Standard_A(1|[248]m?)_v2$/)) {
            return "standardAv2Family";
        }
    }
    return;
}

/**
 * @param {AzureManagementClients} clients - Destination clients
 * @param {string} location - Destination location
 * @param {Map<string, ResourceMigrationInfo[]>} dependencies - Dependencies from the migration job
 */
function validateQuotaAsync(clients, location, dependencies)
{
    const vmSizesCoresPromise = azureEx.listAsyncByLocation(clients.computeClient.virtualMachineSizes,location).then(vmSizes => {
        let vmSizesCores = new Map();
        for (let vmSize of vmSizes) {
            vmSizesCores.set(vmSize.name, vmSize.numberOfCores);
        }
        return vmSizesCores;
    });

    const computeUsagePromise = azureEx.listAsyncByLocation(clients.computeClient.usageOperations,location);
    const networkUsagePromise = azureEx.listAsyncByLocation(clients.networkClient.usages,location);
    const storageUsagePromise = azureEx.listAsync(clients.storageClient.usageOperations);
    const usagesPromise = Promise.all([computeUsagePromise, networkUsagePromise, storageUsagePromise]).then(([computeUsages, networkUsages, storageUsages])=> {
        let usagesMap = new Map();
        for (let computeUsage of computeUsages) {
            usagesMap.set(computeUsage.name.value.toLowerCase(), computeUsage);
        }
        for (let networkUsage of networkUsages) {
            usagesMap.set(networkUsage.name.value.toLowerCase(), networkUsage);
        }
        for (let storageUsage of storageUsages) {
            usagesMap.set(storageUsage.name.value.toLowerCase(), storageUsage);
        }
        return usagesMap;
    });

    return Promise.all([vmSizesCoresPromise,usagesPromise]).then(([vmSizesCores, usages]) => {
        //prepare core quota
        if(dependencies.has(ResourceType.VirtualMachines))
        for (let migrationInfo of dependencies.get(ResourceType.VirtualMachines)) {
            
            const vm = migrationInfo.source.resource;
            const coreFamily = GetAzureRmVmCoreFamily(vm.hardwareProfile.vmSize);
            if(!coreFamily){
                throw new Ex(`Core family for vm size '${vm.hardwareProfile.vmSize}' does not support`);
            }
            if(!usages.has(coreFamily)){
                throw new Ex(`Core family '${coreFamily}' does not support on location '${location}'`);
            }
            if(!vmSizesCores.has(vm.hardwareProfile.vmSize)){
                throw new Ex(`Vm size '${vm.hardwareProfile.vmSize}' does not support on location '${location}'`);
            }
            const numberOfCores = vmSizesCores.get(vm.hardwareProfile.vmSize);

            usages.get("cores").currentValue += numberOfCores;
            usages.get(coreFamily).currentValue += numberOfCores;
        }
        
        //prepare other quota
        for(let [type, migrationInfos] of dependencies){
            for(let migrationInfo of migrationInfos){
                //check dependencies that need to be created
                if(migrationInfo.destination.resource != null)
                    usages.get(type).currentValue += 1;
            }
        }
        
        //check quota
        const outOfQuota = [];
        for(let [type, usage] of usages){
            if(usage.currentValue > usage.limit) {
                outOfQuota.push(usage.name.localizedValue);
            }
        }

        //throw 
        if(outOfQuota.length > 0 ){
            throw new Ex(`'${outOfQuota.join(", ")}' quota exeeds its limit.`);
        }
        return;
    });
}

module.exports = validateQuotaAsync;