#!/bin/bash
set -e

# This script will be used by travis to run functional test
# against different kuberentes version
export KUBE_VERSION=$1
# parse the kubernetes version, return the digit passed as argument
# v1.17.0 -> kube_version 1 -> 1
# v1.17.0 -> kube_version 2 -> 17
kube_version() {
    echo "${KUBE_VERSION}" | sed 's/^v//' | cut -d'.' -f"${1}"
}
sudo scripts/minikube.sh up
sudo scripts/minikube.sh deploy-rook
sudo scripts/minikube.sh create-block-pool
# pull docker images to speed up e2e
sudo scripts/minikube.sh cephcsi
sudo scripts/minikube.sh k8s-sidecar
sudo chown -R travis: "$HOME"/.minikube /usr/local/bin/kubectl

NAMESPACE=cephcsi-e2e-$RANDOM
# create ns for e2e
kubectl create ns ${NAMESPACE}
KUBE_MAJOR=$(kube_version 1)
KUBE_MINOR=$(kube_version 2)
# skip snapshot operation if kube version is less than 1.17.0
if [[ "${KUBE_MAJOR}" -ge 1 ]] && [[ "${KUBE_MINOR}" -ge 17 ]]; then
    # delete snapshot CRD created by ceph-csi in rook
    scripts/install-snapshot.sh delete-crd
    # install snapshot controller
    scripts/install-snapshot.sh install
fi
# set up helm
scripts/install-helm.sh up
# install cephcsi helm charts
scripts/install-helm.sh install-cephcsi ${NAMESPACE}
# functional tests
go test github.com/ceph/ceph-csi/e2e -mod=vendor --deploy-timeout=10 -timeout=30m --cephcsi-namespace=${NAMESPACE} --deploy-cephfs=false --deploy-rbd=false -v

#cleanup
# skip snapshot operation if kube version is less than 1.17.0
if [[ "${KUBE_MAJOR}" -ge 1 ]] && [[ "${KUBE_MINOR}" -ge 17 ]]; then
    # delete snapshot CRD
    scripts/install-snapshot.sh cleanup
fi
scripts/install-helm.sh cleanup-cephcsi ${NAMESPACE}
scripts/install-helm.sh clean
kubectl delete ns ${NAMESPACE}
sudo scripts/minikube.sh clean
