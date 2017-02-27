'use strict';

const armResource = require('azure-arm-resource'),
    ComputeManagementClient = require('azure-arm-compute'),
    StorageManagementClient = require('azure-arm-storage'),
    NetworkManagementClient = require('azure-arm-network'),
    ResourceType = require('./ResourceType');

class AzureManagementClients {
    /**
     * @constructor
     * @param {ServiceClientCredentials} credentials
     * @param {string} subscriptionId
     * @param {string} baseUri
     */
    constructor(credentials, subscriptionId, baseUri) {
        this.resourceClient = new armResource.ResourceManagementClient(credentials, subscriptionId, baseUri);
        this.computeClient = new ComputeManagementClient(credentials, subscriptionId, baseUri);
        this.storageClient = new StorageManagementClient(credentials, subscriptionId, baseUri);
        this.networkClient = new NetworkManagementClient(credentials, subscriptionId, baseUri);
        this[ResourceType.AvailabilitySets] = this.computeClient.availabilitySets;
        this[ResourceType.VirtualMachines] = this.computeClient.virtualMachines;
        this[ResourceType.StorageAccounts] = this.storageClient.storageAccounts;
        this[ResourceType.LoadBalancers] = this.networkClient.loadBalancers;
        this[ResourceType.NetworkInterfaces] = this.networkClient.networkInterfaces;
        this[ResourceType.NetworkSecurityGroups] = this.networkClient.networkSecurityGroups;
        this[ResourceType.PublicIpAddresses] = this.networkClient.publicIPAddresses;
        this[ResourceType.VirtualNetworks] = this.networkClient.virtualNetworks;
    }
}

module.exports = AzureManagementClients;