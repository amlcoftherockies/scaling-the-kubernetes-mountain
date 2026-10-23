#!/usr/bin/env bash
# ==============================================================================
# ckad-lab-smoke-test.sh — CKAD Lab Cluster Smoke Test & Security Audit
# ==============================================================================
# Specifically for the CKAD Track (Shared Multi-Tenant GKE Cluster, Sections 4–10).
# (Not for the CKA Track, where participants use dedicated Compute Engine VMs.)
#
# Validates that the current kubeconfig user:
#   1. Can connect & has a valid non-expired token + default namespace
#   2. Is NOT over-permissioned (RBAC least-privilege, PodSecurity, Admission
#      Policies, ResourceQuotas, and LoadBalancer caps are enforced)
#   3. Has all permissions & cluster capabilities required to complete every
#      CKAD lab module (Sections 4 through 10), including live external HTTP
#      routing on <namespace>.<domain>.
#
# Usage:
#   ./scripts/ckad-lab-smoke-test.sh [options]
#
# Options:
#   -k, --kubeconfig PATH   Kubeconfig to test (default: $KUBECONFIG, then
#                           ~/.kube/config, or ~/.kube/ckad-lab.kubeconfig)
#   -d, --domain DOMAIN     Base ingress domain (default: amlcoftherockies.net)
#   -n, --namespace NS      Override target namespace (default: from kubeconfig)
#   --quick                 Run RBAC & guardrail checks only (skip live Pod/HTTP
#                           deployment smoke tests)
#   -h, --help              Show this help message
# ==============================================================================

set -uo pipefail

# --- Default Configuration ---
DEFAULT_DOMAIN="amlcoftherockies.net"
DOMAIN="${WORKSHOP_DOMAIN:-$DEFAULT_DOMAIN}"
KUBECONFIG_ARG=""
NAMESPACE_ARG=""
QUICK_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -k|--kubeconfig)
      KUBECONFIG_ARG="$2"
      shift 2
      ;;
    -d|--domain)
      DOMAIN="$2"
      shift 2
      ;;
    -n|--namespace)
      NAMESPACE_ARG="$2"
      shift 2
      ;;
    --quick)
      QUICK_MODE=true
      shift
      ;;
    -h|--help)
      sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $1 (use --help for usage)" >&2
      exit 2
      ;;
  esac
done

# --- Resolve KUBECONFIG (defaults to standard ~/.kube/config or $KUBECONFIG) ---
if [[ -n "$KUBECONFIG_ARG" ]]; then
  export KUBECONFIG="$KUBECONFIG_ARG"
elif [[ -n "${KUBECONFIG:-}" ]]; then
  export KUBECONFIG="$KUBECONFIG"
elif [[ -f "$HOME/.kube/config" ]]; then
  export KUBECONFIG="$HOME/.kube/config"
elif [[ -f "$HOME/.kube/ckad-lab.kubeconfig" ]]; then
  export KUBECONFIG="$HOME/.kube/ckad-lab.kubeconfig"
else
  export KUBECONFIG="$HOME/.kube/config"
fi

# --- Formatting & Counters ---
BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
RESET="\033[0m"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
declare -a REPORT_ROWS=()
declare -a GUIDANCE_ITEMS=()

record_pass() {
  local section="$1"
  local check="$2"
  local detail="${3:-}"
  PASS_COUNT=$((PASS_COUNT + 1))
  printf "  ${GREEN}✓ PASS${RESET}  %-52s ${DIM}%s${RESET}\n" "$check" "$detail"
  REPORT_ROWS+=("PASS|${section}|${check}|${detail}")
}

record_warn() {
  local section="$1"
  local check="$2"
  local detail="${3:-}"
  local fix="${4:-}"
  WARN_COUNT=$((WARN_COUNT + 1))
  printf "  ${YELLOW}⚠ WARN${RESET}  %-52s ${YELLOW}%s${RESET}\n" "$check" "$detail"
  REPORT_ROWS+=("WARN|${section}|${check}|${detail}")
  if [[ -n "$fix" ]]; then
    GUIDANCE_ITEMS+=("[WARN] ${check}: ${fix}")
  fi
}

