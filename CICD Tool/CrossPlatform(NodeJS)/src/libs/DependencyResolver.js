'use strict';

const ResourceType = require('./ResourceType'),
    models = require('./models'),
    azureEx = require('./azureExtensions'),
    Vhd = require('./Vhd'),
    vmSpecifics = require('./vmSpecifics');

class DependencyResolver {
    /**
     * @constructs
     * @param {AzureManagementClients} clients
     */
    constructor(clients) {
        this.clients = clients;
    }

    /**
     * @param {string} type - Resource type
     * @param {string} resourceGroup - Resource group
     * @param {string} name - Resource name
     * @return {Promise<ResourceDependency>}
     */
    resolveAsync(type, resourceGroup, name) {
        const vmOps = this.clients.computeClient.virtualMachines;
        const asOps = this.clients.computeClient.availabilitySets;
        const stgOps = this.clients.storageClient.storageAccounts;
        const nicOps = this.clients.networkClient.networkInterfaces;
        const pipOps = this.clients.networkClient.publicIPAddresses;
        const nsgOps = this.clients.networkClient.networkSecurityGroups;
        const vnetOps = this.clients.networkClient.virtualNetworks;
        const networkClient = this.clients.networkClient;
        let resourceIdProcessed = {};
        let storageProcessed = {};

        return azureEx.getAsync(vmOps, resourceGroup, name).then(vm => {
            return new vmSpecifics.VmDependency(vm);
        }).then(dep => {
            if (dep.root.availabilitySet) {
                return getAsyncWithIdCheck(asOps, dep.root.availabilitySet.id, resourceIdProcessed).then(availabilitySet => {
                    dep.pushToDependencies(availabilitySet);
                    return dep;
                });
            } else {
                return Promise.resolve(dep);
            }
        }).then(dep => {
            return azureEx.listAsync(stgOps).then(storList => {
                let osDiskInfo = uriResolver(dep.root.storageProfile.osDisk.vhd.uri)
                let osStorageRg = getStorageResourceGroup(storList, osDiskInfo.storageAccount);
                dep.osDisk = new Vhd.OsDisk(osStorageRg, osDiskInfo.storageAccount, osDiskInfo.container, osDiskInfo.blob,
                    dep.root.storageProfile.osDisk.vhd.uri, dep.root.storageProfile.osDisk.osType);

                return stgGetPropertiesAsyncWithCheck(stgOps, osStorageRg, osDiskInfo.storageAccount, storageProcessed).then(account => {
                    dep.pushToDependencies(account);

                    if (dep.root.storageProfile.dataDisks.length === 0) {
                        return dep;
                    } else {
                        let dataDiskProcessed = 0;
                        let dataDiskPromises = [];
                        for (let dataDisk of dep.root.storageProfile.dataDisks) {
                            let dataDiskInfo = uriResolver(dataDisk.vhd.uri);
                            let dataDiskRg = getStorageResourceGroup(storList, dataDiskInfo.storageAccount);
                            dep.dataDisks.push(new Vhd.DataDisk(dataDiskRg, dataDiskInfo.storageAccount, dataDiskInfo.container, dataDiskInfo.blob,
                                dataDisk.vhd.uri, dataDisk.lun));

                            let promise = stgGetPropertiesAsyncWithCheck(stgOps, dataDiskRg, dataDiskInfo.storageAccount, storageProcessed);
                            dataDiskPromises.push(promise);
                        }
                        return Promise.all(dataDiskPromises).then(dataDisks => {
                            for (let dataDisk of dataDisks) {
                                dep.pushToDependencies(dataDisk);
                            }
                            return dep;
                        });
                    }
                });
            });

        }).then(dep => {
            if (dep.root.networkProfile.networkInterfaces) {

                let nicPromises = [];

                for (let nic of dep.root.networkProfile.networkInterfaces) {
                    let promise = getNicDependencieAsync(networkClient, nic.id, resourceIdProcessed);
                    nicPromises.push(promise);
                }

                return Promise.all(nicPromises).then(nicDepsArrays => {
                    for (let nicDeps of nicDepsArrays) {
                        for (let nicDep of nicDeps) {
                            dep.dependencies.push(nicDep);
                        }
                    }
                    return dep;
                });
            } else {
                return Promise.resolve(dep);
            }
        });
    }
}

function uriResolver(uri) {
    let uriSplit = uri.split('/');
    let storageAccount = uriSplit[2].split('.')[0];
    let container = uriSplit[3];
    let blob = uriSplit[uriSplit.length - 1];

    return { storageAccount, container, blob };
}

function getAsyncWithIdCheck(operations, resourceId, resourceIdProcessed) {
    if (resourceIdProcessed.hasOwnProperty(resourceId)) {
        return Promise.resolve(null);
    } else {
        resourceIdProcessed[resourceId] = true;
        return azureEx.getAsyncWithId(operations, resourceId);
    }
}

