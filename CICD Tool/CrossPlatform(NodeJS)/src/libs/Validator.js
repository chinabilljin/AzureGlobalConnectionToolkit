'use strict';

const exceptions = require('./exceptions'),
    azureEx = require('./azureExtensions'),
    ResourceType = require('./ResourceType'),
    utils = require('./utils'),
    models = require('./models'),
    validateQuotaAsync = require('./quotaValidator');

const Ex = exceptions.ValidationFailureException;

class Validator {
    /**
     * @param {VmMigrationJob} job
     * @param {AzureManagementClients} clients
     */
    constructor(job, clients) {
        this.job = job;
        this.clients = clients;
        /** @type {Set<string>} */
        this.newResourceGroups = new Set();
        /** @type {Set<ResourceInfo>} */
        this.newStorageAccounts = new Set();
    }

    /**
     * @param {ResourceMigrationInfo} migrationInfo
     * @param {string} type
     * @param {string} destLocation
     * @return {Promise<Object>}
     */
    validateGenericAsync(migrationInfo, type, destLocation) {
        /** @type {ValidationConfig} */
        const config = configs[type];

        const resourceId = migrationInfo.destination.resourceId;
        const resourceGroup = resourceId.resourceGroup;
        const resourceName = resourceId.resourceName;
        config.validateName(resourceName);

        if (this.newResourceGroups.has(resourceGroup)) {
            // We know the resource group doesn't exist yet so no need to check further
            config.preparePayload(migrationInfo, destLocation, this.job.dependencies);
            return;
        }

        validateResourceGroupName(resourceGroup);
        return azureEx.getAsync(this.clients[type], resourceGroup, resourceName).then(result => {
            if (config.mustCreateNew) {
                throw new Ex(`${resourceId} already exists`);
            }
            if (destLocation && result.location != destLocation) {
                throw new Ex(`${resourceId} already exists in a different location ${result.location}. The specified location is ${destLocation}.`);
            }

            return result;
        }, err => {
            if (err.code == azureEx.ErrorCode.ResourceGroupNotFound) {
                this.newResourceGroups.add(resourceGroup);
            }
            if (err.code == azureEx.ErrorCode.ResourceGroupNotFound ||
                err.code == azureEx.ErrorCode.ResourceNotFound) {
                config.preparePayload(migrationInfo, destLocation, this.job.dependencies);
                return;
            }

            throw new exception.AzMigrationException(err.toString());
        });
    }

    /**
     * @param {ResourceMigrationInfo} migrationInfo
     * @param {string} destLocation
     * @return {Promise<Object>}
     */
    validateStorageAccountAsync(migrationInfo, destLocation) {
        const stgOps = this.clients.storageClient.storageAccounts;
        const srcAccount = migrationInfo.source.resource;
        const resourceId = migrationInfo.destination.resourceId;
        const resourceGroup = resourceId.resourceGroup;
        const name = resourceId.resourceName;

        if (srcAccount.encryption) {
            throw new Ex(`Source storage account ${srcAccount.name} is encrypted. Migration of encrypted storage accounts is not supported.`);
        }

        validateResourceGroupName(resourceGroup);
        validateStorageAccountName(name);
        const p = azureEx.stgCheckNameAvailabilityAsync(stgOps, name).then(result => {
            if (result.nameAvailable) {
                this.newStorageAccounts.add(migrationInfo.destination);
                // Prepare the payload for create API
                preparePayloadForCreateStorageAccount(migrationInfo, destLocation, this.job.dependencies);
                return;
            }

            if (result.reason == 'AlreadyExists') {
                return azureEx.stgGetPropertiesAsync(stgOps, resourceGroup, name).then(account => {
                    if (account.kind != srcAccount.kind) {
                        throw new Ex(`Storage account '${name}' already exists in resource group '${resourceGroup}' but the kind '${account.kind}' is incompatible`);
                    } else if (account.location != destLocation) {
                        throw new Ex(`Storage account '${name}' already exists in resource group '${resourceGroup}' but the location '${account.location}' is different`);
                    } else if (account.sku.tier != srcAccount.sku.tier) {
                        throw new Ex(`Storage account '${name}' already exists in resource group '${resourceGroup}' but the SKU tier '${account.sku.tier}' is different`);
                    }

                    return account;
                }, err => {
                    if (err.code == azureEx.ErrorCode.ResourceGroupNotFound ||
                        err.code == azureEx.ErrorCode.ResourceNotFound) {
                        throw new Ex(result.message);
                    }
                    throw new exception.AzMigrationException(err);
                });
            }

            throw new exceptions.AzMigrationException(result.message);
        });

        if (this.newResourceGroups.has(resourceGroup)) {
            // Resource group is already planned to be created, no need to check its existence
            return p;
        }

        // Add resource group to the new resource group set if necessary
        const checkRgExistencePromise = azureEx.rgCheckExistenceAsync(this.clients.resourceClient.resourceGroups, resourceGroup);
        return Promise.all([p, checkRgExistencePromise]).then(([account, isExisting]) => {
            if (!isExisting) {
                this.newResourceGroups.add(resourceGroup);
            }
            return account;
        });
    }