record_fail() {
  local section="$1"
  local check="$2"
  local detail="${3:-}"
  local fix="${4:-}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "  ${RED}✗ FAIL${RESET}  %-52s ${RED}%s${RESET}\n" "$check" "$detail"
  REPORT_ROWS+=("FAIL|${section}|${check}|${detail}")
  if [[ -n "$fix" ]]; then
    GUIDANCE_ITEMS+=("[FAIL] ${check}: ${fix}")
  fi
}

cleanup_smoke_resources() {
  if [[ -n "${NS:-}" ]]; then
    kubectl -n "$NS" delete pod,svc,httproute,ingress,pvc,podmonitoring \
      -l app.kubernetes.io/managed-by=ckad-smoke-test \
      --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
}
trap cleanup_smoke_resources EXIT

echo -e "${BOLD}==============================================================================${RESET}"
echo -e "${BOLD}  CKAD LAB SMOKE TEST & SECURITY AUDIT (CKAD Track — Sections 4–10)${RESET}"
echo -e "${BOLD}==============================================================================${RESET}"
echo -e "  ${DIM}Track:${RESET}      CKAD Shared Cluster Lab (not CKA VM Track)"
echo -e "  ${DIM}Kubeconfig:${RESET} ${KUBECONFIG}"
echo -e "  ${DIM}Domain:${RESET}     ${DOMAIN}"
echo ""

# ==============================================================================
# PHASE 1: Local CLI Prerequisites & Cluster Connectivity
# ==============================================================================
echo -e "${BOLD}${CYAN}[1/4] Local CLI Tools & Cluster Connectivity${RESET}"

if command -v kubectl >/dev/null 2>&1; then
  K_VER=$(kubectl version --client -o yaml 2>/dev/null | awk '/gitVersion:/ {print $2; exit}')
  record_pass "1. CLI & Auth" "kubectl CLI installed" "${K_VER:-installed}"
else
  record_fail "1. CLI & Auth" "kubectl CLI installed" "kubectl not found in PATH" \
    "Install kubectl: brew install kubectl (macOS) or winget install Kubernetes.kubectl (Windows)."
  echo -e "\n${RED}Cannot proceed without kubectl. Exiting.${RESET}"
  exit 1
fi

if command -v helm >/dev/null 2>&1; then
  H_VER=$(helm version --short 2>/dev/null | head -n 1)
  record_pass "1. CLI & Auth" "helm CLI installed (for Section 10)" "${H_VER}"
else
  record_warn "1. CLI & Auth" "helm CLI installed (for Section 10)" "helm not found in PATH" \
    "Section 10 Module 1 requires Helm v3. Install via: brew install helm (macOS) or winget install Helm.Helm (Windows)."
fi

if [[ ! -f "$KUBECONFIG" ]]; then
  record_fail "1. CLI & Auth" "Kubeconfig file exists" "File not found: $KUBECONFIG" \
    "Save your emailed ckad-lab.kubeconfig to ~/.kube/config (or export KUBECONFIG=~/.kube/ckad-lab.kubeconfig) or pass --kubeconfig PATH."
  echo -e "\n${RED}Cannot proceed without a valid kubeconfig file. Exiting.${RESET}"
  exit 1
else
  record_pass "1. CLI & Auth" "Kubeconfig file exists" "$KUBECONFIG"
fi

NS="${NAMESPACE_ARG:-$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)}"
if [[ -z "$NS" ]]; then
  NS="default"
  record_warn "1. CLI & Auth" "Default namespace set in kubeconfig context" "None set (falling back to 'default')" \
    "Set your namespace in the context: kubectl config set-context --current --namespace=<your-namespace>."
else
  record_pass "1. CLI & Auth" "Default namespace set in kubeconfig context" "namespace=${NS}"
fi

