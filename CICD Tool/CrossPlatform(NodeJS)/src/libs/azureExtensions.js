'use strict';

const exceptions = require('./exceptions');
const models = require('./models');

function commonCallback(resolve, reject, err, result, request, response) {
    if (err) {
        reject(err);
    } else {
        resolve(result);
    }
}

function rgCheckExistenceAsync(resourceGroupOperations, name, options) {
    return new Promise((resolve, reject) => {
        resourceGroupOperations.checkExistence(name, options, commonCallback.bind(null, resolve, reject));
    });
}

function rgGetAsync(resourceGroupOperations, name, options) {
    return new Promise((resolve, reject) => {
        resourceGroupOperations.get(name, options, commonCallback.bind(null, resolve, reject));
    });
}

function rgCreateOrUpdateAsync(resourceGroupOperations, name, parameters, options) {
    return new Promise((resolve, reject) => {
        resourceGroupOperations.createOrUpdate(name, parameters, options, commonCallback.bind(null, resolve, reject));
    });
}

function rgEnsureAsync(resourceGroupOperations, name, location, options) {
    return rgCheckExistenceAsync(resourceGroupOperations, name, options).then(result => {
        if (result) {
            return rgGetAsync(resourceGroupOperations, name, options);
        } else {
            if (!location) {
                throw new exceptions.AzMigrationException('location is not provided and cannot be deduced');
            }

            return rgCreateOrUpdateAsync(resourceGroupOperations, name, { location: location }, options);
        }
    });
}

function stgCheckNameAvailabilityAsync(storageAccountOperations, name, options) {
    return new Promise((resolve, reject) => {
        storageAccountOperations.checkNameAvailability(name, options, commonCallback.bind(null, resolve, reject));
    });
}

function stgCreateAsync(storageAccountOperations, resourceGroupName, accountName, parameters, options) {
    return new Promise((resolve, reject) => {
        storageAccountOperations.create(resourceGroupName, accountName, parameters, options,
            commonCallback.bind(null, resolve, reject));
    });
}

function stgListByResourceGroupAsync(storageAccountOperations, resourceGroupName, options) {
    return new Promise((resolve, reject) => {
        storageAccountOperations.listByResourceGroup(resourceGroupName, options, commonCallback.bind(null, resolve, reject));
    });
}

function stgGetPropertiesAsync(storageAccountOperations, resourceGroupName, accountName, options) {
    return new Promise((resolve, reject) => {
        storageAccountOperations.getProperties(resourceGroupName, accountName, options,
            commonCallback.bind(null, resolve, reject));
    });
}

function stgEnsureContainerAsync(blobServiceOperations, containerName, options) {
    return new Promise((resolve, reject) => {
        blobServiceOperations.createContainerIfNotExists(containerName, options,
            commonCallback.bind(null, resolve, reject));
    });
}

function stgGetBlobPropertiesAsync(blobServiceOperations, containerName, blobName) {
    return new Promise((resolve, reject) => {
        blobServiceOperations.getBlobProperties(containerName, blobName,
            commonCallback.bind(null, resolve, reject));
    });
}

function dnsCheckNameAvailabilityAsync(networkClient, name, location) {
    return new Promise((resolve, reject) => {
        networkClient.checkDnsNameAvailability(location, { domainNameLabel: name }, commonCallback.bind(null, resolve, reject));
    });
}

function stgEnsureAsync(storageAccountOperations, resourceGroupName, accountName, parameters, options) {
    return stgCheckNameAvailabilityAsync(storageAccountOperations, accountName, options).then(result => {
        if (result.nameAvailable) {
            return stgCreateAsync(storageAccountOperations, resourceGroupName, accountName, parameters, options);
        } else if (result.reason == 'AlreadyExists') {
            return stgListByResourceGroupAsync(storageAccountOperations, resourceGroupName, options).then(accounts => {
                for (let account of accounts) {
                    if (account.name === accountName) {
                        if (account.kind !== parameters.kind) {
                            throw new exceptions.AzMigrationException(
                                `Storage account '${accountName}' already exists in resource group '${resourceGroupName}' but the kind '${account.kind}' is incompatible`);
                        } else if (account.location !== parameters.location) {
                            throw new exceptions.AzMigrationException(
                                `Storage account '${accountName}' already exists in resource group '${resourceGroupName}' but the location '${account.location}' is different`);
                        }

                        return account;
                    }
                }

                throw new exceptions.AzMigrationException(result.message);
            });
        }

        throw new exceptions.AzMigrationException(result.message);
    });
}

function listAsync(operations, options) {
    return new Promise((resolve, reject) => {
        operations.list(options, commonCallback.bind(null, resolve, reject));
    });
}

    
function listAsyncByLocation(operations, location, options) {
	return new Promise((resolve, reject) => {
        operations.list(location, options, commonCallback.bind(null, resolve, reject));
    });
}

function stgListKeysAsync(storageAccountOperations, resourceGroupName, accountName, options) {
    return new Promise((resolve, reject) => {
        storageAccountOperations.listKeys(resourceGroupName, accountName, options, 
        commonCallback.bind(null, resolve, reject));
    });
}