    /**
     * @return {Promise<Object>}
     */
    validateVmMigrationAsync() {
        let p = Promise.resolve();
        const destLocation = this.job.destLocation

        p = p.then(() => {
            return this.validateGenericAsync(this.job.root, ResourceType.VirtualMachines, destLocation);
        });

        for (let [type, migrationInfos] of this.job.dependencies) {
            // Storage account specific validations
            if (type == ResourceType.StorageAccounts) {
                for (let migrationInfo of migrationInfos) {
                    p = p.then(() => {
                        return this.validateStorageAccountAsync(migrationInfo, destLocation);
                    });
                }
                continue;
            }

            // Public IP address specific validations
            if(type == ResourceType.PublicIpAddresses) {
                for (let migrationInfo of migrationInfos) {
                    const dnsSettings = migrationInfo.source.resource.dnsSettings;
                    if(!dnsSettings) {
                        continue; // Skip if dnsSettings is missing
                    }

                    p = p.then(() => {
                        return azureEx.dnsCheckNameAvailabilityAsync(this.clients.networkClient, dnsSettings.domainNameLabel, destLocation).then(result => {
                            if(!result.available) {
                                throw new Ex(`Domain name label '${dnsSettings.domainNameLabel}' has been taken in location '${destLocation}'`);
                            }
                        });
                    });
                }
            }

            // Validations for other types
            for (let migrationInfo of migrationInfos) {
                p = p.then(() => {
                    return this.validateGenericAsync(migrationInfo, type, destLocation);
                });
                // Virtual network specific validations
                if(type == ResourceType.VirtualNetworks) {
                    p = p.then(existingVnet => {
                        const result = checkVirtualNetworksCompatibility(migrationInfo.source.resource, existingVnet);
                        if (!result.isCompatible) {
                            throw new Ex(`Virtual network '${migrationInfo.destination.resourceId.resourceName}' already exists in resource group '${migrationInfo.destination.resourceId.resourceGroup}' and it's not compatible because ${result.reason}`);
                        }
                    });
                }

                // Public IP specific validations
                if(type == ResourceType.PublicIpAddresses) {
                    p = p.then(existingIp => {
                        const result = checkPublicIpAddressesCompatibility(existingIp);
                        if (!result.isCompatible) {
                            throw new Ex(`Public IP Address '${migrationInfo.source.resourceId.resourceName}' already exists in resource group '${migrationInfo.source.resourceId.resourceGroup}' and it's not compatible because ${result.reason}`);
                        }
                    });
                }
            }
        }

        p = p.then(() => { 
            return validateQuotaAsync(this.clients, destLocation, this.job.dependencies);
        });
        
        return p;
    }
}

/**
 * Determines whether the given virtual networks are compatible
 * @param {Object} src
 * @param {Object} dest
 * @return {Object} An object that indicates whether they are compatible and contains the reason why they are not
 */
function checkVirtualNetworksCompatibility(srcVnet, destVnet) {
    let isCompatible = true;
    let reason = null;

    if(destVnet) {
        for(let srcSubnet of srcVnet.subnets){
            let foundSubnet = destVnet.subnets.find( destSubnet => {
                return destSubnet.name == srcSubnet.name && destSubnet.addressPrefix == srcSubnet.addressPrefix;
            });
            if (!foundSubnet){
                isCompatible = false;
                reason = `Cannot match the subnet '${srcSubnet.name}' in destination virtual network. Either the subnet does not exist or the configuration incorrect.`
                return { isCompatible, reason };
            }
        }
    }
    return { isCompatible, reason };
}