WHOAMI=$(kubectl auth whoami -o jsonpath='{.status.userInfo.username}' 2>/dev/null || true)
if [[ -z "$WHOAMI" ]]; then
  record_fail "1. CLI & Auth" "API server authentication (kubectl auth whoami)" "Unauthorized or cluster unreachable" \
    "Your kubeconfig token may have expired (GKE tokens last 48h) or the cluster is down. Ask the instructor to run: labctl-gke rotate <your-email>."
  echo -e "\n${RED}Authentication failed. Cannot run cluster checks.${RESET}"
  exit 1
else
  record_pass "1. CLI & Auth" "API server authentication (kubectl auth whoami)" "${WHOAMI}"
fi

MY_HOST="${NS}.${DOMAIN}"
echo -e "  ${DIM}Target Namespace:${RESET} ${NS}"
echo -e "  ${DIM}Student Hostname:${RESET} http://${MY_HOST}"
echo ""

# ==============================================================================
# PHASE 2: Over-Permissive Access Audit (Least-Privilege & Multi-Tenant Safety)
# ==============================================================================
echo -e "${BOLD}${CYAN}[2/4] Least-Privilege & Over-Permissive Access Audit${RESET}"

IS_CLUSTER_ADMIN=$(kubectl auth can-i '*' '*' --all-namespaces 2>/dev/null || true)
if [[ "$IS_CLUSTER_ADMIN" == "yes" ]]; then
  record_fail "2. Security Audit" "Not using cluster-admin credentials" "User '${WHOAMI}' has full cluster-admin ('*' '*')" \
    "You are using an instructor/admin kubeconfig! Students must use their namespace-scoped ServiceAccount kubeconfig (e.g., ~/.kube/ckad-lab.kubeconfig)."
else
  record_pass "2. Security Audit" "Not using cluster-admin credentials" "can-i '*' '*' = no"
fi

check_denied() {
  local label="$1"
  local fix="$2"
  shift 2
  local ans
  ans=$(kubectl auth can-i "$@" 2>/dev/null || true)
  if [[ "$ans" == "no" ]]; then
    record_pass "2. Security Audit" "$label" "denied as expected"
  else
    record_fail "2. Security Audit" "$label" "OVER-PERMISSIVE (can-i $* = yes)" "$fix"
  fi
}

check_denied "Cannot list Secrets in kube-system" \
  "Student ServiceAccount can read kube-system Secrets! Check ClusterRoleBindings and remove broad view/edit bindings." \
  list secrets -n kube-system

check_denied "Cannot list Pods in default namespace" \
  "Student ServiceAccount can list Pods outside their namespace! Ensure RoleBinding is Namespace-scoped, not ClusterRoleBinding." \
  list pods -n default

check_denied "Cannot create Namespaces (cluster-scoped)" \
  "User can create namespaces. Ensure student is only bound via a namespaced RoleBinding." \
  create namespaces

check_denied "Cannot create ClusterRoles or ClusterRoleBindings" \
  "User can modify cluster-wide RBAC. Remove cluster-scoped RBAC permissions." \
  create clusterroles

check_denied "Cannot create PersistentVolumes (hostPath bypass risk)" \
  "User can create PVs directly (which allows hostPath mounts). Students should only create namespaced PVCs." \
  create persistentvolumes

check_denied "Cannot delete or modify cluster Nodes" \
  "User can mutate cluster nodes! labctl-participant-cluster-read must only grant get/list/watch on nodes." \
  delete nodes

check_denied "Cannot modify ValidatingAdmissionPolicies" \
  "User can alter cluster admission guardrails! Revoke admissionregistration.k8s.io write access." \
  delete validatingadmissionpolicies

check_denied "Cannot modify own ResourceQuota (${NS})" \
  "User can edit ResourceQuotas in ${NS}. Standard 'edit' ClusterRole does not allow quota writes—check custom roles." \
  update resourcequotas -n "$NS"

echo ""

# ==============================================================================
# PHASE 3: Required Student Permissions & Guardrail Objects (Sections 4–10)
# ==============================================================================
echo -e "${BOLD}${CYAN}[3/4] Required Student Permissions & Namespace Guardrails (Sections 4–10)${RESET}"

