'use strict';

class MigrationSite {
    /**
     * @constructor
     * @param {AzureEnvironment} environment
     * @param {string} subscriptionId
     */
    constructor(environment, subscriptionId) {
        this.environment = environment;
        this.subscriptionId = subscriptionId;
        /** @type {ServiceClientCredentials} */
        this.credentials = null;
    }
}

class MigrationOptions {
    /**
     * @constructor
     * @param {MigrationSite} srcSite
     * @param {MigrationSite} destSite
     * @param {string} srcResourceGroup - Source resouce group name
     * @param {string} srcResourceName - Source resource name
     * @param {string} destLocation - [optional] Destination location
     */
    constructor(srcSite, destSite, srcResourceGroup, srcResourceName, destLocation) {
        this.srcSite = srcSite;
        this.destSite = destSite;
        this.srcResourceGroup = srcResourceGroup;
        this.srcResourceName = srcResourceName;
        this.destLocation = destLocation;
    }
}

const separator = '/';
const subIdIndex = 1;
const resourceGroupIndex = 3;
const providerIndex = 5;
const resourceTypeIndex = 6;
const resourceNameIndex = 7;
const subResourceTypeIndex = 8;
const subResourceNameIndex = 9;
const subSubResourceTypeIndex = 10;
const subSubResourceNameIndex = 11;
const resourceGroupPartsCount = 4;
const resourcePartsCount = 8;
const subResourcePartsCount = 10;
const subSubResourcePartsCount = 12;
const ResourceIdType = {
    Invalid: 0,
    ResourceGroup: 1,
    Resource: 2,
    SubResource: 3,
    SubSubResource: 4
};

class ResourceId {
    /**
     * @constructor
     * @param {number} type - Resource ID type
     */
    constructor(type) {
        /** @type {number} */
        this.type = type;
    }

    /**
     * @param {string} resourceId - Azure resource ID
     */
    static parse(resourceId) {
        let offset = 0;
        if (resourceId.charAt(0) === separator) {
            offset = 1;
        }

        const result = new ResourceId(ResourceIdType.Invalid);
        const parts = resourceId.toLowerCase().split(separator);
        if (parts.length < resourceGroupPartsCount + offset) {
            return result;
        }
        result.subscriptionId = parts[subIdIndex + offset];
        result.resourceGroup = parts[resourceGroupIndex + offset];
        if (parts.length < resourcePartsCount + offset) {
            result.type = ResourceIdType.ResourceGroup;
            return result;
        }
        result.provider = parts[providerIndex + offset];
        result.resourceType = parts[resourceTypeIndex + offset];
        result.resourceName = parts[resourceNameIndex + offset];
        if (parts.length < subResourcePartsCount + offset) {
            result.type = ResourceIdType.Resource;
            return result;
        }
        result.subResourceType = parts[subResourceTypeIndex + offset];
        result.subResourceName = parts[subResourceNameIndex + offset];
        if (parts.length < subSubResourcePartsCount + offset) {
            result.type = ResourceIdType.SubResource;
            return result;
        }
        result.subSubResourceType = parts[subSubResourceTypeIndex + offset];
        result.subSubResourceName = parts[subSubResourceNameIndex + offset];
        result.type = ResourceIdType.SubSubResource;
        return result;
    }

    toString(type) {
        type = type || this.type;
        if (type === ResourceIdType.Invalid) return null;
        let result = `/subscriptions/${this.subscriptionId}/resourcegroups/${this.resourceGroup}`;
        if (type === ResourceIdType.ResourceGroup) return result;
        result += `/providers/${this.provider}/${this.resourceType}/${this.resourceName}`;
        if (type === ResourceIdType.Resource) return result;
        result += `/${this.subResourceType}/${this.subResourceName}`;
        if (type === ResourceIdType.SubResource) return result;
        result += `/${this.subSubResourceType}/${this.subSubResourceName}`;
        return result;
   }
}

class ResourceInfo {
    /**
     * @constructor
     * @param {ResourceId} resourceId - The resource ID
     * @param {Object} resource - The object returned from 'get' Azure Rest API for a resource
     */
    constructor(resourceId, resource) {
        this.resourceId = resourceId;
        this.resource = resource;
    }

    /**
     * @param {Object} resource - The object returned from 'get' Azure Rest API for a resource
     * @return {ResourceInfo} A new instance
     */
    static fromResource(resource) {
        return new ResourceInfo(ResourceId.parse(resource.id), resource);
    }
}

class ResourceMigrationInfo {
    /**
     * @constructor
     * @param {ResourceInfo} source - Source resource info
     * @param {ResourceInfo} destination - Destination resource info
     */
    constructor(source, destination) {
        this.source = source;
        this.destination = destination;
    }

    /**
     * @param {ResourceInfo} source - Source resource info
     * @param {string} destSubId
     * @param {string} destResourceGroup
     * @param {string} destResourceName
     * @return {ResourceMigrationInfo}
     */
    static fromSource(source, destSubId, destResourceGroup, destResourceName) {
        // Make a new instance of ResourceId so we don't pollute the source ResourceId object
        const destId = ResourceId.parse(source.resource.id);
        destId.subscriptionId = destSubId;
        if (destResourceGroup)
            destId.resourceGroup = destResourceGroup;
        if (destResourceName)
            destId.resourceName = destResourceName;

        return new ResourceMigrationInfo(source, new ResourceInfo(destId, null));
    }

    /**
     * @return {boolean} Whether this resource needs to be deployed to destination
     */
    get needsDeployment() { return this.destination && this.destination.resource; }
}

class ResourceDependency {
    /**
     * @constructor
     * @param {Object} root The root resource
     * @param {Array<Object>} dependencies An array of dependencies
     */
    constructor(root) {
        this.root = root;
        this.dependencies = [];
    }

    pushToDependencies(dep) {
        if (dep){
            this.dependencies.push(dep);
        }
    }
}

module.exports = {
    MigrationSite,
    MigrationOptions,
    ResourceId,
    ResourceIdType,
    ResourceInfo,
    ResourceMigrationInfo,
    ResourceDependency,
};