function checkPublicIpAddressesCompatibility(dest) {
    let isCompatible = true;
    let reason = null;
    if (dest){
        if (dest.ipConfiguration){
            let ipConfig = models.ResourceId.parse(dest.ipConfiguration.id);
            if (ipConfig.resourceType == ResourceType.NetworkInterfaces){
                isCompatible = false;
                reason = `This public IP address has been use by another network interface '${ipConfig.resourceName}'.`
            }
        }
    }
    return { isCompatible, reason };
}

/**
 * Transforms a dependency resource ID in source resource to destination resource
 * @param {Object} src - Grandparent object of the ID in source resource
 * @param {Object} dest - Grandparent object of the ID in destination resource
 * @param {string} propName - The property name of the parent object of the ID
 * @param {ResourceMigrationInfo[]} migrationInfos Migration info of the type
 */
function transformResourceId(src, dest, propName, migrationInfos) {
    const srcProp = src[propName];
    if (srcProp) {
        const id = srcProp.id;
        const found = migrationInfos.find(migrationInfo => {
            return migrationInfo.source.resource.id.toLowerCase() == id.toLowerCase();
        });
        if (!found) {
            throw new Ex(`Couldn't find '${id}' in the dependencies`);
        }
        if (!dest.hasOwnProperty(propName)) {
            dest[propName] = {};
        }
        dest[propName].id = found.destination.resourceId.toString();
    }
}

/**
 * Transforms a dependency sub resource ID from source format to destination format
 * @param {Object} prop - Parent object of the ID
 * @param {ResourceMigrationInfo[]} migrationInfos - Migration info of the type
 */
function transformSubResourceId(prop, migrationInfos) {
    if (prop) {
        const id = models.ResourceId.parse(prop.id);
        const found = migrationInfos.find(migrationInfo => {
            return migrationInfo.source.resourceId.resourceName === id.resourceName;
        });
        if (!found) {
            throw new Ex(`Couldn't find a resource of type '${id.resourceType}' and name '${id.resourceName}' in the dependencies`);
        }
        const parentDestId = found.destination.resourceId;
        id.subscriptionId = parentDestId.subscriptionId;
        id.resourceGroup = parentDestId.resourceGroup;
        id.resourceName = parentDestId.resourceName;
        prop.id = id.toString();
    }
}

/**
 * Transforms a dependency sub resource ID from source format to destination format
 * @param {Object} prop - Parent object of the ID
 * @param {ResourceId} destResourceId - Destination resource ID
 */
function transformSubResourceIdCore(prop, destResourceId) {
    if (prop) {
        const id = models.ResourceId.parse(prop.id);
        id.subscriptionId = destResourceId.subscriptionId;
        id.resourceGroup = destResourceId.resourceGroup;
        id.resourceName = destResourceId.resourceName;
        prop.id = id.toString();
    }
}

/**
 * Deletes the common unnecessary properties from the resource object retreived with the get API
 * so it can be used for created API.
 * @param {Object} resource - Resource object retreived with the get API
 */
function deleteUnnecessaryProps(resource) {
    delete resource.id;
    delete resource.etag;
    delete resource.provisioningState;
}

/**
 * @param {Object} src - Source resource
 * @param {string} location - Destination location
 * @return {Object} The payload can be used to create the destination resource
 */
function preparePayloadForCreateGeneric(src, location) {
    return {
        location: location,
        tags: utils.deepCopy(src.tags)
    };
}

/**
 * @param {ResourceMigrationInfo} migrationInfo - Migration info
 * @param {string} location - Destination location
 * @param {Map<string, ResourceMigrationInfo[]>} dependencies - Dependencies from the migration job
 */
function preparePayloadForCreateStorageAccount(migrationInfo, location, dependencies) {
    const src = migrationInfo.source.resource;
    const result = preparePayloadForCreateGeneric(src, location);
    result.kind = src.kind;
    result.sku = utils.deepCopy(src.sku);
    result.accessTier = src.accessTier;
    migrationInfo.destination.resource = result;
};

/**
 * @param {ResourceMigrationInfo} migrationInfo - Migration info
 * @param {string} location - Destination location
 * @param {Map<string, ResourceMigrationInfo[]>} dependencies - Dependencies from the migration job
 */