check_allowed() {
  local label="$1"
  local fix="$2"
  shift 2
  local ans
  ans=$(kubectl auth can-i "$@" 2>/dev/null || true)
  if [[ "$ans" == "yes" ]]; then
    record_pass "3. Lab RBAC" "$label" "allowed"
  else
    record_fail "3. Lab RBAC" "$label" "FORBIDDEN (can-i $* = no)" "$fix"
  fi
}

# Section 4: Core Workloads
check_allowed "Section 4: Create Pods, Deployments, DaemonSets, Jobs, CronJobs" \
  "Missing workload permissions in ${NS}. Run 'labctl-gke infra --apply' or check RoleBinding 'workshop-user-edit' in ${NS}." \
  create deployments -n "$NS"
check_allowed "Section 4: Create DaemonSets & CronJobs in ${NS}" \
  "Missing DaemonSet/CronJob permissions in ${NS}. Verify RoleBinding to 'edit' ClusterRole." \
  create daemonsets.apps -n "$NS"
check_allowed "Section 4: Read cluster Nodes (read-only)" \
  "Cannot list nodes. Run 'labctl-gke infra --apply' to update ClusterRole 'labctl-participant-cluster-read'." \
  list nodes

# Section 5: Config & Storage
check_allowed "Section 5: Create ConfigMaps, Secrets, PVCs & StatefulSets" \
  "Missing PVC/ConfigMap/Secret permissions in ${NS}. Check RoleBinding in ${NS}." \
  create persistentvolumeclaims -n "$NS"
check_allowed "Section 5: Read StorageClasses, PVs & CSI Drivers (read-only)" \
  "Cannot list StorageClasses or CSIDrivers. Run 'labctl-gke infra --apply' to update 'labctl-participant-cluster-read'." \
  list csidrivers.storage.k8s.io
check_allowed "Section 5 & 7: Inspect kube-system Pods, DaemonSets & Autoscaler" \
  "Cannot list Pods/DaemonSets in kube-system. Run 'labctl-gke infra --apply' to install 'labctl-kubesystem-reader'." \
  list daemonsets.apps -n kube-system

# Section 6: RuntimeClass
check_allowed "Section 6: Read RuntimeClasses (gVisor inspection)" \
  "Cannot list RuntimeClasses. Run 'labctl-gke infra --apply' to update 'labctl-participant-cluster-read'." \
  list runtimeclasses.node.k8s.io

# Section 7: Observability & Metrics
check_allowed "Section 7: Read Node & Pod Metrics (kubectl top)" \
  "Cannot read metrics.k8s.io. Run 'labctl-gke infra --apply' so 'labctl-participant-cluster-read' includes metrics.k8s.io." \
  list pods.metrics.k8s.io -n "$NS"

# Section 8: Security, RBAC & NetworkPolicy
check_allowed "Section 8: Create ServiceAccounts, Roles, RoleBindings & NetworkPolicies" \
  "Cannot create Roles, RoleBindings, ServiceAccounts, or NetworkPolicies in ${NS}. Run 'labctl-gke infra --apply'." \
  create roles.rbac.authorization.k8s.io -n "$NS"
check_allowed "Section 8: Create NetworkPolicies in ${NS}" \
  "Cannot create NetworkPolicies in ${NS}. Verify 'edit' RoleBinding." \
  create networkpolicies.networking.k8s.io -n "$NS"

# Section 9: Services, Ingress & Gateway API HTTPRoutes
check_allowed "Section 9: Create Ingresses (networking.k8s.io) in ${NS}" \
  "Cannot create Ingresses in ${NS}. Verify 'edit' RoleBinding." \
  create ingresses.networking.k8s.io -n "$NS"
check_allowed "Section 9: Create Gateway API HTTPRoutes in ${NS}" \
  "Cannot create HTTPRoutes. Run 'labctl-gke infra --apply' to ensure ClusterRole 'labctl-gateway-routes-edit' aggregates to 'edit'." \
  create httproutes.gateway.networking.k8s.io -n "$NS"
