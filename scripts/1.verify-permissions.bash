#!/bin/bash
# Verify the technical account can create the resources DataGalaxy needs.
# Each check runs "kubectl auth can-i create <resource>", which must answer "yes".

# shellcheck source=SCRIPTDIR/lib/common.bash
source "$(dirname "$0")/lib/common.bash"

load_messages
[ "$1" = "-h" ] && usage 0 permissions
[ -n "$DG_NAMESPACE" ] || usage 2 permissions

can_create() {
  if [ "$(kubectl auth can-i create "$@" 2>/dev/null)" = "yes" ]; then
    ok permissions.can_create "$1"
  else
    fail permissions.can_create "$1"
  fi
}

section permissions.title
check_cluster_access "$DG_NAMESPACE"
info permissions.user "$(kubectl auth whoami -o jsonpath='{.status.userInfo.username}' 2>/dev/null)"

section permissions.namespaced "$DG_NAMESPACE"
can_create pod                   -n "$DG_NAMESPACE"
can_create service               -n "$DG_NAMESPACE"
can_create deployment            -n "$DG_NAMESPACE"
can_create replicaset            -n "$DG_NAMESPACE"
can_create persistentvolumeclaim -n "$DG_NAMESPACE"
can_create configmap             -n "$DG_NAMESPACE"
can_create secret                -n "$DG_NAMESPACE"
can_create statefulset           -n "$DG_NAMESPACE"
can_create serviceaccount        -n "$DG_NAMESPACE"
can_create ingress               -n "$DG_NAMESPACE"
can_create job                   -n "$DG_NAMESPACE"
can_create cronjob               -n "$DG_NAMESPACE"
can_create networkpolicy         -n "$DG_NAMESPACE"
can_create role                  -n "$DG_NAMESPACE"

section permissions.cluster
can_create clusterrole
can_create crd

summary
