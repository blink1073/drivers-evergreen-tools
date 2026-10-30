#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -f ./secrets-export.sh ]; then
  echo "Sourcing secrets"
  source ./secrets-export.sh
fi
if [ -z "${EKS_CLUSTER_NAME:-}" ]; then
    . ./../../secrets_handling/setup-secrets.sh drivers/eks
fi

# Tagging intentionally omitted (DRIVERS-3712 red: untagged baseline).
# The verify block below is expected to FAIL with "lacks mongodb-owner/mongodb-env".

eksctl create cluster --name $EKS_CLUSTER_NAME --zones "${EKS_REGION}a,${EKS_REGION}b"
kubectl config set-context --current
eksctl utils associate-iam-oidc-provider --cluster $EKS_CLUSTER_NAME --approve
eksctl create iamserviceaccount \
    --name $EKS_SERVICE_ACCOUNT_NAME \
    --cluster $EKS_CLUSTER_NAME \
    --role-name $EKS_IAM_ROLE_NAME \
    --attach-policy-arn $EKS_POLICY_ARN \
    --approve \
    --override-existing-serviceaccounts

# Verify the cluster's tags when requested (DRIVERS-3712).
if [ -n "${VERIFY_MONGODB_TAGS:-}" ]; then
  . "$DRIVERS_TOOLS"/.evergreen/verify-tags.sh
  verify_cloud_tags "EKS cluster ${EKS_CLUSTER_NAME}" \
    "$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --region "${EKS_REGION}" --query "cluster.tags" --output json)"
fi
