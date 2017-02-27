'use strict';

const ResourceType = require('./ResourceType'),
    azureEx = require('./azureExtensions'),
    telemetry = require('./telemetry');

class Deployable {
    /**
     * @param {VmMigrationJob} job
     */
    constructor(job) {
        /** @type {ResourceMigrationInfo[]} */
        this.phases = [];
        this.job = job;
    }

    /**
     * Add all items of the ResourceMigrationInfo arrays passed as parameters as the current phase.
     * Next call will add into the a new phase.
     * @param {Array} groups - An array of ResourceMigrationInfo[]
     */
    addPhase(...groups) {
        const resources = [];
        for (let group of groups) {
            Array.prototype.push.apply(resources, group);
        }

        this.phases.push(resources);
    }

    addVmPhase(vmInfo) {
        let resources = [];
        if(vmInfo) {
            resources.push(vmInfo);
        }
        this.phases.push(resources);
    }

    /**
     * Deploy all the resources in the phases property
     * @param {Object} operations
     */
    deployAsync(operations) {
        let p = Promise.resolve();
        const len = this.phases.length;
        for (let i = 0; i < len; i++) {
            p = p.then(() => {
                const migrationInfos = this.phases[i];
                telemetry.trackEvent(`Deploying phase ${i + 1}/${len}.`,{ migrationInfos: JSON.stringify(migrationInfos) });
                console.log(`Deploying phase ${i + 1}/${len}. ${migrationInfos.length} resources.`);
                let promises = [];
                for (let migrationInfo of migrationInfos) {
                    if (!migrationInfo.needsDeployment) continue;
                    const resourceInfo = migrationInfo.destination;
                    const resource = resourceInfo.resourceId;
                    promises.push(azureEx.createOrUpdateAsync(operations[resource.resourceType],
                        resource.resourceGroup, resource.resourceName, resourceInfo.resource));
                    console.log(`Start deploying resourceGroups/${resource.resourceGroup}/providers/${resource.provider}/${resource.resourceType}/${resource.resourceName}`);
                }

                return Promise.all(promises);
            });
        }

        p = p.then(() => {
            return this.job;
        })
        return p;
    }
}

module.exports = Deployable;