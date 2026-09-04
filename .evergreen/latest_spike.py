#!/usr/bin/env python3
"""
Spike: prove out downloading "latest" MongoDB server binaries from the private
S3 bucket via drivers-test-secrets-role -> SERVER_ARTIFACTS_ROLE_ARN.

Local usage (SSO -> drivers-test-secrets-role -> SERVER_ARTIFACTS_ROLE_ARN):
    AWS_PROFILE=drivers-test python3 latest_spike.py

Evergreen usage (drivers-test-secrets-role -> SERVER_ARTIFACTS_ROLE_ARN),
after an `ec2.assume_role` step for drivers-test-secrets-role has exported
AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_SESSION_TOKEN:
    python3 latest_spike.py

The role ARN, bucket, and top-level prefix all come from the
drivers/devprod-release-infrastructure secret, not hardcoded here.

crypt_shared is not yet available for every branch and is skipped for now.
"""

import argparse
import json
import os
import uuid

import boto3

DRIVERS_TEST_SECRETS_ROLE_ARN = (
    "arn:aws:iam::857654397073:role/drivers-test-secrets-role"
)
SERVER_ARTIFACTS_SECRET_VAULT = "drivers/devprod-release-infrastructure"
DEFAULT_BRANCH = "mongodb-mongo-v8.0-staging"
DEFAULT_FILENAME = "mongodb-linux-x86_64-enterprise-ubuntu2204.tgz"


def drivers_test_secrets_creds(region, profile):
    """Credentials for drivers-test-secrets-role.

    In Evergreen, `ec2.assume_role` already exports these as ambient env vars, so
    no extra hop is needed. Locally, assume the role from an SSO profile.
    """
    if "AWS_ACCESS_KEY_ID" in os.environ and not profile:
        return None
    profile = profile or os.environ.get("AWS_PROFILE")
    session = boto3.Session(profile_name=profile)
    sts = session.client("sts", region_name=region)
    resp = sts.assume_role(
        RoleArn=DRIVERS_TEST_SECRETS_ROLE_ARN,
        RoleSessionName=str(uuid.uuid4()),
    )
    return resp["Credentials"]


def client(service, region, creds):
    kwargs = dict(region_name=region)
    if creds:
        kwargs.update(
            aws_access_key_id=creds["AccessKeyId"],
            aws_secret_access_key=creds["SecretAccessKey"],
            aws_session_token=creds["SessionToken"],
        )
    return boto3.client(service, **kwargs)


def get_server_artifacts_config(region, creds):
    secretsmanager = client("secretsmanager", region, creds)
    secret = json.loads(
        secretsmanager.get_secret_value(SecretId=SERVER_ARTIFACTS_SECRET_VAULT)[
            "SecretString"
        ]
    )
    return {
        "role_arn": secret["SERVER_ARTIFACTS_ROLE_ARN"],
        "bucket": secret["SERVER_ARTIFACTS_BUCKET"],
        "prefix": secret["SERVER_ARTIFACTS_PREFIX"],
    }


def assume_server_artifacts_role(region, creds, role_arn):
    sts = client("sts", region, creds)
    resp = sts.assume_role(RoleArn=role_arn, RoleSessionName=str(uuid.uuid4()))
    return resp["Credentials"]


def download(region, creds, bucket, key, dest):
    s3 = client("s3", region, creds)
    s3.download_file(bucket, key, dest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", help="local AWS profile (defaults to AWS_PROFILE)")
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--branch", default=DEFAULT_BRANCH, help="S3 branch folder")
    parser.add_argument(
        "--filename", default=DEFAULT_FILENAME, help="S3 object filename"
    )
    parser.add_argument("--dest", default="latest-spike-download.tgz")
    args = parser.parse_args()

    secrets_creds = drivers_test_secrets_creds(args.region, args.profile)
    print(
        "drivers-test-secrets-role creds:",
        "assumed via SSO" if secrets_creds else "ambient (Evergreen)",
    )

    config = get_server_artifacts_config(args.region, secrets_creds)
    print(f"Resolved server artifacts config from secret: {config}")

    artifacts_creds = assume_server_artifacts_role(
        args.region, secrets_creds, config["role_arn"]
    )
    print(f"Assumed {config['role_arn']}")

    key = f"{config['prefix']}/{args.branch}/{args.filename}"
    download(args.region, artifacts_creds, config["bucket"], key, args.dest)
    print(f"Downloaded s3://{config['bucket']}/{key} -> {args.dest}")


if __name__ == "__main__":
    main()
