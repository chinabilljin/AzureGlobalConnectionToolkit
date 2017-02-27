'use strict';

const AzureManagementClients = require('./AzureManagementClients'),
    DependencyResolver = require('./DependencyResolver'),
    MigrationJob = require('./MigrationJob'),
    Deployable = require('./Deployable'),
    ResourceType = require('./ResourceType'),
    azureEx = require('./azureExtensions'),
    models = require('./models'),
    exceptions = require('./exceptions'),
    Validator = require('./Validator'),
    Vhd = require('./Vhd'),
    vmSpecifics = require('./vmSpecifics'),
    telemetry = require('./telemetry');

/**
 * @param {MigrationOptions} options
 * @return {Promise<any>} A promise that resolves when the migration is done.
 */
function migrateAsync(options) {
    const srcSite = options.srcSite;
    const destSite = options.destSite;
    const destSubId = destSite.subscriptionId;
    const srcClients = new AzureManagementClients(srcSite.credentials, srcSite.subscriptionId,
        srcSite.environment.resourceManagerEndpointUrl);
    const destClients = new AzureManagementClients(destSite.credentials, destSubId,
        destSite.environment.resourceManagerEndpointUrl);

    const destGroup = options.srcResourceGroup;
    const rgOps = destClients.resourceClient.resourceGroups;
    const destLocationPromise = azureEx.rgGetAsync(rgOps, destGroup).then(result => {
        telemetry.trackEvent("Deduced destination location", { DestinationLocation: result.location });
        console.log(`Deduced destination location to be '${result.location}'`);
        return result.location;
    }, err => {
        if (err.code == azureEx.ErrorCode.ResourceGroupNotFound && options.destLocation) {
            telemetry.trackEvent("Deduced destination location", { DestinationLocation: options.destLocation });
            return options.destLocation;
        }
        throw new exceptions.AzMigrationException('Destination location is not specified and cannot be deduced');
    });

    console.log(`Resolving dependencies...`);
    const dependencyResolver = new DependencyResolver(srcClients);
    const dependencyPromise = dependencyResolver.resolveAsync(ResourceType.VirtualMachines, options.srcResourceGroup, options.srcResourceName);
    return Promise.all([destLocationPromise, dependencyPromise]).then(([location, vmDep]) => {
        telemetry.trackEvent(`Resolved dependencies`, { dependencies: JSON.stringify(vmDep) });
        console.log(`Found ${vmDep.dependencies.length} dependencies`);
        // TODO: do resource renaming
        return new vmSpecifics.VmMigrationJob(srcSite, destSite, location, vmDep);
    }).then(job => {
        telemetry.trackEvent(`Vm migration job created`, { job: JSON.stringify(job) });
        console.log(`Validating the input against the destination environment`);
        const validator = new Validator(job, destClients);
        return validator.validateVmMigrationAsync().then(() => {
            return MigrationJob.ensureResourceGroupsAsync(rgOps, validator.newResourceGroups, job.destLocation);
        }).then(() => {
            return MigrationJob.ensureStorageAccountsAsync(destClients.storageClient.storageAccounts, validator.newStorageAccounts);
        }).then(() => {
            telemetry.trackEvent(`Resource group and storage account ensured`, { job: JSON.stringify(job) });
            return job;
        });
    }).then(job => {
        // Copy VHDs
        telemetry.trackEvent(`Start copying VHDs`, { job: JSON.stringify(job) });
        console.log(`Start copying VHDs`);
        let vhds = [];
        let promises = [];
        vhds.push(job.osDisk);
        if(!(!job.dataDisks))
            vhds = vhds.concat(job.dataDisks);
        vhds.forEach( (vhd) => {
            promises.push(vhd.copyAsync(srcClients.storageClient.storageAccounts, destClients.storageClient.storageAccounts));
        });
        return Promise.all(promises).then((progress)=>{
            return Vhd.showProgress(progress);
        }).then(()=>{
            job.root.destination.resource.storageProfile.osDisk.vhd.uri = job.osDisk.uri;
            for (let dataDisk of job.root.destination.resource.storageProfile.dataDisks){
                let found = job.dataDisks.find(targetDataDisk => {
                    return targetDataDisk.lun == dataDisk.lun;
                });
                if (!found) {
                    throw new exceptions.AzMigrationException(`Couldn't find '${dataDisk.name}' in the processed data disks`);
                }
                dataDisk.vhd.uri = found.uri;
            }
            console.log("All VHDs are copied");
            telemetry.trackEvent("All VHDs are copied",{ vhds: JSON.stringify(vhds) });
            return job;
        });
    }).then(job => {
        return job.toDeployable().deployAsync(destClients);
    }).then(job => {
        // Do final check
        telemetry.trackEvent("Start post validation",{ job: JSON.stringify(job) });
        console.log("Start post validation...");
        const vm = job.root.destination.resourceId;
        telemetry.trackEvent("Start post validation", { ResourceId: vm });
        return azureEx.getAsync(destClients.computeClient.virtualMachines,vm.resourceGroup,vm.resourceName).then(vm => {
            if(vm && vm.provisioningState === "Succeeded") {
                return "deploy succeeded";
            }
            return "post validation failed";
        }, () => {
            return "post validation failed";
        });
    });
}

module.exports = {
    migrateAsync
};