'use strict';

const restAzure = require('ms-rest-azure'),
    args = require('./args'),
    exceptions = require('./exceptions');

/**
 * @param {MigrationOptions} options
 * @param {Object} argNames
 * @return {number} The log in method
 */
function determine(options, argNames) {
    let spn = 0;
    if (options[argNames.clientId]) {
        spn++;
    }
    if (options[argNames.secret]) {
        spn++;
    }
    if (options[argNames.domain]) {
        spn++;
    }
    if (spn == 3) {
        return LoginMethod.ServicePrinciple;
    }

    let user = 0;
    if (options[argNames.username]) {
        user++;
    }
    if (options[argNames.password]) {
        user++;
    }
    if (user == 2) {
        return LoginMethod.UsernameAndPassword;
    }

    if (spn > 0) {
        throw new exceptions.AzMigrationException(
            `all '--${argNames.clientId}', '--${argNames.secret}', and '--${argNames.domain}' must be specified for Service Principle login`);
    }
    if (user > 0) {
        throw new exceptions.AzMigrationException(
            `both '--${argNames.username}' and '--${argNames.password}' must be specified for Service Principle login`);
    }

    return LoginMethod.Interactive;
}

const LoginMethod = {
    Interactive: 0,
    UsernameAndPassword: 1,
    ServicePrinciple: 2
}

/**
 * @param {AzureEnvironment} env
 * @param {MigrationOptions} options
 * @param {Object} argNames
 * @return {Promise<ServiceClientCredentials>}
 */
function loginAsync(env, options, argNames) {
    let method = determine(options, argNames);
    switch (method)
    {
        case LoginMethod.ServicePrinciple:
            return new Promise((resolve, reject) => {
                let domain = options[argNames.domain];
                restAzure.loginWithServicePrincipalSecret(
                    options[argNames.clientId],
                    options[argNames.secret],
                    domain,
                    { environment: env, domain: domain },
                    (err, credentials) => {
                        if (err) {
                            reject(err);
                        } else {
                            resolve(credentials);
                        }
                    });
            });
            break;
        case LoginMethod.UsernameAndPassword:
            return new Promise((resolve, reject) => {
                restAzure.loginWithUsernamePassword(
                    options[argNames.username],
                    options[argNames.password],
                    { environment: env },
                    (err, credentials) => {
                        if (err) {
                            reject(err);
                        } else {
                            resolve(credentials);
                        }
                    });
            });
            break;
        case LoginMethod.Interactive:
        default:
            return new Promise((resolve, reject) => {
                restAzure.interactiveLogin({ environment: env }, (err, credentials) => {
                    if (err) {
                        reject(err);
                    } else {
                        resolve(credentials);
                    }
                });
            });
    }
}

/**
 * @param {AzureEnvironment} env
 * @param {MigrationOptions} options
 * @return {Promise<ApplicationTokenCredentials>}
 */
function loginSourceAsync(env, options) {
    return loginAsync(env, options, args.src);
}

/**
 * @param {AzureEnvironment} env
 * @param {MigrationOptions} options
 * @return {Promise<ApplicationTokenCredentials>}
 */
function loginDestinationAsync(env, options) {
    return loginAsync(env, options, args.dest);
}

module.exports = {
    loginSourceAsync,
    loginDestinationAsync
};