function preparePayloadForCreateAvailabilitySet(migrationInfo, location, dependencies) {
    const src = migrationInfo.source.resource;
    const result = preparePayloadForCreateGeneric(src, location);
    result.platformUpdateDomainCount = src.platformUpdateDomainCount;
    result.platformFaultDomainCount = src.platformFaultDomainCount;
    migrationInfo.destination.resource = result;
};

/**
 * @param {ResourceMigrationInfo} migrationInfo - Migration info
 * @param {string} location - Destination location
 * @param {Map<string, ResourceMigrationInfo[]>} dependencies - Dependencies from the migration job
 */
function preparePayloadForCreateNetworkSecurityGroup(migrationInfo, location, dependencies) {
    const src = migrationInfo.source.resource;
    const result = preparePayloadForCreateGeneric(src, location);
    result.securityRules = utils.deepCopy(src.securityRules);
    migrationInfo.destination.resource = result;
}

/**
 * @param {ResourceMigrationInfo} migrationInfo - Migration info
 * @param {string} location - Destination location
 * @param {Map<string, ResourceMigrationInfo[]>} dependencies - Dependencies from the migration job
 */
function preparePayloadForCreatePublicIpAddress(migrationInfo, location, dependencies) {
    const src = migrationInfo.source.resource;
    const result = preparePayloadForCreateGeneric(src, location);
    result.publicIPAllocationMethod = src.publicIPAllocationMethod;
    result.publicIPAddressVersion = src.publicIPAddressVersion;
    result.idleTimeoutInMinutes = src.idleTimeoutInMinutes;
    if (src.dnsSettings) {
        result.dnsSettings = {
            domainNameLabel: src.dnsSettings.domainNameLabel
        };
    }
    migrationInfo.destination.resource = result;
}

/**
 * @param {ResourceMigrationInfo} migrationInfo - Migration info
 * @param {string} location - Destination location
 * @param {Map<string, ResourceMigrationInfo[]>} dependencies - Dependencies from the migration job
 */
function preparePayloadForCreateVirtualNetwork(migrationInfo, location, dependencies) {
    const src = migrationInfo.source.resource;
    const result = preparePayloadForCreateGeneric(src, location);
    result.addressSpace = utils.deepCopy(src.addressSpace);
    result.dhcpOptions = utils.deepCopy(src.dhcpOptions);
    if (src.subnets) {
        result.subnets = [];
        for (let subnet of src.subnets) {
            const destSubnet = {
                name: subnet.name,
                addressPrefix: subnet.addressPrefix
            };
            transformResourceId(subnet, destSubnet, 'networkSecurityGroup', dependencies.get(ResourceType.NetworkSecurityGroups));
            result.subnets.push(destSubnet);
        }
    }
    migrationInfo.destination.resource = result;
}

/**
 * @param {ResourceMigrationInfo} migrationInfo - Migration info
 * @param {string} location - Destination location
 * @param {Map<string, ResourceMigrationInfo[]>} dependencies - Dependencies from the migration job
 */
function preparePayloadForCreateVirtualMachine(migrationInfo, location, dependencies) {
    const src = migrationInfo.source.resource;
    const result = preparePayloadForCreateGeneric(src, location);

    result.hardwareProfile = utils.deepCopy(src.hardwareProfile);
    
    result.storageProfile = utils.deepCopy(src.storageProfile);
    if (result.storageProfile.imageReference){
        delete result.storageProfile.imageReference;
    }
    if (result.storageProfile.osDisk.image){
        delete result.storageProfile.osDisk.image;
    }
    result.storageProfile.osDisk.createOption = 'Attach';
    for (let dataDisk of result.storageProfile.dataDisks){
        dataDisk.createOption = 'Attach'; 
        if (dataDisk.diskSizeGB){
            delete dataDisk.diskSizeGB;
        }
    }

    result.networkProfile = utils.deepCopy(src.networkProfile);
    for (let nic of result.networkProfile.networkInterfaces){
        transformSubResourceId(nic, dependencies.get(ResourceType.NetworkInterfaces));
    }

    if (src.availabilitySet){
        transformResourceId(src, result, 'availabilitySet', dependencies.get(ResourceType.AvailabilitySets));
    }

    migrationInfo.destination.resource = result;
}

