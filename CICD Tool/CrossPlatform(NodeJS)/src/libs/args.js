'use strict';

function commonArguments(prefix) {
    return {
        environment: prefix + 'Env',
        clientId: prefix + 'ClientId',
        secret: prefix + 'Secret',
        domain: prefix + 'Domain',
        username: prefix + 'Username',
        password: prefix + 'Password',
        subscriptionId: prefix + 'SubId',
        resourceGroup: prefix + 'Group',
        resourceName: prefix + 'Name',
    };
}

let src = commonArguments('src');
let dest = commonArguments('dest');
dest.location = 'destLocation';

module.exports = {
    src,
    dest
};