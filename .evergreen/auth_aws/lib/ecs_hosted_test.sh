#!/bin/bash
# A shell script to run in an ECS hosted task
set -ex

# The environment variable is always set during interactive logins
# But for non-interactive logs, ~/.bashrc does not appear to be read on Ubuntu but it works on Fedora
[[ -z "${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI}" ]] && export $(strings /proc/1/environ | grep AWS_CONTAINER_CREDENTIALS_RELATIVE_URI)

env

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
apt-get update
apt-get install -y unzip
unzip awscliv2.zip
./aws/install

aws sts get-caller-identity
#aws sts assume-role --role-arn "arn:aws:sts::557821124784:assumed-role/ecsTaskExecutionRole" --role-session-name "test"


mkdir -p /data/db || true

/root/mongod --fork --logpath server.log --setParameter authenticationMechanisms="MONGODB-AWS,SCRAM-SHA-256"
sleep 1
/root/mongosh --verbose ecs_hosted_test.js
bash /root/src/.evergreen/run-mongodb-aws-ecs-test.sh "mongodb://localhost/aws?authMechanism=MONGODB-AWS"