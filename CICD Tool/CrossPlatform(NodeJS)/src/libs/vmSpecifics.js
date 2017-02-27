'use strict';

const MigrationJob = require('./MigrationJob'),
    Deployable = require('./Deployable'),
    ResourceType = require('./ResourceType'),
    models = require('./models'),
    Validator = require('./Validator');

class VmDependency extends models.ResourceDependency {
    /**
     * @param {Object} root
     */
    constructor(root) {
        super(root);
        /** @type {OsDisk} */
        this.osDisk = null;
        /** @type {DataDisk[]} */
        this.dataDisks = [];
    }
}

class VmMigrationJob extends MigrationJob {
    /**
     * @param {MigrationSite} srcSite
     * @param {MigrationSite} destSite
     * @param {string} destLocation
     * @param {VmDependency} vmDep
     */
    constructor(srcSite, destSite, destLocation, vmDep) {
        super(srcSite, destSite, destLocation, vmDep);
        this.osDisk = vmDep.osDisk;
        this.dataDisks = vmDep.dataDisks;
    }

    /**
     * @return {Deployable}
     */
    toDeployable() {
        const deployable = new Deployable(this);
        deployable.addPhase(this.dependencies.get(ResourceType.AvailabilitySets),
            this.dependencies.get(ResourceType.NetworkSecurityGroups),
            this.dependencies.get(ResourceType.PublicIpAddresses));
        deployable.addPhase(this.dependencies.get(ResourceType.VirtualNetworks));
        deployable.addPhase(this.dependencies.get(ResourceType.LoadBalancers));
        deployable.addPhase(this.dependencies.get(ResourceType.NetworkInterfaces));
        deployable.addVmPhase(this.root);
        return deployable;
    }
}

module.exports = {
    VmDependency,
    VmMigrationJob
};