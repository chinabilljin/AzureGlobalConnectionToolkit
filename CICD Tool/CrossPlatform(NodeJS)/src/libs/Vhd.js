'use strict';

const Azure = require('azure-storage'),
    exceptions = require('./exceptions'),
    BlobUtilities = Azure.BlobUtilities,
    Ex = exceptions.ValidationFailureException,
    Multiprogress = require('multi-progress'),
    azureEx = require('./azureExtensions');


class CopyStates {
    /**
     * @constructor
     * @param {BlobService} destBlobService
     * @param {int} sourceBillableSize
     * @param {string} destContainerName
     * @param {string} destBlobName
     */
    constructor(sourceBillableSize, destBlobService, destContainerName, destBlobName, callback) {
        this.sourceBillableSize = sourceBillableSize;
        this.destBlobService = destBlobService;
        this.destContainerName = destContainerName;
        this.destBlobName = destBlobName;
        this.isComplete = false;
        this.callback = callback;
    }

    /**
     * @return {Promise<progress>}
     */
    updateAsync() {
        var blobService = this.destBlobService;
        var containerName = this.destContainerName;
        var blobName = this.destBlobName;
        var callback = this.callback;
        if (this.isComplete)
            return;
        return azureEx.stgGetBlobPropertiesAsync(blobService, containerName, blobName).then((result) => {
            if (result.copy.status == "success") {
                this.currentBytes = result.copy.bytesCopied;
                this.totalBytes = result.copy.totalBytes;
                this.isComplete = true;
                return callback();
            }
            else if (result.copy.status == "pending") {
                this.currentBytes = (result.copy.bytesCopied>this.sourceBillableSize)?result.copy.sourceBillableSize:result.copy.bytesCopied;
                this.totalBytes = result.copy.totalBytes;
            }
            else {
                callback();
                this.isComplete = true;
                throw new Ex(`Can't parse getBlobProperties's response when Copying VHDs`);
            }
        });
    }
}

class Vhd {
    /**
     * @constructor
     * @param {string} resourceGroupName
     * @param {string} storageAccountName
     * @param {string} container
     * @param {string} blob
     * @param {string} uri
     */
    constructor(resourceGroupName, storageAccountName, container, blob, uri) {
        this.resourceGroupName = resourceGroupName;
        this.storageAccount = storageAccountName;
        this.container = container;
        this.blob = blob;
        this.uri = uri;
    }



    /**
     *  Start to copy
     * @param {StorageAccounts} srcStorageOperation 
     * @param {StorageAccounts} dstStorageOperation
     * @return {Promise<CopyStates>}
     */
    copyAsync(srcStorageOperation, dstStorageOperation) {
        var sourceBlobService;
        var sourceContainerName = this.container;
        var sourceBlobName = this.blob;
        var sourceGroupName = this.resourceGroupName;
        var sourceAccountName = this.storageAccount;
        var sourceSnapshotId = '';
        var sourceBillableSize = 0;

        var destBlobService;
        var destContainerName = sourceContainerName;
        var destBlobName = sourceBlobName;
        var destGroupName = sourceGroupName;
        var destAccountName =sourceAccountName;

        var vhd = this;

        let promises = [];
        promises.push(getBlobServiceAsync(srcStorageOperation, sourceGroupName, sourceAccountName));
        promises.push(getBlobServiceAsync(dstStorageOperation, destGroupName, destAccountName));
        return Promise.all(promises).then(([sourceBlobServiceResult, destBlobServiceResult])=>{
            sourceBlobService = sourceBlobServiceResult;
            destBlobService = destBlobServiceResult;
        }).then(()=>{
            return azureEx.stgEnsureContainerAsync(destBlobService, destContainerName, {});
        }).then(() => {
            return findAvailableBlobNameAsync(destBlobService, destContainerName, destBlobName);
        }).then((AvailableBlobName) => {
            destBlobName = AvailableBlobName;
            return azureEx.blobListPageRangesAsync(sourceBlobService, sourceContainerName, sourceBlobName);
        }).then((ranges) => {
            for (let range of ranges){
                sourceBillableSize += (12 + range.end - range.start);
            }
            //An approximate value. For detail please refer to https://blogs.msdn.microsoft.com/windowsazurestorage/2010/07/08/understanding-windows-azure-storage-billing-bandwidth-transactions-and-capacity/
            return azureEx.blobCreateSnapshotAsync(sourceBlobService, sourceContainerName, sourceBlobName);
        }).then((snapshotId) => {
            sourceSnapshotId = snapshotId;
            var startDate = new Date();
            var expiryDate = new Date();
            expiryDate.setDate(startDate.getDate() + 1);
            var sharedAccessPolicy = {
                AccessPolicy: {
                    Permissions: BlobUtilities.SharedAccessPermissions.READ,
                    Expiry: expiryDate
                },
            };
            var sasToken = sourceBlobService.generateSharedAccessSignature(sourceContainerName, sourceBlobName, sharedAccessPolicy);
            sasToken = (sasToken === null ? '' : sasToken);
            var usePrimaryEndpoint = true;
            var sourceUri = sourceBlobService.getUrl(sourceContainerName, sourceBlobName, sasToken, usePrimaryEndpoint, sourceSnapshotId);
            vhd.sourceUri = vhd.uri;
            vhd.uri = destBlobService.getUrl(sourceContainerName, sourceBlobName);
            var options = { accessCondition: {} };
            return azureEx.blobStartCopyAsync(destBlobService, sourceUri, destContainerName, destBlobName, options);
        }).then(() => {
            var isSnapshotDeleted = false;
            var finishCallBack = function () {
                if (isSnapshotDeleted) return;
                var options = {
                    //deleteSnapshots: BlobUtilities.SnapshotDeleteOptions.SNAPSHOTS_ONLY // Delete all snapshots
                    snapshotId: sourceSnapshotId
                };
                return azureEx.blobDeleteSnapshotAsync(sourceBlobService, sourceContainerName, sourceBlobName, options).then((result) => {
                    //console.log("Sucessfully deleted snapshot: %s(%s)", sourceBlobName, sourceSnapshotId);
                    //return azureEx.blobDeleteSnapshotAsync(destBlobService, destContainerName, destBlobName, {});   // TestOnly: Delete dest blob after copying
                }).then((result) => {
                    isSnapshotDeleted = true;
                    return;
                });
            }
            var progress = new CopyStates(sourceBillableSize, destBlobService, destContainerName, destBlobName, finishCallBack.bind(this));
            return progress;
        });
    }
}

