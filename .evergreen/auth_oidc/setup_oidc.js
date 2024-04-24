/**
 * Set up OIDC auth roles.
 */
(function() {
"use strict";

const adminUser = process.env['AZUREOIDC_USERNAME'] || 'bob';
console.log("Setting up Admin User", adminUser);
const conn = Mongo();
const admin = conn.getDB("admin");
assert(admin.auth(adminUser, "pwd123"));

console.log("Setting up User");
conn.getDB('$external').runCommand({
    createUser: 'test1/system:serviceaccount:drivers-python:default',
    roles: [{role: 'readWriteAnyDatabase', db: 'admin'}]
});

}());
