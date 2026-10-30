#!/bin/bash
# Verify an ingress controller exposes applications outside the cluster.
# Deploy a web page behind an ingress, then query it in HTTP and HTTPS
# from this machine, on default ports.

# shellcheck source=SCRIPTDIR/lib/common.bash
source "$(dirname "$0")/lib/common.bash"

MANIFEST="$(dirname "$0")/../k8s_manifests/ingress-test.yaml"
APP="datagalaxy-ingress-test"
DEFAULT_HOST="datagalaxy.int.domaine.com"
DEFAULT_IMAGE="nginxinc/nginx-unprivileged"
EXPECTED="OK!"
RETRIES=12

IMAGE="${DG_IMAGE:-$DEFAULT_IMAGE}"
TIMEOUT="${DG_TIMEOUT:-120}"

load_messages
[ "$1" = "-h" ] && usage 0 ingress "$DEFAULT_IMAGE"
if [ -z "$DG_NAMESPACE" ] || [ -z "$DG_DOMAIN" ]; then usage 2 ingress "$DEFAULT_IMAGE"; fi
[ -f "$MANIFEST" ] || die common.manifest_not_found "$MANIFEST"
require_cmd curl

# Without DNS, DG_INGRESS_IP sends the requests to the ingress controller.
CURL_OPTS=(-s -k --max-time 10)
[ -n "$DG_INGRESS_IP" ] && CURL_OPTS+=(--connect-to "$DG_DOMAIN::$DG_INGRESS_IP:")

# Query a URL until the test page is served, the controller may need time to sync.
# Set $page (the page content) and $code (the HTTP status code).
query() {
  for _ in $(seq "$RETRIES"); do
    page="$(curl "${CURL_OPTS[@]}" -w '\n%{http_code}' "$1")"
    code="${page##*$'\n'}"
    case "$code" in
      2*) [[ "$page" == *"$EXPECTED"* ]] && return ;;
      3*) return ;;
    esac
    sleep 5
  done
}

section ingress.title
check_cluster_access "$DG_NAMESPACE"

# The ingress class: DG_INGRESS_CLASS, or the default one.
info ingress.classes
kubectl get ingressclass | indent
if [ -n "$DG_INGRESS_CLASS" ]; then
  kubectl get ingressclass "$DG_INGRESS_CLASS" >/dev/null 2>&1 || { fail ingress.class_missing "$DG_INGRESS_CLASS"; summary; }
else
  kubectl get ingressclass -o yaml | grep -q 'is-default-class: "true"' || warn ingress.no_default_class
fi

# Show the controller among the cluster PODs, and how it is linked to the outside network.
controller_pods="$(kubectl get pods -A -o wide | grep -Ei 'ingress|traefik|haproxy|router-default|contour|kong|envoy')"
if [ -n "$controller_pods" ]; then
  info ingress.controller_pods
  echo "$controller_pods" | indent
else
  warn ingress.no_controller_pod
fi
info ingress.exposed_services
kubectl get svc -A --no-headers | awk '$3 == "LoadBalancer" || $3 == "NodePort"' | indent
info ingress.describe_link

# Deploy the test application, with the DataGalaxy domain name.
section ingress.deploy_title
info ingress.deploy_info "$DG_DOMAIN" "$IMAGE"
if [ "$DG_KEEP" = true ]; then
  info ingress.kept "$APP" "$DG_NAMESPACE"
else
  trap 'kubectl delete deployment,service,configmap,ingress "$APP" -n "$DG_NAMESPACE" --ignore-not-found >/dev/null 2>&1' EXIT
fi
sed -e "s|$DEFAULT_HOST|$DG_DOMAIN|" -e "s|image: $DEFAULT_IMAGE|image: $IMAGE|" "$MANIFEST" \
  | awk -v ic="$DG_INGRESS_CLASS" '/^  rules:/ && ic != "" { print "  ingressClassName: " ic } { print }' \
  | kubectl apply -n "$DG_NAMESPACE" -f - >/dev/null || { fail ingress.deploy_failed; summary; }
if ! kubectl rollout status deployment/"$APP" -n "$DG_NAMESPACE" --timeout="${TIMEOUT}s" >/dev/null 2>&1; then
  fail ingress.not_ready "$TIMEOUT" "$IMAGE"
  kubectl get pods -n "$DG_NAMESPACE" -l app="$APP" | indent
  summary
fi
ok ingress.deployed
kubectl get ingress "$APP" -n "$DG_NAMESPACE" | indent

# Query the page from outside the cluster. HTTP may be forbidden, HTTPS must work.
section ingress.access_title
[ -n "$DG_INGRESS_IP" ] && info ingress.resolved "$DG_DOMAIN" "$DG_INGRESS_IP"

url="http://$DG_DOMAIN/$APP/index.html"
query "$url"
case "$code" in
  2*) if [[ "$page" == *"$EXPECTED"* ]]; then ok ingress.http_ok "$url" "$EXPECTED"; else warn ingress.http_unexpected "$code"; fi ;;
  3*) ok ingress.http_redirect "$code" ;;
  *)  warn ingress.http_failed "$code" ;;
esac

url="https://$DG_DOMAIN/$APP/index.html"
query "$url"
if [[ "$code" == 2* && "$page" == *"$EXPECTED"* ]]; then
  ok ingress.https_ok "$url" "$EXPECTED"
else
  fail ingress.https_failed "$code"
fi

summary
