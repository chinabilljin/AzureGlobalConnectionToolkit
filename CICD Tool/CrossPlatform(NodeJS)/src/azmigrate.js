#!/usr/bin/env node

'use strict';

const program = require('commander'),
    os = require('os'),
    utils = require('./libs/utils'),
    exceptions = require('./libs/exceptions'),
    args = require('./libs/args'),
    login = require('./libs/login'),
    models = require('./libs/models'),
    vm = require('./libs/vm'),
    telemetry = require('./libs/telemetry');

program.version('0.0.1')
    .option(`-e, --${args.src.environment} <environment>`, 'source Azure environment (e.g. AzureCloud)', 'AzureCloud')
    .option(`-E, --${args.dest.environment} <environment>`, '<required> destination Azure environment (e.g. AzureChinaCloud)')
    .option(`-i, --${args.src.clientId} <clientId>`, '[required for service principle login] source AAD application client ID, aka. SPN')
    .option(`-c, --${args.src.secret} <secret>`, '[required for service principle login] source AAD application secret')
    .option(`-d, --${args.src.domain} <domain>`, '[required for service principle login] source domain or tenant id containing the AAD application')
    .option(`-I, --${args.dest.clientId} <clientId>`, '[required for service principle login] destination AAD application client ID, aka. SPN')
    .option(`-C, --${args.dest.secret} <secret>`, '[required for service principle login] destination AAD application secret')
    .option(`-D, --${args.dest.domain} <domain>`, '[required for service principle login] destination domain or tenant id containing the AAD application')
    .option(`-u, --${args.src.username} <username>`, '[required for username & password login] source AAD account user name')
    .option(`-p, --${args.src.password} <password>`, '[required for username & password login] source AAD account password')
    .option(`-U, --${args.dest.username} <username>`, '[required for username & password login] destination AAD account user name')
    .option(`-P, --${args.dest.password} <password>`, '[required for username & password login] destination AAD account password')
    .command('help')
    .description('output usage information')
    .action(() => {
        program.help();
    });

program.command('vm')
    .description('migrate virtual machines')
    .option(`-s, --${args.src.subscriptionId} <subcriptionId>`, '<required> source subscription ID')
    .option(`-S, --${args.dest.subscriptionId} <subcriptionId>`, '<required> destination subscription ID')
    .option(`-g, --${args.src.resourceGroup} <resourceGroupName>`, '<required> source resource group name')
    //.option(`-G, --${args.dest.resourceGroup} <resourceGroupName>`, 'destination resource group name (default: same as source)')
    .option(`-n, --${args.src.resourceName} <vmName>`, '<required> source virtual machine name')
    //.option(`-N, --${args.dest.resourceName} <vmName>`, 'destination virtual machine name (default: same as source)')
    .option(`-L, --${args.dest.location} <location>`, 'destination location (default: same as resource group if exists)')
    .action((options) => {

        //version check node js version to support ES6 
        let version = process.version;
        let ver = version.split('.');
        let ver0num = parseInt(ver[0].replace('v',''), 10);
        let ver1num = parseInt(ver[1],10);
        let ver2num = parseInt(ver[2],10);
        const isTelemetryEnabled = true;

        if (ver0num === 6) {
            if (ver1num < 5 ){
                throw new exceptions.ValidationFailureException('You need node.js v6.5.0 or higher to run this code. Your version: ' +  version );
            }
        } else if (ver0num < 6){
            throw new exceptions.ValidationFailureException('You need node.js v6.5.0 or higher to run this code. Your version: ' +  version );
        }

        const srcEnv = utils.toAzureEnvironment(program.srcEnv);
        if (!srcEnv) {
            throw new exceptions.InvalidOptionValueException(args.src.environment, program.srcEnv)
        }

        const strDestEnv = utils.ensureOption(program, args.dest.environment);
        const destEnv = utils.toAzureEnvironment(strDestEnv);
        if (!destEnv) {
            throw new exceptions.InvalidOptionValueException(args.dest.environment, strDestEnv)
        }

        if (srcEnv === destEnv) {
            throw new exceptions.AzMigrationException('destination environment cannot be same as source environment');
        }

        const srcSubId = utils.ensureOption(options, args.src.subscriptionId);
        const destSubId = utils.ensureOption(options, args.dest.subscriptionId);
        const srcGroup = utils.ensureOption(options, args.src.resourceGroup);
        const srcName = utils.ensureOption(options, args.src.resourceName);
        const migrationOptions = new models.MigrationOptions(
            new models.MigrationSite(srcEnv, srcSubId),
            new models.MigrationSite(destEnv, destSubId),
            srcGroup,
            srcName,
            options.destLocation
        );
        const nic= os.networkInterfaces()
        const macAddress = Object.keys(nic).map(key=>nic[key].map(x=>x.mac)).reduce((c,x)=>c.concat(x),[])
            .reduce((c,x)=>{if(x!=='00:00:00:00:00:00' && c.indexOf(x) === -1) c.push(x);return c;},[])[0];
        telemetry.init(isTelemetryEnabled);
        login.loginSourceAsync(srcEnv, program).then(srcCredentials => {
            migrationOptions.srcSite.credentials = srcCredentials;
            return login.loginDestinationAsync(destEnv, program);
        }).then(destCredentials => {
            migrationOptions.destSite.credentials = destCredentials;
            const eventObject = {
                SourceEnvironment: srcEnv.name,
                SourceSubscriptionId: srcSubId,
                DestinationSubscriptionId: destSubId,
                DestinationEnvironment: destEnv.name,
                SourceResourceGroupName: srcGroup,
                SourceVmName: srcName,
                NodejsVersion: version,
                MacAddress: macAddress,
                Platform: os.platform(),
                OsType: os.type()
            };
            telemetry.trackEvent("start migration", eventObject);
            return vm.migrateAsync(migrationOptions);
        }).then(result => {
            console.log(result);
            telemetry.trackEvent('Migration finished', { MigrationResult: result });
            console.log('All done!');
            process.exit();
        }).catch(ex => {
            telemetry.trackEvent('Migration failed', { MigrationException: ex });
            telemetry.trackException(ex);
            console.log('\n  ' + ex);
            process.exit(1);
        });
    });

try {
    program.parse(process.argv);
} catch (ex) {
    telemetry.trackEvent('Migration failed', { MigrationException: ex });
    telemetry.trackException(ex);
    console.log('\n  ' + ex);
    process.exit(1);
}

if (program.args.length === 0) {
    program.help();
}