#!/bin/bash

set -ex

source hack/common.sh

set +e

# Remove finalizers from all cephclusters, to not block the cleanup
echo "Removing cephcluster finalizers"
$OCS_OC_PATH get cephcluster -n openshift-storage -o=custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,FINALIZERS:.metadata.finalizers --no-headers | grep cephcluster.ceph.rook.io | while read p; do
    arr=($p)
    name="${arr[0]}"
    namespace="${arr[1]}"
    $OCS_OC_PATH patch cephcluster $name -n $namespace --type=json -p '[{ "op": "remove", "path": "/metadata/finalizers" }]'
done

echo "Delete all storageclusterinitializations"
$OCS_OC_PATH -n openshift-storage delete storagecluster,storageclusterinitialization --cascade=false --all

echo "Deleting noobaa objects"
$OCS_OC_PATH -n openshift-storage delete noobaa --all

echo "Deleting noobaa-core stateful set"
$OCS_OC_PATH -n openshift-storage delete --ignore-not-found statefulset noobaa-core

echo "Delete all noobaa-core related pods"
$OCS_OC_PATH -n openshift-storage delete pods -l "noobaa-core"

# delete ceph clusters and storage clusters
echo "Deleting all storageclusters and cephclusters"
$OCS_OC_PATH -n openshift-storage delete cephcluster --all

set -e

echo "Deleting noobaa-operator"
$OCS_OC_PATH -n openshift-storage delete --ignore-not-found deployment noobaa-operator

echo "Deleting rook-operator"
$OCS_OC_PATH -n openshift-storage delete --ignore-not-found deployment rook-operator

echo "Deleting ocs-operator"
$OCS_OC_PATH -n openshift-storage delete --ignore-not-found deployment ocs-operator

echo "Deleting subscriptions"
$OCS_OC_PATH -n openshift-storage delete subscription --all

echo "Deleting all remaining deployments"
$OCS_OC_PATH -n openshift-storage delete deployments --all

echo "Deleting all remaining daemonsets"
$OCS_OC_PATH -n openshift-storage delete daemonsets --all

echo "Deleting all remaining pods"
$OCS_OC_PATH -n openshift-storage delete pods --all

echo "Deleting all PVCs and PVs"
$OCS_OC_PATH -n openshift-storage delete pvc --all

# clean up any remaining objects installed in the deploy manifests such as
# namespaces, operator groups, and resources outside of the openshift-storage namespace.
echo "Deleting remaining ocs-operator manifests"
$OCS_OC_PATH delete --ignore-not-found -f deploy/deploy-with-olm.yaml

echo "Waiting on namespaces to disappear"
# We wait for the namespaces to disappear because that signals
# to us that the delete is finalized. Otherwise a 'cluster-deploy'
# might fail if all cluster artifacts haven't finished being removed.
managed_namespaces=(openshift-storage local-storage)
for i in ${managed_namespaces[@]}; do
	if [ -n "$($OCS_OC_PATH get namespace | grep "${i} ")" ]; then
		echo "Deleting namespace ${i}"
		$OCS_OC_PATH delete --ignore-not-found namespace ${i}

		current_time=0
		sample=10
		timeout=120
		echo "Waiting for ${i} namespace to disappear ..."
		while [ -n "$($OCS_OC_PATH get namespace | grep "${i} ")" ]; do
			sleep $sample
			current_time=$((current_time + sample))
			if [[ $current_time -gt $timeout ]]; then
				exit 1
			fi
		done
	fi
done

# clean old
rm -rf $OUTDIR_CLUSTER_DEPLOY_MANIFESTS