class OsDisk extends Vhd {
    /**
     * @constructor
     * @param {string} resourceGroupName
     * @param {string} storageAccountName
     * @param {string} container
     * @param {string} blob
     * @param {string} uri
     * @param {string} type
     */
    constructor(resourceGroupName, storageAccountName, container, blob, uri, type) {
        super(resourceGroupName, storageAccountName, container, blob, uri);
        this.type = type;
    }
}

class DataDisk extends Vhd {
    /**
     * @constructor
     * @param {string} resourceGroupName
     * @param {string} storageAccountName
     * @param {string} containe
     * @param {string} blob
     * @param {string} uri
     * @param {number} lun
     */
    constructor(resourceGroupName, storageAccountName, container, blob, uri, lun) {
        super(resourceGroupName, storageAccountName, container, blob, uri);
        this.lun = lun;
    }
}

/**
 * Finds an available name for a blob in a given container
 * @param {BlobService} blobService
 * @param {string} container
 * @param {string} preferredBlobName
 * @return {Promise<string>} The available blob name
 */
function findAvailableBlobNameAsync(blobService, container, preferredBlobName) {
    let name = preferredBlobName,
        ext = '';
    const dotIndex = preferredBlobName.lastIndexOf('.');
    if (dotIndex >= 0) {
        name = preferredBlobName.substring(0, dotIndex);
        ext = preferredBlobName.substring(dotIndex)
    }

    const tryNameAsync = blobName => {
        return azureEx.doesBlobExistAsync(blobService, container, blobName).then(result => {
            if (result.exists) {
                return tryNameAsync(name + Math.floor((Math.random() * 10000)) + ext);
            }

            return blobName;
        });
    };

    return tryNameAsync(preferredBlobName);
}

/**
 * Wait VHD copying and show progress bar
 * @param {CopyStates} copyStates
 * @return {Promise<Object>} 
 */
function showProgress(copyStates) {
    const mutiBar = Multiprogress(process.stderr);
    const createBar = mutiBar.newBar.bind(mutiBar);

    var updateCopyStates = function () {
        let promises = [];
        copyStates.forEach((copy) => {
            promises.push(copy.updateAsync());
        });
        return Promise.all(promises);
    }

    var check = function (resolve, reject, interval) {
        return updateCopyStates().then(() => {
            var isAllComplete = true;
            copyStates.forEach((state) => {
                if (!state.bar) {
                    state.bar = createBar(state.destBlobName + '. [:bar] :percent :etas', {
                        complete: '=',
                        incomplete: ' ',
                        width: 20,
                        total: state.sourceBillableSize
                    });
                }
                let currentPercentage = (state.currentBytes /state.sourceBillableSize);
                state.bar.update(currentPercentage.toFixed(2));
                if (!state.isComplete)
                    isAllComplete = false;
            });
            if (isAllComplete) {
                clearInterval(interval);
                resolve();
            }
        },()=>{
            throw new exceptions.AzMigrationException(`Copying VHDs error`);
        }).catch((err) => {
            CopyStates.forEach((copy) => {
                copy.callback();
            });
            clearInterval(interval);
            reject(err);
        });

    };
    return new Promise((resolve, reject) => {
        var interval = setInterval(() => {
            check(resolve, reject, interval);
        }, 1000 * 10);
    });
}

/**
 * Create BlobService
 * @param {StorageAccounts } ARM StorageManagementClient
 * @param {string } groupName
 * @param {string } accountName
 * @return {Promise<BlobService>} 
 */
function getBlobServiceAsync(stgAccountOperations, groupName, accountName) {
    var key, endpoint;
    return azureEx.stgListKeysAsync(stgAccountOperations, groupName, accountName).then((keyList) => {
        key = keyList.keys[0].value;
        return azureEx.stgGetPropertiesAsync(stgAccountOperations, groupName, accountName, {});
    }).then((properties) => {
        endpoint = properties.primaryEndpoints.blob;
        return Azure.createBlobService(accountName, key, endpoint);
    });
}




module.exports = {
    OsDisk,
    DataDisk,
    showProgress,
    getBlobServiceAsync
};