function stgGetPropertiesAsyncWithCheck(stgOps, storRg, storName, stgProcessed) {
    if (stgProcessed.hasOwnProperty(storName)) {
        return Promise.resolve(null);
    } else {
        stgProcessed[storName] = true;
        return azureEx.stgGetPropertiesAsync(stgOps, storRg, storName);
    }
}

function getNicDependencieAsync(networkClient, nicId, resourceIdProcessed) {
    return new Promise((resolve, reject) => {
        getAsyncWithIdCheck(networkClient.networkInterfaces, nicId, resourceIdProcessed)
            .then(nicResource => {

                let depsToAdd = [];

                if (nicResource) {
                    depsToAdd.push(nicResource);

                    let ipConfig = nicResource.ipConfigurations[0];
                    getIpConfigDependenciesAsync(networkClient, ipConfig, resourceIdProcessed).then(ipConfigDeps => {
                        for (let ipConfigDep of ipConfigDeps) {
                            depsToAdd.push(ipConfigDep);
                        }
                        return depsToAdd;
                    }).then(depsToAdd => {
                        if (nicResource.networkSecurityGroup) {
                            getAsyncWithIdCheck(networkClient.networkSecurityGroups, nicResource.networkSecurityGroup.id, resourceIdProcessed).then(nsg => {
                                depsToAdd.push(nsg);
                                resolve(depsToAdd);
                            });
                        } else {
                            resolve(depsToAdd);
                        }
                    });
                } else {
                    resolve(depsToAdd);
                }
            });
    });
}

function getIpConfigDependenciesAsync(networkClient, ipConfig, resourceIdProcessed) {
    let depsToAdd = [];

    return getVnDependenciesAsync(networkClient, ipConfig.subnet.id, resourceIdProcessed).then(vnDeps => {
        for (let vnDep of vnDeps) {
            depsToAdd.push(vnDep);
        }
        return depsToAdd;
    }).then(depsToAdd => {
        if (ipConfig.publicIPAddress) {
            return getAsyncWithIdCheck(networkClient.publicIPAddresses, ipConfig.publicIPAddress.id, resourceIdProcessed).then(pip => {
                depsToAdd.push(pip);
                return depsToAdd;
            });
        } else {
            return Promise.resolve(depsToAdd);
        }
    }).then(depsToAdd => {
        if (ipConfig.loadBalancerBackendAddressPools) {
            return getLbDependenciesAsync(networkClient, ipConfig.loadBalancerBackendAddressPools[0].id, resourceIdProcessed).then(lbDeps => {
                for (let lbDep of lbDeps) {
                    depsToAdd.push(lbDep);
                }
                return depsToAdd;
            });
        } else {
            return Promise.resolve(depsToAdd);
        }
    });
}

function getVnDependenciesAsync(networkClient, vnId, resourceIdProcessed) {
    return getAsyncWithIdCheck(networkClient.virtualNetworks, vnId, resourceIdProcessed).then(vnResource => {
        let depsToAdd = [];
        if (vnResource) {
            depsToAdd.push(vnResource);

            let promises = [];

            for (let subnet of vnResource.subnets) {
                if (subnet.networkSecurityGroup) {
                    promises.push(azureEx.getAsyncWithId(networkClient.networkSecurityGroups, subnet.networkSecurityGroup.id));
                }
            }

            return Promise.all(promises).then(nsgDeps => {
                for (let nsgDep of nsgDeps) {
                    depsToAdd.push(nsgDep);
                }
                return depsToAdd;
            });
        } else {
            return Promise.resolve(depsToAdd);
        }
    });
}

function getLbDependenciesAsync(networkClient, lbId, resourceIdProcessed) {
    return getAsyncWithIdCheck(networkClient.loadBalancers, lbId, resourceIdProcessed).then(lbResource => {
        let depsToAdd = [];
        if (lbResource) {
            depsToAdd.push(lbResource);

            let promises = [];

            for (let lbIp of lbResource.frontendIPConfigurations) {
                if (lbIp.publicIPAddress) {
                    promises.push(azureEx.getAsyncWithId(networkClient.publicIPAddresses, lbIp.publicIPAddress.id));
                }
            }

            return Promise.all(promises).then(ipDeps => {
                for (let ipDep of ipDeps) {
                    depsToAdd.push(ipDep);
                }
                return depsToAdd;
            });
        } else {
            return Promise.resolve(depsToAdd);
        }
    });
}

function getStorageResourceGroup(storageList, storageAccountName) {
    for (let storage of storageList) {
        if (storage.name === storageAccountName) {
            let idInfo = models.ResourceId.parse(storage.id);
            return idInfo.resourceGroup;
        }
    }
}

module.exports = DependencyResolver;