check_allowed "Section 9: Read shared Gateway in lab-ingress namespace" \
  "Cannot read Gateway in lab-ingress. Run 'labctl-gke infra --apply' to create RoleBinding 'gateway-reader' in lab-ingress." \
  get gateways.gateway.networking.k8s.io -n lab-ingress

# Section 10: Helm, Kustomize & Operator CRDs
check_allowed "Section 10: List CustomResourceDefinitions (kubectl get crd)" \
  "Cannot list CRDs. Run 'labctl-gke infra --apply' to add 'customresourcedefinitions' to 'labctl-participant-cluster-read'." \
  list customresourcedefinitions.apiextensions.k8s.io
check_allowed "Section 10: Create PodMonitoring CRs (monitoring.googleapis.com)" \
  "Cannot create PodMonitoring CRs. Run 'labctl-gke infra --apply' to update 'labctl-gateway-routes-edit'." \
  create podmonitorings.monitoring.googleapis.com -n "$NS"

# Check presence of ResourceQuota & LimitRange in target namespace
if kubectl -n "$NS" get resourcequota workshop-quota >/dev/null 2>&1; then
  LB_QUOTA=$(kubectl -n "$NS" get resourcequota workshop-quota -o jsonpath='{.spec.hard.services\.loadbalancers}' 2>/dev/null || echo "?")
  record_pass "3. Guardrails" "ResourceQuota 'workshop-quota' present in ${NS}" "services.loadbalancers=${LB_QUOTA}"
else
  record_warn "3. Guardrails" "ResourceQuota 'workshop-quota' present in ${NS}" "Not found in ${NS}" \
    "Namespace '${NS}' is missing 'workshop-quota'. Re-apply namespace guardrails via: labctl-gke infra --apply."
fi

if kubectl -n "$NS" get limitrange workshop-defaults >/dev/null 2>&1; then
  record_pass "3. Guardrails" "LimitRange 'workshop-defaults' present in ${NS}" "present"
else
  record_warn "3. Guardrails" "LimitRange 'workshop-defaults' present in ${NS}" "Not found in ${NS}" \
    "Namespace '${NS}' is missing 'workshop-defaults'. Re-apply namespace guardrails via: labctl-gke infra --apply."
fi

echo ""

# ==============================================================================
# PHASE 4: Live End-to-End Functional & Guardrail Smoke Tests
# ==============================================================================
if [[ "$QUICK_MODE" == "true" ]]; then
  echo -e "${BOLD}${CYAN}[4/4] Live Functional & Guardrail Smoke Tests (SKIPPED via --quick)${RESET}"
