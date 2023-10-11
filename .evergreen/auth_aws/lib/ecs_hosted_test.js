/**
 * Verify the AWS IAM ECS hosted auth works
 */

(function() {
"use strict";

// This varies based on hosting ECS task as the account id and role name can vary
const AWS_ACCOUNT_ARN = "arn:aws:sts::557821124784:assumed-role/ecsTaskExecutionRole/*";

const external = Mongo().getDB("$external");
const admin = Mongo().getDB("admin");

console.log('test1')
admin.runCommand({createUser: "admin", pwd: "pwd", roles: ['root']});
console.log('test2')
admin.auth("admin", "pwd");
console.log('test3')
external.runCommand({createUser: AWS_ACCOUNT_ARN, roles:[{role: 'read', db: "aws"}]});

// Try the auth function
console.log('test4')
const testConn = new Mongo();
console.log('test5')
const testExternal = testConn.getDB('$external');
console.log('test6')
assert(testExternal.auth({mechanism: 'MONGODB-AWS'}));
console.log('test7')
}());
