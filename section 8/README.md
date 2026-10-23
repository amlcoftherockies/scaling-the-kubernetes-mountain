# Section 8: Application Security, RBAC & Network Policies

Welcome to Section 8! Together with [Section 5, Module 1 (ConfigMaps, Secrets, Env Vars & Volume Mounts)](../section%205/README.md#1-module-1-decoupling-configuration-configmaps--secrets), this standalone lab completes the **CKAD Application Environment, Configuration and Security (25%)** domain.

> [!NOTE]
> **Self-Contained Lab:** This section does not depend on resources from earlier sections. Everything runs inside your existing workshop namespace with your standard `kubeconfig`.

In this section, you will practice:
1.  **Pod Security Standards (PSS) & PodSecurityPolicies**: Understanding `privileged`, `baseline`, and `restricted` enforcement levels, and inspecting your namespace's active Pod Security Admission labels.
2.  **Pod & Container `SecurityContext`**: Running containers as a non-root user (`runAsNonRoot`, `runAsUser`, `fsGroup`), locking down the root filesystem (`readOnlyRootFilesystem`), dropping Linux capabilities (`drop: ["ALL"]`), and eliminating `PodSecurity` warnings.
3.  **ServiceAccounts & Role-Based Access Control (RBAC)**: Creating `ServiceAccount`s, controlling token auto-mounting (`automountServiceAccountToken`), inspecting `Role`s / `RoleBinding`s, and testing permissions with `kubectl auth can-i`.
4.  **NetworkPolicies for Application Isolation**: Enforcing zero-trust microsegmentation between Pods (`podSelector`, `namespaceSelector`, `ipBlock`, `Ingress` & `Egress` rules).

---

## 🛡️ Module 1: Pod Security Standards (PSS) & `SecurityContext`

### 1.1 From PodSecurityPolicy (PSP) to Pod Security Standards (PSS)

*   **Historical Context (`PodSecurityPolicy`)**: In older Kubernetes versions, cluster admins used `PodSecurityPolicy` objects to restrict Pod privileges. Because PSP had confusing RBAC binding semantics, it was deprecated in Kubernetes 1.21 and **removed in Kubernetes 1.25**.
*   **Modern Standard (`Pod Security Standards` + `Pod Security Admission`)**: Built directly into the Kubernetes API server and configured via simple **labels on a Namespace**:
    *   `pod-security.kubernetes.io/enforce: <level>` — **Rejects** Pods that violate the profile.
    *   `pod-security.kubernetes.io/warn: <level>` — Allows the Pod, but prints a **user-facing warning** in `kubectl`.
    *   `pod-security.kubernetes.io/audit: <level>` — Records an audit log event if violated.

#### The Three Pod Security Standard Levels:

| Profile | Description | Key Restrictions |
| :--- | :--- | :--- |
| **`privileged`** | Unrestricted. | None (used only for trusted system Daemons like CNI plugins or storage drivers). |
| **`baseline`** | Minimally restrictive; prevents known privilege escalations while allowing most default container images to run out-of-the-box. | Blocks `privileged: true`, `hostNetwork`, `hostPID`, `hostIPC`, `hostPath` volumes, and adding dangerous Linux capabilities. |
| **`restricted`** | Heavily hardened following current container security best practices. | Everything in `baseline` **plus**: requires `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, and a `seccompProfile` (`RuntimeDefault` or `Localhost`). |

---

### 1.2 Hands-On: Inspecting Your Namespace's Pod Security Labels

1.  Check the labels on your workshop namespace:
    ```bash
    cd "section 8"
    NS=$(kubectl config view --minify -o jsonpath='{..namespace}')
    kubectl get namespace $NS --show-labels
    ```
    *Look at the labels on your namespace:*
    *   `pod-security.kubernetes.io/enforce=baseline`
    *   `pod-security.kubernetes.io/warn=restricted`
    *That explains why every time you deployed a standard Pod in earlier sections, Kubernetes allowed it (`baseline`) while printing `Warning: would violate PodSecurity "restricted:latest"`!*

2.  **Test the `baseline` Enforcement Guardrail:**
    Try to deploy [manifests/pod-privileged-denied.yaml](manifests/pod-privileged-denied.yaml), which sets `securityContext.privileged: true`:
    ```bash
    kubectl apply -f manifests/pod-privileged-denied.yaml
    ```
    *The API server immediately blocks the Pod:*
    ```text
    Error from server (Forbidden): error when creating "manifests/pod-privileged-denied.yaml": pods "pod-privileged-denied" is forbidden: violates PodSecurity "baseline:latest": privileged (container "app" must not set securityContext.privileged=true)
    ```

---

### 1.3 Hands-On: Hardening a Pod with `SecurityContext` (`restricted` Compliant)

A **`securityContext`** can be defined at two levels in a Pod YAML:
*   **Pod-level (`spec.securityContext`)**: Applies default UID/GID (`runAsUser`, `runAsGroup`, `runAsNonRoot`), Seccomp profile, and volume group ownership (`fsGroup`) across all containers in the Pod.
*   **Container-level (`spec.containers[*].securityContext`)**: Applies container-specific settings like `allowPrivilegeEscalation`, `readOnlyRootFilesystem`, and Linux `capabilities` (overrides Pod-level settings if both set `runAsUser`).

1.  Review and apply [manifests/pod-securitycontext.yaml](manifests/pod-securitycontext.yaml):
    ```bash
    kubectl apply -f manifests/pod-securitycontext.yaml
    ```
    *Notice there is **zero `PodSecurity` warning**! Because `pod-hardened` sets `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, and `seccompProfile.type: RuntimeDefault`, it passes `restricted:latest` cleanly.*

2.  **Verify the non-root UID, GID, and `fsGroup` inside the container:**
    ```bash
    kubectl wait --for=condition=Ready pod/pod-hardened --timeout=60s
    kubectl exec pod-hardened -- id
    ```
    *Output:* `uid=65532(65532) gid=65532(65532) groups=65532(65532),2000`
    *(Notice supplemental group `2000` from `fsGroup: 2000`!)*

3.  **Verify `readOnlyRootFilesystem: true` vs. Mounted Volume:**
    Try writing a file to `/tmp` on the root filesystem vs. `/data` (an `emptyDir` volume owned by `fsGroup: 2000`):
    ```bash
    # 1. Writing to the root filesystem fails (Read-only file system!):
    kubectl exec pod-hardened -- touch /tmp/hack.sh

    # 2. Reading & writing to the mounted /data volume works:
    kubectl exec pod-hardened -- cat /data/status.txt
    kubectl exec pod-hardened -- ls -ln /data/status.txt
    ```
    *Look at the group column of `ls -ln`: the file is owned by UID `65532` and GID **`2000`** (`fsGroup`)!*

---

## 🔑 Module 2: ServiceAccounts & Role-Based Access Control (RBAC)

In Kubernetes, human users and automated processes authenticate differently, but both are authorized using **RBAC**.

### 2.1 How RBAC Works (`Role`, `ClusterRole`, `RoleBinding`, `ClusterRoleBinding`)

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ SUBJECT (Who)          ServiceAccount  |  User  |  Group                │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │ bound via
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ BINDING (Where)        RoleBinding (Single Namespace)                   │
│                        or ClusterRoleBinding (Cluster-Wide)             │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │ references
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ ROLE (What Rules)      Role (Namespaced rules)                          │
│                        or ClusterRole (Reusable / Cluster-scoped rules) │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │ grants
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ API RESOURCES & VERBS  Resources: pods, secrets, deployments, ...       │
│                        Verbs:     get, list, watch, create, delete, ... │
└─────────────────────────────────────────────────────────────────────────┘
```

| Object | Scope | Purpose |
| :--- | :--- | :--- |
| **`ServiceAccount`** | Namespaced | An identity for Pods/processes running inside a namespace. Every namespace has a `default` ServiceAccount, or you can create dedicated ones per application. |
| **`Role`** | Namespaced | Defines a set of allowed **verbs** (`get`, `list`, `watch`, `create`, `delete`) on **resources** (`pods`, `configmaps`, `secrets`) within a single namespace. |
| **`ClusterRole`** | Cluster-scoped | Defines allowed verbs on cluster-scoped resources (`nodes`, `persistentvolumes`) **OR** acts as a reusable template (like the built-in `view`, `edit`, and `admin` ClusterRoles) that can be bound inside individual namespaces. |
| **`RoleBinding`** | Namespaced | Grants the permissions of a `Role` (or a `ClusterRole`) to a `ServiceAccount`/User **within that namespace only**. |
| **`ClusterRoleBinding`** | Cluster-scoped | Grants the permissions of a `ClusterRole` across the **entire cluster**. |

---

### 2.2 Built-In RBAC Privilege Escalation Prevention (Why You Can Create `Role`s Safely!)

In our multi-tenant workshop cluster, you are allowed to create **`Role`s** and **`RoleBinding`s** inside your own namespace—yet you cannot use that power to grant yourself (or a Pod) extra permissions! How does Kubernetes prevent you from creating a `Role` with `verbs: ["*"]` on `resources: ["*"]`?

> [!IMPORTANT]
> **How Kubernetes RBAC Privilege Escalation Prevention Works:**
> The Kubernetes API server enforces a strict rule whenever anyone creates or updates a `Role` or `RoleBinding`:
> 1. **Rule-by-Rule Subset Check (`escalate` guard):** You can **only** create or update a `Role` if **you already hold every single permission (API group, resource, and verb)** listed in that `Role` within that scope.
> 2. **Binding Check (`bind` guard):** You can **only** create a `RoleBinding` referencing a `Role`/`ClusterRole` if you already hold all the permissions contained in that referenced role.
> 3. **Namespace Isolation:** Because `Role` and `RoleBinding` are strictly namespaced objects (and you cannot create cluster-wide `ClusterRole`s or `ClusterRoleBinding`s), any permissions you grant to a `ServiceAccount` apply **only inside your namespace**.
>
> This means you can safely practice creating least-privilege `ServiceAccount`s, `Role`s, and `RoleBinding`s for your applications (or AI agents / MCP servers!), and if you ever try to include a permission you don't own (such as modifying `ResourceQuota`s), the API server immediately blocks it with:
> `Forbidden: user ... is attempting to grant RBAC permissions not currently held`.

---

### 2.3 Hands-On: Auditing Permissions, Creating `Role`s & `RoleBinding`s, and Calling the K8s API with a `ServiceAccount` Token

1.  **Inspect the `ServiceAccount`s in your workshop namespace:**
    ```bash
    kubectl get serviceaccounts
    ```
    *You will see `default` (automatically created in every namespace) and `workshop-user` (the ServiceAccount backing your workshop `kubeconfig`).*

2.  **Test your own RBAC permissions using `kubectl auth can-i` (a huge CKAD time-saver!):**
    ```bash
    kubectl auth can-i create deployments        # yes (allowed in your namespace)
    kubectl auth can-i get nodes                 # yes (read-only cluster role)
    kubectl auth can-i delete nodes              # no  (cluster-admin only)
    kubectl auth can-i create roles              # yes (allowed in your namespace, guarded against escalation!)
    kubectl auth can-i create clusterroles       # no  (cluster-scoped RBAC is forbidden)
    kubectl auth can-i list secrets              # yes (allowed inside your namespace)
    kubectl auth can-i list secrets -n default   # no  (isolated from other namespaces!)
    ```

3.  **Test RBAC Privilege Escalation Prevention in Action:**
    Try creating a `Role` that grants permission to `delete` `resourcequotas` (a permission you do **not** hold):
    ```bash
    kubectl create role sneaky-admin --verb=delete --resource=resourcequotas
    ```
    *Observe the API server catches the escalation attempt and rejects it with `Error from server (Forbidden): roles.rbac.authorization.k8s.io "sneaky-admin" is forbidden: user ... is attempting to grant RBAC permissions not currently held`!*

4.  **Create a `ServiceAccount`, `Role`, and `RoleBinding` Imperatively (CKAD Exam Skill):**
    On the CKAD exam, never type RBAC YAML by hand—use `kubectl create` (and add `--dry-run=client -o yaml` whenever you want to inspect the generated manifest):
    ```bash
    NS=$(kubectl config view --minify -o jsonpath='{..namespace}')

    # 1. Create a dedicated ServiceAccount for a Pod that needs to read Pods
    kubectl create serviceaccount pod-inspector-sa

    # 2. Create a Role that ONLY allows get, list, watch on pods and pods/log
    kubectl create role pod-reader \
      --verb=get,list,watch \
      --resource=pods,pods/log

    # 3. Bind the pod-reader Role to pod-inspector-sa in your namespace
    kubectl create rolebinding pod-reader-binding \
      --role=pod-reader \
      --serviceaccount=$NS:pod-inspector-sa

    # 4. Verify the ServiceAccount's exact permissions using --as!
    kubectl auth can-i list pods --as=system:serviceaccount:$NS:pod-inspector-sa       # yes!
    kubectl auth can-i delete pods --as=system:serviceaccount:$NS:pod-inspector-sa     # no! (read-only)
    kubectl auth can-i list secrets --as=system:serviceaccount:$NS:pod-inspector-sa    # no! (pods only)
    ```

5.  **Call the Kubernetes API Directly from Inside a Pod Using a Mounted `ServiceAccount` Token:**
    When a Pod runs with a `ServiceAccount` (unless `automountServiceAccountToken: false` is set), the `kubelet` automatically mounts three files into `/var/run/secrets/kubernetes.io/serviceaccount/`:
    *   `token`: A signed, time-bound JWT bearer token identifying the `ServiceAccount`.
    *   `ca.crt`: The cluster's public Certificate Authority bundle (to verify `https://kubernetes.default.svc`).
    *   `namespace`: The Pod's current namespace name.

    Let's launch a Pod running as `pod-inspector-sa` and use its mounted token to query the Kubernetes API server over HTTPS:
    ```bash
    # Launch a curl pod using our pod-inspector-sa ServiceAccount
    kubectl run api-explorer \
      --image=curlimages/curl:8.7.1 \
      --overrides='{"spec":{"serviceAccountName":"pod-inspector-sa"}}' \
      -- sleep 3600
    kubectl wait --for=condition=Ready pod/api-explorer --timeout=60s

    # 1. Inspect the auto-mounted ServiceAccount files inside the container:
    kubectl exec api-explorer -- ls -la /var/run/secrets/kubernetes.io/serviceaccount

    # 2. Query the Kubernetes API for Pods in your namespace (ALLOWED by pod-reader Role -> 200 OK!):
    kubectl exec api-explorer -- sh -c '
      TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
      CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
      curl -s --cacert $CACERT -H "Authorization: Bearer $TOKEN" \
        https://kubernetes.default.svc/api/v1/namespaces/$NS/pods
    ' | head -n 25

    # 3. Try querying Secrets with the same token (DENIED by RBAC -> 403 Forbidden!):
    kubectl exec api-explorer -- sh -c '
      TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
      CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
      curl -sS --cacert $CACERT -H "Authorization: Bearer $TOKEN" \
        https://kubernetes.default.svc/api/v1/namespaces/$NS/secrets
    '
    ```
    *Notice how querying `/pods` returns the live `PodList` JSON from the API server, while querying `/secrets` returns `"status": "Failure", "reason": "Forbidden", "code": 403` because `pod-reader` only grants access to `pods`!*

6.  **Opt Out of Token Mounting (`automountServiceAccountToken: false`):**
    If your application **doesn't** need to call the Kubernetes API (which is true for 95% of web apps and microservices!), best practice—and a classic CKAD exam task—is to set **`automountServiceAccountToken: false`** on the `ServiceAccount` or `Pod` spec so a compromised container cannot steal a Kubernetes API token:
    ```bash
    kubectl apply -f manifests/serviceaccount-pod.yaml
    kubectl wait --for=condition=Ready pod/pod-custom-sa --timeout=60s

    # Verify the Pod uses app-runner-sa and that NO token volume was mounted:
    kubectl get pod pod-custom-sa -o jsonpath='{.spec.serviceAccountName}'; echo ""
    kubectl exec pod-custom-sa -- ls /var/run/secrets/kubernetes.io/serviceaccount
    ```
    *The `ls` command returns `No such file or directory` because `automountServiceAccountToken: false` prevented mounting credentials into the container!*

---

## 🔒 Module 3: NetworkPolicies for Application Isolation

By default in Kubernetes, **all Pods can talk to all other Pods** unless restricted by a **`NetworkPolicy`**.
*   The moment a `NetworkPolicy` selects a Pod (via `spec.podSelector`), that Pod becomes **isolated** for the listed `policyTypes` (`Ingress` and/or `Egress`): **all traffic not explicitly allowed by a matching rule is dropped!**
*   Rules can match peers using three selectors:
    1.  **`podSelector`**: Matches Pods by label in the same namespace.
    2.  **`namespaceSelector`**: Matches Pods in namespaces carrying a specific label.
    3.  **`ipBlock`**: Matches external CIDR ranges (e.g., `10.0.0.0/8`).

```text
┌────────────────────────┐                        ┌─────────────────────────┐
│  Pod: frontend-client  │ ═══ ALLOWED (80/TCP) ═►│   Service: backend-svc  │
│  (label: role=frontend)│                        │   (app=backend-api)     │
└────────────────────────┘                        └─────────────────────────┘
                                                               ▲
┌────────────────────────┐                                     │
│  Pod: intruder-client  │ ─── DROPPED by Egress NetworkPolicy ╳
│ (label: role=untrusted)│     (restrict-intruder-egress)
└────────────────────────┘
```

> [!NOTE]
> **Why `NetworkPolicy` Rules Are Additive:**
> If two `NetworkPolicy` objects select the same Pod, Kubernetes combines their rules as a **union (`OR`)**. In our shared workshop cluster, every namespace already has a baseline **Ingress** `NetworkPolicy` (`labctl-isolate-namespace`) that allows pods within your namespace to accept incoming connections from each other while blocking other students' namespaces.
> Because `labctl-isolate-namespace` only sets `policyTypes: [Ingress]`, we can lock down intra-namespace traffic without touching the workshop's baseline policy by applying an **`Egress` `NetworkPolicy`**!

---

### 3.1 Hands-On: Locking Down Pod Traffic with an Egress `NetworkPolicy`

1.  **Inspect the workshop's existing baseline `NetworkPolicy` in your namespace:**
    ```bash
    kubectl get networkpolicy
    kubectl describe networkpolicy labctl-isolate-namespace
    ```
    *Notice it selects `<none>` (all Pods in your namespace) for `Policy Types: Ingress`, isolating your namespace from other students while allowing traffic from `lab-ingress` (Traefik).*

2.  **Deploy the 3 test Pods (`backend-api`, `frontend-client`, `intruder-client`) and `backend-svc`:**
    ```bash
    kubectl apply -f manifests/netpol-setup.yaml
    kubectl wait --for=condition=Ready pod/backend-api pod/frontend-client pod/intruder-client --timeout=60s
    ```

3.  **Test Connectivity BEFORE Applying Our `NetworkPolicy`:**
    Verify that both `frontend-client` and `intruder-client` can reach `backend-svc`:
    ```bash
    kubectl exec frontend-client -- wget -qO- --timeout=3 http://backend-svc
    kubectl exec intruder-client -- wget -qO- --timeout=3 http://backend-svc
    ```
    *Both print `CONFIDENTIAL: Backend API Data`!*

4.  **Apply the Egress `NetworkPolicy` ([manifests/networkpolicy.yaml](manifests/networkpolicy.yaml)):**
    Review [manifests/networkpolicy.yaml](manifests/networkpolicy.yaml)—it targets `role: untrusted` (`intruder-client`) with `policyTypes: [Egress]`, allowing only DNS (`port 53`) and connections to `app: public-api` (blocking connections to `backend-api`!):
    ```bash
    kubectl apply -f manifests/networkpolicy.yaml
    kubectl describe networkpolicy restrict-intruder-egress
    ```

5.  **Test Connectivity AFTER Applying the `NetworkPolicy`:**
    ```bash
    # 1. Authorized frontend (role=frontend) SUCCEEDS immediately:
    kubectl exec frontend-client -- wget -qO- --timeout=3 http://backend-svc

    # 2. Restricted pod (role=untrusted) IS BLOCKED (times out after 3s):
    kubectl exec intruder-client -- wget -qO- --timeout=3 http://backend-svc
    ```
    *`frontend-client` returns `CONFIDENTIAL: Backend API Data`, while `intruder-client` is dropped by the CNI firewall (`wget: download timed out`)!*

> [!IMPORTANT]
> **CKAD `NetworkPolicy` Pitfall (`AND` vs. `OR` in YAML lists):**
> In `ingress[*].from`:
> ```yaml
> # ONE list item with two keys = Logical AND (Pod in namespace X WITH label Y)
> from:
> - namespaceSelector:
>     matchLabels: {env: prod}
>   podSelector:
>     matchLabels: {role: frontend}
>
> # TWO separate list items ('-') = Logical OR (Any Pod in namespace X OR any Pod in current namespace with label Y)
> from:
> - namespaceSelector:
>     matchLabels: {env: prod}
> - podSelector:
>     matchLabels: {role: frontend}
> ```
> A single hyphen `-` can completely change the meaning of a NetworkPolicy on the exam!

---

## ⚖️ Module 4: Resource Requests, Limits, `LimitRange`, `ResourceQuota` & How `kube-scheduler` Places Pods

To prevent a single runaway container from starving an entire node (or a single namespace from consuming the whole cluster), Kubernetes provides three layers of resource governance—and uses **`resources.requests`** as the foundation for all scheduling decisions:

| Mechanism | Scope | What It Does |
| :--- | :--- | :--- |
| **`resources.requests` & `limits`** | Per Container (`Pod` spec) | • **`requests`**: Minimum CPU/Memory reserved for the container; used by **`kube-scheduler`** to pick a node with enough free `Allocatable` capacity.<br>• **`limits`**: Hard ceiling enforced by the Linux kernel (**cgroups**). Exceeding CPU limit -> **CPU throttling**; exceeding Memory limit -> **`OOMKilled` (Exit Code 137)**! |
| **`LimitRange`** | Namespace | Injects **`defaultRequest`** and **`default`** limits into any container that omits `resources`, and enforces per-container `min`/`max` bounds. |
| **`ResourceQuota`** | Namespace | Caps the **aggregate sum** of CPU requests/limits, memory requests/limits, PVCs, Services, and Pod counts across all Pods in the namespace. |

---

### 4.1 How `kube-scheduler` Makes Scheduling Decisions (`Filter` -> `Score` -> `Bind`)

A very common misconception is that `kube-scheduler` checks a node's live CPU/Memory usage (`kubectl top nodes`) before placing a Pod. **It does NOT!**

Instead, `kube-scheduler` treats every node like a reservation ledger based strictly on **`resources.requests`**:

```text
┌───────────────────────────────────────────────────────────────────────────┐
│ Newly Created Pod (spec.nodeName == "")                                   │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: FILTERING (Predicates — Which nodes CAN run this Pod?)           │
│   • Resource Requests: Node Allocatable >= Sum(Existing Pod Requests)     │
│                        + New Pod's resources.requests                     │
│   • Node Selectors / Node Affinity: Does node have required labels?       │
│   • Taints & Tolerations: Does Pod tolerate the node's taints?            │
│   • Volume Topology: Is node in the same zone as the Pod's PVC disk?      │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│ PHASE 2: SCORING (Priorities — Which surviving node is BEST?)             │
│   • Ranks candidate nodes (e.g., spreading Pods across zones/nodes,       │
│     least-requested capacity, or whether the container image is cached).  │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│ PHASE 3: BINDING (Or FailedScheduling -> Cluster Autoscaler!)             │
│   • Winner found   ──► Sets Pod's spec.nodeName; target kubelet starts it │
│   • 0 nodes match  ──► Pod stays "Pending" (FailedScheduling event)       │
│                        ──► Cluster Autoscaler sees Pending Pod & adds VM! │
└───────────────────────────────────────────────────────────────────────────┘
```

> [!IMPORTANT]
> **Why Accurate `requests` Matter in Production (and AI/ML GPU Clusters):**
> *   **Under-requesting (`requests` too low):** `kube-scheduler` packs too many Pods onto one node because the reservation ledger looks empty. Under real load, the node runs out of physical RAM and the Linux kernel **OOMKills** containers (`Exit Code 137`) or throttles CPU!
> *   **Over-requesting (`requests` too high):** `kube-scheduler` thinks nodes are "full" (`Allocated Requests = 95%`) even when actual CPU usage in `kubectl top nodes` is only `5%`—wasting cloud VMs and triggering unnecessary Cluster Autoscaler scale-ups!

---

### 4.2 Hands-On: Inspecting the Node Reservation Ledger, `LimitRange`, `ResourceQuota`, and Scheduling Constraints

1.  **Inspect a Worker Node's Reservation Ledger (`Capacity` vs. `Allocatable` vs. `Allocated resources`):**
    Pick one of the cluster's worker nodes and inspect how `kube-scheduler` views its capacity:
    ```bash
    NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
    kubectl describe node $NODE | grep -A 18 "Allocated resources:"
    ```
    *Look closely at the `Allocated resources:` table at the bottom of `kubectl describe node`:*
    *   **`Requests` column**: The exact sum of `resources.requests` of all Pods currently scheduled on that node. **If `New Pod Request + Allocated Requests > Node Allocatable`, `kube-scheduler` will NOT place the Pod on this node!**
    *   **`Limits` column**: Can exceed `100%` (overcommitment), because not every Pod bursts to its ceiling at the exact same millisecond.

2.  **Inspect Node Labels & Taints (Why Normal Pods Never Land on the `gvisor` Node!):**
    In Phase 1 (`Filtering`), `kube-scheduler` checks **Node Labels** (`nodeSelector` / `nodeAffinity`) and **Node Taints** (`tolerations`):
    ```bash
    # View node labels (machine type, zone, OS, and sandbox runtime):
    kubectl get nodes --show-labels

    # Inspect the Taint on our gVisor node:
    kubectl describe node -l sandbox.gke.io/runtime=gvisor | grep -E "Name:|Taints:"
    ```
    *Notice `Taints: sandbox.gke.io/runtime=gvisor:NoSchedule`! That `NoSchedule` taint repels all ordinary Pods so general workloads don't accidentally consume the sandbox node pool (or expensive GPU nodes like `nvidia.com/gpu=present:NoSchedule`). Only Pods with a matching **toleration** and **nodeSelector** are scheduled there!*

3.  **Inspect the active `LimitRange` and `ResourceQuota` in your namespace:**
    ```bash
    kubectl describe limitrange workshop-defaults
    kubectl describe resourcequota workshop-quota
    ```
    *Notice how `workshop-defaults` automatically injects `defaultRequest: cpu=50m, memory=64Mi` and `default: cpu=200m, memory=256Mi` whenever you deploy a Pod without a `resources:` block, and enforces `max: cpu=1, memory=2Gi` per container!*

4.  **Deploy a Pod with explicit CPU and Memory `requests` and `limits` ([manifests/pod-resources.yaml](manifests/pod-resources.yaml)):**
    ```bash
    kubectl apply -f manifests/pod-resources.yaml
    kubectl wait --for=condition=Ready pod/pod-resources-demo --timeout=60s

    # Check the QoS Class assigned by Kubernetes (Burstable vs Guaranteed vs BestEffort) and which node it landed on:
    kubectl get pod pod-resources-demo -o jsonpath='Node={.spec.nodeName} QoS={.status.qosClass} Requests={.spec.containers[0].resources.requests} Limits={.spec.containers[0].resources.limits}'; echo ""

    # Check how your namespace ResourceQuota usage ("Used" column) increased:
    kubectl describe resourcequota workshop-quota
    ```
    *Because `requests` (`100m` / `128Mi`) are lower than `limits` (`250m` / `256Mi`), Kubernetes assigns `qosClass: Burstable` (if `requests == limits` for both CPU and memory, it becomes `Guaranteed`).*

5.  **Test What Happens When a Pod Cannot Be Scheduled (`Pending` + `FailedScheduling` Event):**
    Let's deploy a Pod with a `nodeSelector` (`disktype=nvme-ultra`) that no node in the cluster has, and see how `kube-scheduler` records its scheduling decision:
    ```bash
    kubectl run unschedulable-demo --image=docker.io/library/busybox:1.36 \
      --overrides='{"spec":{"nodeSelector":{"disktype":"nvme-ultra"}}}' \
      -- sleep 3600

    # Check the Pod status (it stays Pending!):
    kubectl get pod unschedulable-demo

    # Inspect the FailedScheduling event from default-scheduler:
    kubectl describe pod unschedulable-demo | tail -n 10
    ```
    *Look at the `Events:` output from `default-scheduler`:*
    `Warning  FailedScheduling  ...  0/4 nodes are available: 1 node(s) had untolerated taint {sandbox.gke.io/runtime: gvisor}, 3 node(s) didn't match Pod's node affinity/selector.`
    *Delete the unschedulable test pod:*
    ```bash
    kubectl delete pod unschedulable-demo
    ```

6.  **Test What Happens When a Pod Exceeds `LimitRange` / `ResourceQuota`:**
    Try creating a Pod that requests `8` CPUs and `16Gi` of RAM (exceeding both `LimitRange` `max` and `ResourceQuota`):
    ```bash
    kubectl run quota-buster --image=busybox:1.36 \
      --overrides='{"spec":{"containers":[{"name":"quota-buster","image":"busybox:1.36","command":["sleep","60"],"resources":{"requests":{"cpu":"8","memory":"16Gi"},"limits":{"cpu":"8","memory":"16Gi"}}}]}}'
    ```
    *Before `kube-scheduler` even sees the Pod, the API server's admission controller immediately rejects it:*
    ```text
    Error from server (Forbidden): pods "quota-buster" is forbidden: [maximum cpu usage per Container is 1, but limit is 8, maximum memory usage per Container is 2Gi, but limit is 16Gi]
    ```

---

## 🧹 Cleaning Up

Clean up all resources created in this section:
```bash
kubectl delete -f manifests/pod-resources.yaml -f manifests/networkpolicy.yaml -f manifests/netpol-setup.yaml -f manifests/serviceaccount-pod.yaml -f manifests/pod-securitycontext.yaml --ignore-not-found
kubectl delete pod api-explorer --ignore-not-found
kubectl delete rolebinding pod-reader-binding --ignore-not-found
kubectl delete role pod-reader --ignore-not-found
kubectl delete serviceaccount pod-inspector-sa --ignore-not-found
```