else
  echo -e "${BOLD}${CYAN}[4/4] Live Functional & Guardrail Smoke Tests (in namespace '${NS}')${RESET}"

  # 4.1 Guardrail test: Privileged Pod must be rejected by Pod Security 'baseline'
  PRIV_OUT=$(kubectl -n "$NS" apply --dry-run=server -f - 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: smoke-priv-test
  labels:
    app.kubernetes.io/managed-by: ckad-smoke-test
spec:
  containers:
  - name: bad
    image: busybox:1.36
    command: ["sleep", "5"]
    securityContext:
      privileged: true
EOF
)
  if echo "$PRIV_OUT" | grep -qiE "forbidden|violates PodSecurity"; then
    record_pass "4. Live Smoke" "Guardrail: Privileged Pod blocked by PodSecurity" "baseline admission enforced"
  else
    record_fail "4. Live Smoke" "Guardrail: Privileged Pod blocked by PodSecurity" "Privileged pod was ALLOWED!" \
      "Namespace '${NS}' is missing label 'pod-security.kubernetes.io/enforce=baseline'. Run: labctl-gke infra --apply."
  fi

  # 4.2 Guardrail test: Spoofed hostname on Ingress/HTTPRoute must be rejected
  SPOOF_OUT=$(kubectl -n "$NS" apply --dry-run=server -f - 2>&1 <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: smoke-spoof-route
  labels:
    app.kubernetes.io/managed-by: ckad-smoke-test
spec:
  parentRefs:
  - name: lab-gateway
    namespace: lab-ingress
  hostnames:
  - "someone-else.${DOMAIN}"
  rules:
  - backendRefs:
    - name: dummy
      port: 80
EOF
)
  if echo "$SPOOF_OUT" | grep -qiE "denied|hostnames must be set to"; then
    record_pass "4. Live Smoke" "Guardrail: Spoofed HTTPRoute hostname blocked" "ValidatingAdmissionPolicy enforced"
  else
    record_fail "4. Live Smoke" "Guardrail: Spoofed HTTPRoute hostname blocked" "Spoofed hostname 'someone-else.${DOMAIN}' was ALLOWED!" \
      "ValidatingAdmissionPolicy 'labctl-httproute-hosts' is not bound to '${NS}' (needs label 'labctl-managed=true'). Run: labctl-gke infra --apply."
  fi

  # 4.3 Section 7: Live `kubectl top nodes`
  if TOP_OUT=$(kubectl top nodes 2>&1); then
    NODE_CNT=$(echo "$TOP_OUT" | awk 'NR>1 {c++} END {print c+0}')
    record_pass "4. Live Smoke" "Section 7: 'kubectl top nodes' returns live metrics" "${NODE_CNT} node(s) reporting CPU/Memory"
  else
    record_fail "4. Live Smoke" "Section 7: 'kubectl top nodes' returns live metrics" "Failed: $(echo "$TOP_OUT" | head -n 1)" \
      "Ensure GKE Metrics Server is running and 'labctl-participant-cluster-read' grants get/list on metrics.k8s.io."
  fi

  # 4.4 Section 10: Kustomize render check + PodMonitoring Custom Resource lifecycle
  if kubectl -n "$NS" apply -f - >/dev/null 2>&1 <<EOF
apiVersion: monitoring.googleapis.com/v1
kind: PodMonitoring
metadata:
  name: smoke-podmonitoring
  labels:
    app.kubernetes.io/managed-by: ckad-smoke-test
spec:
  selector:
    matchLabels:
      app: smoke-test
  endpoints:
  - port: http
    interval: 30s
EOF
  then
    kubectl -n "$NS" delete podmonitoring smoke-podmonitoring --ignore-not-found >/dev/null 2>&1 || true
    record_pass "4. Live Smoke" "Section 10: Apply & delete PodMonitoring Custom Resource" "monitoring.googleapis.com/v1 reconciled"
  else
    record_fail "4. Live Smoke" "Section 10: Apply & delete PodMonitoring Custom Resource" "Failed to create PodMonitoring CR in ${NS}" \
      "Run 'labctl-gke infra --apply' so ClusterRole 'labctl-gateway-routes-edit' grants podmonitorings access."
  fi

  # 4.5 Sections 4, 8, 9: Deploy restricted-compliant Pod + Service + HTTPRoute & curl external domain
  echo -e "  ${DIM}Deploying temporary smoke-test Pod, Service & HTTPRoute on http://${MY_HOST}/smoke-test ...${RESET}"
  if kubectl -n "$NS" apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ckad-smoke-pod
  labels:
    app: ckad-smoke
    app.kubernetes.io/managed-by: ckad-smoke-test
spec:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: echo
    image: hashicorp/http-echo:1.0
    args: ["-listen=:8080", "-text=CKAD_SMOKE_OK"]
    ports:
    - containerPort: 8080
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
---
apiVersion: v1
kind: Service
metadata:
  name: ckad-smoke-svc
  labels:
    app.kubernetes.io/managed-by: ckad-smoke-test
spec:
  selector:
    app: ckad-smoke
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ckad-smoke-route
  labels:
    app.kubernetes.io/managed-by: ckad-smoke-test