/**
 * @param {Object} operations - Operation object from Azure management client SDK
 * @param {string} resourceGroupName
 * @param {string} resourceName
 * @param {Object} parameters - JSON representation of the resource to be created/updated
 * @param {Object} options
 * @return {Promise<Object>} JSON representation of the created or updated resource
 */
function createOrUpdateAsync(operations, resourceGroupName, name, parameters, options) {
    return new Promise((resolve, reject) => {
        operations.createOrUpdate(resourceGroupName, name, parameters, options,
            commonCallback.bind(null, resolve, reject));
    });
}

/**
 * @param {Object} operations - Operation object from Azure management client SDK
 * @param {string} resourceGroupName
 * @param {string} resourceName
 * @param {Object} options
 * @return {Promise<Object>} JSON representation of the created or updated resource
 */
function getAsync(operations, resourceGroupName, resourceName, options) {
    return new Promise((resolve, reject) => {
        operations.get(resourceGroupName, resourceName, options, commonCallback.bind(null, resolve, reject));
    });
}

function storageCallback(resolve, reject, error, result, response) {
    if (error) {
        reject(error);
    } else {
        resolve(result);
    }
}

/**
 * Gets a resource with its ID
 * @param {Object} operations - Operation object from Azure management client SDK
 * @param {string} resourceId
 * @param {Object} options
 * @return {Promise<Object>} JSON representation of the created or updated resource
 */
function getAsyncWithId(operations, resourceId, options) {
    return new Promise((resolve, reject) => {
        var resourceInfo = models.ResourceId.parse(resourceId);
        operations.get(resourceInfo.resourceGroup, resourceInfo.resourceName, options, function(err, result){
            if (err){
                reject(err);
            }
            else{
                result.resourceGroupName = resourceInfo.resourceGroup.toLowerCase();
                resolve(result);
            }
        });
    });
}

/**
 * @param {BlobService} blobService - The target blob service object
 * @param {string} sourceUri
 * @param {string} targetContainer
 * @param {string} targetBlob
 * @param {Object} options
 * @return {Promise<BlobResult>} The copied blob information
 */
function blobStartCopyAsync(blobService, sourceUri, targetContainer, targetBlob, options) {
    return new Promise((resolve, reject) => {
        blobService.startCopyBlob(sourceUri, targetContainer, targetBlob, options,
            storageCallback.bind(null, resolve, reject));
    });
}

/**
 * @param {BlobService} blobService
 * @param {string} container
 * @param {string} blobName
 * @param {Object} options
 * @return {Promise<BlobResult>} The blob information
 */
function doesBlobExistAsync(blobService, container, blobName, options) {
    return new Promise((resolve, reject) => {
        blobService.doesBlobExist(container, blobName, options,
            storageCallback.bind(null, resolve, reject));
    });
}

/**
 * @param {BlobService} blobService
 * @param {string} container
 * @param {string} blobName
 * @return {Promise<BlobResult>} The blob information
 */
function blobCreateSnapshotAsync(blobService, container, blobName) {
    return new Promise((resolve, reject) => {
        blobService.createBlobSnapshot(container, blobName,
            storageCallback.bind(null, resolve, reject));
    });
}


/**
 * @param {BlobService} blobService
 * @param {string} container
 * @param {string} blobName
 * @param {Object} options
 * @return {Promise<BlobResult>} The blob information
 */
function blobListPageRangesAsync(blobService, container, blobName) {
    return new Promise((resolve, reject) => {
        blobService.listPageRanges(container, blobName,
            storageCallback.bind(null, resolve, reject));
    });
}

/**
 * @param {BlobService} blobService
 * @param {string} container
 * @param {string} blobName
 * @return {Promise<BlobResult>} The blob information
 */
function blobDeleteSnapshotAsync(blobService, container, blobName, options) {
    return new Promise((resolve, reject) => {
        blobService.deleteBlob(container, blobName, options,
            storageCallback.bind(null, resolve, reject));
    });
}

const ErrorCode = {
    RoleAssignmentExists: 'RoleAssignmentExists',
    ResourceNotFound: 'ResourceNotFound',
    ResourceGroupNotFound: 'ResourceGroupNotFound',
    StorageAccountNotFound: 'StorageAccountNotFound',
    DeploymentNotFound: 'DeploymentNotFound',
}

module.exports = {
    ErrorCode,
    dnsCheckNameAvailabilityAsync,
    rgCheckExistenceAsync,
    rgGetAsync,
    rgCreateOrUpdateAsync,
    rgEnsureAsync,
    stgCheckNameAvailabilityAsync,
    stgCreateAsync,
    stgListByResourceGroupAsync,
    stgGetPropertiesAsync,
    stgEnsureContainerAsync,
    stgGetBlobPropertiesAsync,
    stgEnsureAsync,
    dnsCheckNameAvailabilityAsync,
    listAsync,
    listAsyncByLocation,
    stgListKeysAsync,
    createOrUpdateAsync,
    getAsync,
    getAsyncWithId,
    blobStartCopyAsync,
    doesBlobExistAsync,
    blobCreateSnapshotAsync,
    blobListPageRangesAsync,
    blobDeleteSnapshotAsync
};
