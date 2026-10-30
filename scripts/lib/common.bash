#!/bin/bash
# Shared helpers for the verification scripts.
# Meant to be sourced, not executed.

I18N_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../i18n" && pwd)"

COUNT_OK=0
COUNT_WARN=0
COUNT_FAIL=0

# Language of the messages: -l option, DG_LANG variable, or the system locale.
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
  fr*) DG_LANG="${DG_LANG:-fr}" ;;
  *)   DG_LANG="${DG_LANG:-en}" ;;
esac

# Load i18n/<lang>.properties: each "a.b=value" line becomes the MSG_a_b variable.
load_messages() {
  local file="$I18N_DIR/$DG_LANG.properties" key value
  if [ ! -f "$file" ]; then
    echo "[ERROR] Unsupported language '$DG_LANG': use fr or en." >&2
    exit 2
  fi
  while IFS='=' read -r key value || [ -n "$key" ]; do
    case "$key" in ''|'#'*) continue ;; esac
    printf -v "MSG_${key//./_}" '%s' "$value"
  done < "$file"
}

# Print a message: msg <key> [parameters...]
msg() {
  local var="MSG_${1//./_}"
  shift
  # shellcheck disable=SC2059 # The format comes from the properties file.
  printf "${!var}" "$@"
}

if [ -t 1 ]; then
  C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'; C_BOLD=$'\e[1m'; C_RESET=$'\e[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""; C_RESET=""
fi

# All these functions take a message key, followed by its parameters.
section() { echo; echo "${C_BOLD}== $(msg "$@") ==${C_RESET}"; }
info()    { echo "${C_BLUE}[INFO]${C_RESET} $(msg "$@")"; }
ok()      { echo "${C_GREEN}[OK]${C_RESET}   $(msg "$@")"; COUNT_OK=$((COUNT_OK + 1)); }
warn()    { echo "${C_YELLOW}[WARN]${C_RESET} $(msg "$@")"; COUNT_WARN=$((COUNT_WARN + 1)); }
fail()    { echo "${C_RED}[FAIL]${C_RESET} $(msg "$@")"; COUNT_FAIL=$((COUNT_FAIL + 1)); }
die()     { echo "${C_RED}[$(msg common.error)]${C_RESET} $(msg "$@")" >&2; exit 2; }

# Print the help of a script and exit: usage <exit code> <script key> [parameters...]
usage() {
  local code="$1" key="$2"
  shift 2
  msg "$key.usage" "$(basename "$0")" "$@"
  echo
  exit "$code"
}

# Indent the output of a command, to distinguish it from the verdicts.
indent()  { sed 's/^/       /'; }

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die common.command_not_found "$cmd"
  done
}

# Verify kubectl can reach the cluster and the namespace exists.
check_cluster_access() {
  local ns="$1"
  require_cmd kubectl
  kubectl version >/dev/null 2>&1 || die common.cluster_unreachable
  info common.context "$(kubectl config current-context 2>/dev/null)"
  kubectl get namespace "$ns" >/dev/null 2>&1 || die common.namespace_missing "$ns"
  info common.namespace "$ns"
}

# Print the summary and exit: 0 if no blocking failure, 1 otherwise.
summary() {
  section common.summary
  echo "${C_GREEN}${COUNT_OK} OK${C_RESET}, ${C_YELLOW}$(msg common.warnings "$COUNT_WARN")${C_RESET}, ${C_RED}$(msg common.failures "$COUNT_FAIL")${C_RESET}"
  [ "$COUNT_FAIL" -eq 0 ]
  exit $?
}