spec:
  parentRefs:
  - name: lab-gateway
    namespace: lab-ingress
  hostnames:
  - "${MY_HOST}"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /smoke-test
    backendRefs:
    - name: ckad-smoke-svc
      port: 80
EOF
  then
    if kubectl -n "$NS" wait --for=condition=Ready pod/ckad-smoke-pod --timeout=45s >/dev/null 2>&1; then
      record_pass "4. Live Smoke" "Sections 4 & 8: Restricted Pod scheduled & Ready" "pod/ckad-smoke-pod Running"
    else
      record_fail "4. Live Smoke" "Sections 4 & 8: Restricted Pod scheduled & Ready" "Pod did not become Ready within 45s" \
        "Check 'kubectl describe pod ckad-smoke-pod -n ${NS}' and 'kubectl get resourcequota -n ${NS}' for quota or node capacity issues."
    fi

    # Poll external HTTP endpoint for up to 15 seconds to allow Traefik route propagation
    HTTP_OK=false
    HTTP_CODE="000"
    for _ in 1 2 3 4 5; do
      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 "http://${MY_HOST}/smoke-test" 2>/dev/null || echo "000")
      if [[ "$HTTP_CODE" == "200" ]]; then
        HTTP_OK=true
        break
      fi
      sleep 2
    done

    if [[ "$HTTP_OK" == "true" ]]; then
      record_pass "4. Live Smoke" "Section 9: External HTTP routing via ${MY_HOST}" "GET http://${MY_HOST}/smoke-test -> HTTP 200"
    else
      record_fail "4. Live Smoke" "Section 9: External HTTP routing via ${MY_HOST}" "GET http://${MY_HOST}/smoke-test -> HTTP ${HTTP_CODE}" \
        "Check DNS resolution for '${MY_HOST}' (must point to Traefik LB IP), verify 'labctl-gke infra' status, and ensure namespace '${NS}' has label 'labctl-managed=true'."
    fi
  else
    record_fail "4. Live Smoke" "Sections 4, 8, 9: Create Pod/Service/HTTPRoute" "kubectl apply failed in ${NS}" \
      "Verify RBAC permissions in '${NS}' and ensure ValidatingAdmissionPolicies match domain '${DOMAIN}'."
  fi

  cleanup_smoke_resources
fi

# ==============================================================================
# SUMMARY STATUS REPORT & REMEDIATION GUIDANCE
# ==============================================================================
TOTAL=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT))
echo ""
echo -e "${BOLD}==============================================================================${RESET}"
echo -e "${BOLD}  CKAD LAB SMOKE TEST — STATUS REPORT SUMMARY${RESET}"
echo -e "${BOLD}==============================================================================${RESET}"
echo -e "  ${BOLD}User:${RESET}       ${WHOAMI}"
echo -e "  ${BOLD}Namespace:${RESET}  ${NS}"
echo -e "  ${BOLD}Hostname:${RESET}   http://${MY_HOST}"
echo -e "  ${BOLD}Results:${RESET}    ${GREEN}${PASS_COUNT} passed${RESET}, ${YELLOW}${WARN_COUNT} warning(s)${RESET}, ${RED}${FAIL_COUNT} failed${RESET} (out of ${TOTAL} checks)"
echo -e "${BOLD}------------------------------------------------------------------------------${RESET}"

if [[ ${#GUIDANCE_ITEMS[@]} -gt 0 ]]; then
  echo -e "\n${BOLD}🔧 High-Level Remediation Guidance:${RESET}"
  for item in "${GUIDANCE_ITEMS[@]}"; do
    echo -e "  • ${item}"
  done
  echo ""
fi

if [[ "$FAIL_COUNT" -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}✅ READY FOR WORKSHOP: Cluster guardrails are tight and '${WHOAMI}' can complete all CKAD labs (Sections 4–10)!${RESET}"
  exit 0
else
  echo -e "${RED}${BOLD}❌ ACTION REQUIRED: ${FAIL_COUNT} check(s) failed. Review the guidance above before starting the labs.${RESET}"
  exit 1
fi