/**
 * @param {ResourceMigrationInfo} migrationInfo - Migration info
 * @param {string} location - Destination location
 * @param {Map<string, ResourceMigrationInfo[]>} dependencies - Dependencies from the migration job
 */
function preparePayloadForCreateNetworkInterface(migrationInfo, location, dependencies) {
    const src = migrationInfo.source.resource;
    const result = preparePayloadForCreateGeneric(src, location);
    result.enableIPForwarding = src.enableIPForwarding;
    transformResourceId(src, result, 'networkSecurityGroup', dependencies.get(ResourceType.NetworkSecurityGroups));
    if (src.dnsSettings) {
        result.dnsSettings = {
            dnsServers: utils.deepCopy(src.dnsSettings.dnsServers),
            internalDnsNameLabel: src.dnsSettings.internalDnsNameLabel
        };
    }

    if (src.ipConfigurations) {
        result.ipConfigurations = utils.deepCopy(src.ipConfigurations);
        for (let config of result.ipConfigurations) {
            deleteUnnecessaryProps(config);
            transformSubResourceId(config.subnet, dependencies.get(ResourceType.VirtualNetworks));
            transformResourceId(config, config, 'publicIPAddress', dependencies.get(ResourceType.PublicIpAddresses));
            if (config.loadBalancerBackendAddressPools) {
                for (let pool of config.loadBalancerBackendAddressPools) {
                    transformSubResourceId(pool, dependencies.get(ResourceType.LoadBalancers));
                }
            }

            if (config.loadBalancerInboundNatRules) {
                for (let rule of config.loadBalancerInboundNatRules) {
                    transformSubResourceId(rule, dependencies.get(ResourceType.LoadBalancers));
                }
            }
        }
    }

    migrationInfo.destination.resource = result;
}

/**
 * @param {ResourceMigrationInfo} migrationInfo - Migration info
 * @param {string} location - Destination location
 * @param {Map<string, ResourceMigrationInfo[]>} dependencies - Dependencies from the migration job
 */
function preparePayloadForCreateLoadBalancer(migrationInfo, location, dependencies) {
    const src = migrationInfo.source.resource;
    const result = utils.deepCopy(src);
    result.location = location;
    deleteUnnecessaryProps(result);
    delete result.name;
    delete result.resourceGuid;
    if (result.frontendIPConfigurations) {
        for (let config of result.frontendIPConfigurations) {
            deleteUnnecessaryProps(config);
            delete config.inboundNatRules;
            delete config.loadBalancingRules;
            transformResourceId(config, config, 'publicIPAddress', dependencies.get(ResourceType.PublicIpAddresses));
            transformSubResourceId(config.subnet, dependencies.get(ResourceType.VirtualNetworks));
        }
    }
    //backendAddressPool
    if (result.backendAddressPools){
        for (let backendPool of result.backendAddressPools){
            deleteUnnecessaryProps(backendPool);
            delete backendPool.loadBalancingRules;
            delete backendPool.backendIPConfigurations;
        }
    }
    //Probe
    if (result.probes){
        for (let probe of result.probes){
            deleteUnnecessaryProps(probe);
            delete probe.loadBalancingRules;
        }
    }
    let destLbId = migrationInfo.destination.resourceId;
    if (result.inboundNatRules) {
        for (let rule of result.inboundNatRules) {
            deleteUnnecessaryProps(rule);
            delete rule.backendIPConfiguration;
            transformSubResourceIdCore(rule.frontendIPConfiguration, destLbId);
        }
    }

    if (result.inboundNatPools) {
        for (let pool of result.inboundNatPools) {
            deleteUnnecessaryProps(pool);
            transformSubResourceIdCore(pool.frontendIPConfiguration, destLbId);
        }
    }

    if (result.loadBalancingRules) {
        for (let rule of result.loadBalancingRules) {
            deleteUnnecessaryProps(rule);
            transformSubResourceIdCore(rule.frontendIPConfiguration, destLbId);
            transformSubResourceIdCore(rule.backendAddressPool, destLbId);
            transformSubResourceIdCore(rule.probe, destLbId);
        }
    }

    migrationInfo.destination.resource = result;
}

/**
 * @param {string} name - The name to be validated
 * @param {number} minLength - Minimum name length
 * @param {number} maxLength - Maximum name length
 * @param {RegExp} regex - Regular expression object used to test the name
 * @param {string} typeName - The type name
 * @param {string} validChars - The error message to use when regular expression test fails
 */
