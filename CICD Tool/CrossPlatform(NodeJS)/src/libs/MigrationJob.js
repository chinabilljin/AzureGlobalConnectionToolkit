'use strict';

const azureEx = require('./azureExtensions'),
    models = require('./models'),
    exceptions = require('./exceptions'),
    ResourceType = require('./ResourceType'),
    telemetry = require('./telemetry');

class MigrationJob {
    /**
     * @constructor
     * @param {MigrationSite} srcSite - Source migration site
     * @param {MigrationSite} destSite - Destination migration site
     * @param {string} destLocation - The destination location
     * @param {ResourceDependency} resourceDep - The dependency resolve result
     */
    constructor(srcSite, destSite, destLocation, resourceDep) {
        this.srcSite = srcSite;
        this.destSite = destSite;
        this.destLocation = destLocation;

        const destSubId = destSite.subscriptionId;
        const rootInfo = models.ResourceInfo.fromResource(resourceDep.root);

        /** @type {ResourceMigrationInfo} */
        this.root = models.ResourceMigrationInfo.fromSource(rootInfo, destSubId);

        /** @type {Map<string, ResourceMigrationInfo[]>} */
        this.dependencies = new Map();

        for (let dependency of resourceDep.dependencies) {
            const resourceInfo = models.ResourceInfo.fromResource(dependency);
            this.addDependency(resourceInfo.resourceId.resourceType,
                models.ResourceMigrationInfo.fromSource(resourceInfo, destSubId));
        }
    }

    /**
     * @param {string} type Resource type as defined in ResourceType
     * @param {ResourceMigrationInfo} resource
     */
    addDependency(type, resource) {
        const deps = this.dependencies;
        if (deps.has(type)) {
            deps.get(type).push(resource);
        } else {
            deps.set(type, [resource]);
        }
    }

    /**
     * @param {ResourceGroups} resourceGroupOperations
     * @param {Iterable<string>} resourceGroups
     * @return {Promise<Object[]]>}
     */
    static ensureResourceGroupsAsync(resourceGroupOperations, resourceGroups, location) {
        const promises = [];
        for (let resourceGroup of resourceGroups) {
            promises.push(azureEx.rgCreateOrUpdateAsync(resourceGroupOperations, resourceGroup, { location }));
            telemetry.trackEvent(`Creating resource group`, { ResourceGroupName: resourceGroup });
            console.log(`Creating resource group '${resourceGroup}'`);
        }

        return Promise.all(promises);
    }

    /**
     * @param {StorageAccounts} storageAccountOperations
     * @param {Iterable<ResourceInfo>} storageAccounts
     * @param {Promise<Object[]>}
     */
    static ensureStorageAccountsAsync(storageAccountOperations, storageAccounts) {
        const promises = [];
        for (let storageAccount of storageAccounts) {
            const id = storageAccount.resourceId;
            promises.push(azureEx.stgCreateAsync(storageAccountOperations, id.resourceGroup, id.resourceName, storageAccount.resource));
            telemetry.trackEvent(`Start deploying`, { ResourceId: id });
            console.log(`Start deploying ${id}`);
        }

        return Promise.all(promises);
    }
}

module.exports = MigrationJob;