'use strict';

class AzMigrationException extends Error {
}

class InvalidOptionValueException extends AzMigrationException {
    /**
     * @constructor
     * @param {string} optionName
     * @param {string} value
     */
    constructor(optionName, value) {
        super(`'${value}' is not a valid value for option '--${optionName}'`);
    }
}

class MissingRequiredOptionException extends AzMigrationException {
    /**
     * @constructor
     * @param {string} optionName
     */
    constructor(optionName) {
        super(`missing required option '--${optionName}'`);
    }
}

class ValidationFailureException extends AzMigrationException {
    /**
     * @constructor
     * @param {string} message
     */
    constructor(message) {
        super(message);
    }
}

module.exports = {
    AzMigrationException,
    InvalidOptionValueException,
    MissingRequiredOptionException,
    ValidationFailureException
};