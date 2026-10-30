#!/bin/bash
# Verify persistent volumes are dynamically provisioned through PVC.
# Create a PVC and a POD writing on it, check the provisioned volume,
# then delete the PVC and check the volume is deleted too.

# shellcheck source=SCRIPTDIR/lib/common.bash
source "$(dirname "$0")/lib/common.bash"

MANIFEST="$(dirname "$0")/../k8s_manifests/storage-test.yaml"
PVC="datagalaxy-test"
POD="datagalaxy-storage-test"
DEFAULT_IMAGE="nginxinc/nginx-unprivileged"

SIZE="${DG_STORAGE_SIZE:-1Gi}"
STORAGE_CLASS="${DG_STORAGE_CLASS:-}"
IMAGE="${DG_IMAGE:-$DEFAULT_IMAGE}"
TIMEOUT="${DG_TIMEOUT:-120}"

load_messages
[ "$1" = "-h" ] && usage 0 storage "$DEFAULT_IMAGE"
[ -n "$DG_NAMESPACE" ] || usage 2 storage "$DEFAULT_IMAGE"
[ -f "$MANIFEST" ] || die common.manifest_not_found "$MANIFEST"

cleanup() {
  kubectl delete pod "$POD" -n "$DG_NAMESPACE" --ignore-not-found >/dev/null 2>&1
  kubectl delete pvc "$PVC" -n "$DG_NAMESPACE" --ignore-not-found >/dev/null 2>&1
}

section storage.title
check_cluster_access "$DG_NAMESPACE"

# The storage class: DG_STORAGE_CLASS, or the default one.
info storage.classes
kubectl get storageclass | indent
if [ -n "$STORAGE_CLASS" ]; then
  kubectl get storageclass "$STORAGE_CLASS" >/dev/null 2>&1 || { fail storage.class_missing "$STORAGE_CLASS"; summary; }
else
  kubectl get storageclass | grep -q '(default)' || { fail storage.no_default_class; summary; }
fi

# The namespace should not contain any PVC yet.
if [ -n "$(kubectl get pvc -n "$DG_NAMESPACE" --no-headers 2>/dev/null)" ]; then
  warn storage.existing_pvc "$DG_NAMESPACE"
  kubectl get pvc -n "$DG_NAMESPACE" | indent
fi

# No volume must be prepared in advance for the test PVC.
if kubectl get pv --no-headers 2>/dev/null | grep " $DG_NAMESPACE/$PVC " | grep -qv Released; then
  fail storage.pv_exists "$DG_NAMESPACE/$PVC"
  summary
fi

# Create the PVC and the POD: the PVC must get bound, without any manual action.
section storage.test_title "$SIZE"
trap cleanup EXIT
sed -e "s|storage: 1Gi|storage: $SIZE|" -e "s|image: $DEFAULT_IMAGE|image: $IMAGE|" "$MANIFEST" \
  | awk -v sc="$STORAGE_CLASS" '/^  accessModes:/ && sc != "" { print "  storageClassName: " sc } { print }' \
  | kubectl create -n "$DG_NAMESPACE" -f - >/dev/null || { fail storage.create_failed; summary; }
if ! kubectl wait pvc/"$PVC" -n "$DG_NAMESPACE" --for=jsonpath='{.status.phase}'=Bound --timeout="${TIMEOUT}s" >/dev/null 2>&1; then
  fail storage.not_bound "$TIMEOUT"
  kubectl describe pvc "$PVC" -n "$DG_NAMESPACE" | sed -n '/^Events:/,$p' | indent
  summary
fi
ok storage.bound

# Check the provisioned volume.
pv="$(kubectl get pvc "$PVC" -n "$DG_NAMESPACE" -o jsonpath='{.spec.volumeName}')"
read -r capacity class reclaim hostpath <<< "$(kubectl get pv "$pv" -o jsonpath='{.spec.capacity.storage} {.spec.storageClassName} {.spec.persistentVolumeReclaimPolicy} {.spec.hostPath.path}')"
kubectl get pv "$pv" | indent
if [ "$capacity" = "$SIZE" ]; then
  ok storage.size_ok "$pv" "$capacity" "$class"
else
  warn storage.size_diff "$pv" "$capacity" "$SIZE" "$class"
fi
[ -n "$hostpath" ] && warn storage.hostpath

# The POD must be able to write on the volume.
if kubectl wait pod/"$POD" -n "$DG_NAMESPACE" --for=jsonpath='{.status.phase}'=Succeeded --timeout="${TIMEOUT}s" >/dev/null 2>&1; then
  ok storage.writable
else
  warn storage.not_writable
  kubectl describe pod "$POD" -n "$DG_NAMESPACE" | sed -n '/^Events:/,$p' | indent
fi

# Deleting the PVC should delete the volume, unless its reclaim policy keeps it.
cleanup
if [ "$reclaim" != "Delete" ]; then
  warn storage.pv_retained "$pv" "$reclaim"
  info storage.pv_delete_hint "$pv"
elif kubectl wait pv/"$pv" --for=delete --timeout="${TIMEOUT}s" >/dev/null 2>&1; then
  ok storage.pv_deleted "$pv"
else
  fail storage.pv_still_there "$pv" "$TIMEOUT"
fi

summary