function validateName(name, minLength, maxLength, regex, typeName, validChars) {
    if (name.length < minLength || name.length > maxLength) {
        throw new Ex(`${typeName} name length must be within [${minLength}-${maxLength}]`);
    }
    if (!regex.test(name)) {
        throw new Ex(`${typeName} name can only contain ${validChars}`);
    }
}

/**
 * @param {string} name
 */
function validateResourceGroupName(name) {
    validateName(name, 1, 64, /^[-_a-zA-Z0-9]+$/, 'Resource group',
        'alphanumeric, underscore, and hyphen');
}

/**
 * @param {string} name
 */
function validateAvailabilitySetName(name) {
    validateName(name, 1, 64, /^[-_a-zA-Z0-9]+$/, 'Availability set',
        'alphanumeric, underscore, and hyphen');
}

/**
 * @param {string} name
 */
function validateVirtualMachineName(name) {
    validateName(name, 1, 64, /^[-_a-zA-Z0-9]+$/, 'Virtual machine',
        'alphanumeric, underscore, and hyphen');
}

/**
 * @param {string} name
 */
function validateStorageAccountName(name) {
    validateName(name, 3, 24, /^[a-z0-9]+$/, 'Storage account',
        'lower-case alphanumeric characters');
}

/**
 * @param {string} name
 */
function validateVirtualNetworkName(name) {
    validateName(name, 2, 64, /^[-_.a-zA-Z0-9]+$/, 'Virtual network',
        'alphanumeric, dash, underscore, and peirod');
}

/**
 * @param {string} name
 */
function validateNetworkInterfaceName(name) {
    validateName(name, 1, 80, /^[-_.a-zA-Z0-9]+$/, 'Network interface',
        'alphanumeric, dash, underscore, and peirod');
}

/**
 * @param {string} name
 */
function validateNetworkSecurityGroupName(name) {
    validateName(name, 1, 80, /^[-_.a-zA-Z0-9]+$/, 'Network security group',
        'alphanumeric, dash, underscore, and peirod');
}

/**
 * @param {string} name
 */
function validatePublicIpAddressName(name) {
    validateName(name, 1, 80, /^[-_.a-zA-Z0-9]+$/, 'Public IP Address',
        'alphanumeric, dash, underscore, and peirod');
}

/**
 * @param {string} name
 */
function validateLoadBalancerName(name) {
    validateName(name, 1, 80, /^[-_.a-zA-Z0-9]+$/, 'Load balancer',
        'alphanumeric, dash, underscore, and peirod');
}

class ValidationConfig {
    /**
     * @param {function} validateNameFunc
     * @param {function} prepareForCreateFunc
     * @param {boolean} mustCreateNew
     */
    constructor(validateNameFunc, preparePayloadFunc, mustCreateNew = false) {
        this.validateName = validateNameFunc;
        this.preparePayload = preparePayloadFunc;
        this.mustCreateNew = mustCreateNew;
    }
}

const configs = {};
configs[ResourceType.AvailabilitySets] = new ValidationConfig(
    validateAvailabilitySetName,
    preparePayloadForCreateAvailabilitySet
);
configs[ResourceType.LoadBalancers] = new ValidationConfig(
    validateLoadBalancerName,
    preparePayloadForCreateLoadBalancer
);
configs[ResourceType.NetworkInterfaces] = new ValidationConfig(
    validateNetworkInterfaceName,
    preparePayloadForCreateNetworkInterface,
    true
);
configs[ResourceType.NetworkSecurityGroups] = new ValidationConfig(
    validateNetworkSecurityGroupName,
    preparePayloadForCreateNetworkSecurityGroup
);
configs[ResourceType.PublicIpAddresses] = new ValidationConfig(
    validatePublicIpAddressName,
    preparePayloadForCreatePublicIpAddress
);
configs[ResourceType.StorageAccounts] = new ValidationConfig(
    validateStorageAccountName,
    preparePayloadForCreateStorageAccount
);
configs[ResourceType.VirtualMachines] = new ValidationConfig(
    validateVirtualMachineName,
    preparePayloadForCreateVirtualMachine,
    true
);
configs[ResourceType.VirtualNetworks] = new ValidationConfig(
    validateVirtualNetworkName,
    preparePayloadForCreateVirtualNetwork
);

module.exports = Validator;