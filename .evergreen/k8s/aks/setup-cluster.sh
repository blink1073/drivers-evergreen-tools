#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
# ensure-binary.sh is sourced below and reassigns SCRIPT_DIR to its own
# directory; keep this script's directory for the verify module.
AKS_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. $SCRIPT_DIR/../../handle-paths.sh

if [ -f ./secrets-export.sh ]; then
  echo "Sourcing secrets"
  source ./secrets-export.sh
fi
if [ -z "${AZUREKMS_TENANTID:-}" ]; then
    . ./../../secrets_handling/setup-secrets.sh drivers/aks
fi

az logout || true
az login

# Tagging intentionally omitted (DRIVERS-3712 red: untagged baseline)..
# The verify block below is expected to FAIL with "lacks mongodb-owner/mongodb-env".

# Delete the partially created resource group when a provisioning step after
# the group create fails: a leftover partial group blocks re-runs
# (setup-cluster.sh refuses an existing group) and leaks billable resources.
# Disarmed once provisioning succeeds; a verification failure leaves the
# long-lived cluster for manual repair, like the EKS flow.
group_created=0
aks_teardown_group ()
{
  if [ "${group_created}" = 1 ]; then
    echo "Deleting the partially created resource group ${AKS_RESOURCE_GROUP}" 1>&2
    az group delete -y --name "${AKS_RESOURCE_GROUP}" || true
  fi
}
trap aks_teardown_group ERR

EXISTING=$(az group list | grep "${AKS_RESOURCE_GROUP}" || true)
if [ -n "${EXISTING}" ]; then
  echo "${AKS_RESOURCE_GROUP} already exists!"
  exit 1
fi
AKS_SUBSCRIPTION="$(az account show --query id --output tsv)"
az group create --name "${AKS_RESOURCE_GROUP}" --location ${AKS_LOCATION}
group_created=1
az aks create -g "${AKS_RESOURCE_GROUP}" -n "${AKS_CLUSTER_NAME}" \
  --node-count 1 --enable-oidc-issuer --enable-workload-identity \
  --enable-cluster-autoscaler --min-count 1 --max-count 3 \
  --generate-ssh-keys

# Tagging intentionally omitted (DRIVERS-3712 red: untagged baseline)..
AKS_OIDC_ISSUER="$(az aks show -n "${AKS_CLUSTER_NAME}" -g "${AKS_RESOURCE_GROUP}" --query "oidcIssuerProfile.issuerUrl" -otsv)"
export AKS_OIDC_ISSUER
az account set --subscription "${AKS_SUBSCRIPTION}"
az identity create --name "${AKS_USER_ASSIGNED_IDENTITY_NAME}" --resource-group "${AKS_RESOURCE_GROUP}" \
  --location "${AKS_LOCATION}" --subscription "${AKS_SUBSCRIPTION}"
USER_ASSIGNED_CLIENT_ID="$(az identity show --resource-group "${AKS_RESOURCE_GROUP}" \
  --name "${AKS_USER_ASSIGNED_IDENTITY_NAME}" --query 'clientId' -otsv)"
export USER_ASSIGNED_CLIENT_ID
az aks get-credentials --overwrite-existing -n "${AKS_CLUSTER_NAME}" -g "${AKS_RESOURCE_GROUP}"
. $DRIVERS_TOOLS/.evergreen/ensure-binary.sh kubectl
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: ${USER_ASSIGNED_CLIENT_ID}
  name: ${AKS_SERVICE_ACCOUNT_NAME}
  namespace: ${AKS_SERVICE_ACCOUNT_NAMESPACE}
EOF
az identity federated-credential create --name ${AKS_FEDERATED_IDENTITY_CREDENTIAL_NAME} \
  --identity-name ${AKS_USER_ASSIGNED_IDENTITY_NAME} --resource-group ${AKS_RESOURCE_GROUP} \
  --issuer ${AKS_OIDC_ISSUER} --subject system:serviceaccount:${AKS_SERVICE_ACCOUNT_NAMESPACE}:${AKS_SERVICE_ACCOUNT_NAME}
# Assign the resource group
RESOURCE_SUBSCRIPTION=$(az group show --resource-group $AKS_RESOURCE_GROUP -o tsv --query id)
export RESOURCE_SUBSCRIPTION
az role assignment create --role "Azure Kubernetes Service RBAC Admin" --assignee $AKS_APPLICATION_ID  --scope $RESOURCE_SUBSCRIPTION

# Provisioning is complete: a tag verification failure must not delete the
# long-lived cluster.
trap - ERR

# Verify the created resources' tags when requested. verify_aks_tags exits
# the sourcing shell on failure.
if [ -n "${VERIFY_MONGODB_TAGS:-}" ]; then
  . "$AKS_SCRIPT_DIR"/verify-aks-setup.sh
  verify_aks_tags
fi
