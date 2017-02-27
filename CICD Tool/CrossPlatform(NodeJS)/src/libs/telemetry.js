'use strict';

const appInsights = require('applicationinsights'),
    uuidV4 = require('uuid/v4');
const INSTRUMENTATION_KEY = "8b19b7ef-ca6b-42a4-9f93-82a3ff99736c";
const GUID = uuidV4();
let client;
let _isEnabled = false;


/**
 * @param {boolean} isEnabled
 */
function init(isEnabled) {
    _isEnabled = isEnabled;
    if (isEnabled) {
        appInsights.setup(INSTRUMENTATION_KEY)
            .setAutoCollectRequests(false)
            .setAutoCollectPerformance(false)
            .setAutoCollectExceptions(false)
            .setAutoCollectDependencies(false);
        appInsights.start();
        client = appInsights.getClient(INSTRUMENTATION_KEY);
        let context = client.context;
        context.tags[context.keys.sessionId] = GUID;
    }
}

/**
 * @param {string} eventName
 * @param {object} event
 */
function trackEvent(eventName, event) {
    if (_isEnabled) {
        if(event === undefined) {
            event = {};
        }
        client.trackEvent(eventName, event);
    }
}

/**
 * @param {Error} exception
 */
function trackException(exception) {
    if (_isEnabled) {
        client.trackException(exception);
    }
}

module.exports = {
    init,
    trackEvent,
    trackException
};
