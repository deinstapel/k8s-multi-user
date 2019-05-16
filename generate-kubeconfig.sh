#!/usr/bin/env bash

set -e

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 username"
  exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

which gomplate > /dev/null 2>&1 || (echo 'This script needs gomplate!' 1>&2 && exit 1)
which jq > /dev/null 2>&1 || (echo 'This script needs jq!' 1>&2 && exit 1)
which kubectl > /dev/null 2>&1 || (echo 'This script needs kubectl!' 1>&2 && exit 1)
which base64 > /dev/null 2>&1 || (echo 'This script needs base64!' 1>&2 && exit 1)

kubectl auth can-i describe sa -n kube-system > /dev/null 2>&1 || (echo 'You are not allowed to read service accounts in the kube-system namespace' 1>&2 && exit 2)

kubectl auth can-i get secret -n kube-system > /dev/null 2>&1 || (echo 'You are not allowed to read secrets in the kube-system namespace' 1>&2 && exit 2)

TOKEN_ID="$(kubectl get sa -n kube-system k8s-user-$1 -o json | jq -r '.secrets[0].name')"
echo "Token ID: ${TOKEN_ID}" 1>&2

SECRET_CONTENT="$(kubectl get secret -n kube-system ${TOKEN_ID} -o json)"

export TOKEN="$(echo ${SECRET_CONTENT} | jq -r .data.token | base64 -d)"
export USER_CA_CERT="$(echo ${SECRET_CONTENT} | jq -r .data\[\"ca.crt\"\])"
export CLUSTER_NAME="$(kubectl config view -o json | jq -r .clusters\[0\].name)"
export CLUSTER_SERVER="$(kubectl config view -o json | jq -r .clusters\[0\].cluster.server)"
export USER_NAME="$1"

echo "Generating kubeconfig for user ${USER_NAME} for cluster ${CLUSTER_NAME} @ ${CLUSTER_SERVER}" 1>&2

gomplate -f "${DIR}/kubeconfig_tmpl" > "${DIR}/kubeconfig.${USER_NAME}"
echo "Find your generated kubeconfig at ${DIR}/kubeconfig.${USER_NAME}" 1>&2
