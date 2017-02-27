'use strict';

const restAzure = require('ms-rest-azure'),
    exceptions = require('./exceptions');

/**
 * @param {Command} options
 * @param {string} optionName
 * @return {string} Option value
 */
function ensureOption(options, optionName) {
    const value = options[optionName];
    if (!value) {
        throw new exceptions.MissingRequiredOptionException(optionName);
    }

    return value;
}

/**
 * @param {string} strEnv
 * @return {AzureEnvironment}
 */
function toAzureEnvironment(strEnv) {
    switch (strEnv.toLowerCase()) {
        case 'azurecloud':
            return restAzure.AzureEnvironment.Azure;
        case 'azurechinacloud':
            return restAzure.AzureEnvironment.AzureChina;
        case 'azuregermancloud':
            return restAzure.AzureEnvironment.AzureGermanCloud;
        default:
            return null;
    }
}

/**
 * @param {Object} obj - The object to be copied
 * @return {Object} The deep copied object
 */
function deepCopy(obj) {
    return obj ? JSON.parse(JSON.stringify(obj)) : obj;
}

module.exports = {
    ensureOption,
    toAzureEnvironment,
    deepCopy
};