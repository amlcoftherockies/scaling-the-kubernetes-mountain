# Section 9: Services, Multi-Port Exposure, Ingress & HTTP Routing

Welcome to Section 9! Together with [Section 4, Module 3 (ClusterIP, NodePort & CoreDNS)](../section%204/README.md#3-module-3-networking-and-service-discovery) and [Section 8, Module 3 (NetworkPolicies)](../section%208/README.md#3-module-3-networkpolicies-for-application-isolation), this standalone lab completes the **CKAD Services and Networking (20%)** domain.

> [!NOTE]
> **Self-Contained Lab:** This section does not depend on resources from earlier sections. You will use your personal `<namespace>.amlcoftherockies.net` hostname to expose live HTTP applications to the internet!

In this section, you will practice:
1.  **Exposing Applications on Multiple & Named Ports**: Understanding `port` vs. `targetPort` (numeric and named container ports) vs. `nodePort`, and building a **Multi-Port Service**.
2.  **Service Types & CoreDNS Service Discovery (`ClusterIP`, `NodePort`, `LoadBalancer`, `ExternalName`)**: Comparing all 4 Kubernetes Service types and testing `ExternalName` DNS CNAME mapping.
3.  **Standard Kubernetes `Ingress` (`networking.k8s.io/v1`)**: Routing internet HTTP traffic to multiple backend services by URL path (`/v1` vs. `/v2`) using `IngressClass: traefik`.
4.  **Modern L7 Routing with the Gateway API (`HTTPRoute`)**: Attaching routes to the shared `Gateway`, routing by HTTP headers (`X-Canary: true`), and performing weighted canary traffic splits (`75%` / `25%`).

---

## 🔌 Module 1: Exposing Applications on Different & Multiple Ports

On the CKAD exam, applications often listen on non-standard ports (like `8080`, `5678`, or `9090`), while clients expect to connect to standard Service ports (like `80`), or a single Pod exposes both an application port and an admin/metrics port.

### 1.1 `port` vs. `targetPort` vs. `nodePort` (and Named Ports)

```text
┌────────────────┐      ┌──────────────────────────────────┐      ┌────────────────────────────────────┐
│                │ :80  │     Service: multi-port-svc      │ ───► │ Container: app-api                 │
│ Cluster Client │ ───► │ • name: web   (80   -> http-api) │      │ containerPort: 8080 (name: http-api│
│                │ :8081│ • name: admin (8081 -> 9090)     │ ───► │ Container: admin-diag              │
└────────────────┘      └──────────────────────────────────┘      │ containerPort: 9090                │
                                                                  └────────────────────────────────────┘
```

*   **`port` (Service Port)**: The virtual TCP/UDP port exposed on the Service's `ClusterIP` (what clients call, e.g., `http://my-svc:80`).
*   **`targetPort` (Container Port)**: The actual port the container process listens on inside the Pod (e.g., `8080`). Can be a **number** (`8080`) or a **named port** (`http-api`) defined in the Pod's `containers[*].ports[*].name`.
    *   *Why use named ports?* If you later change the container's listening port in the Deployment from `8080` to `8443` and keep `name: http-api`, you never have to modify the Service!
*   **`nodePort` (`30000–32767`)**: Only used by `type: NodePort` and `type: LoadBalancer`. Opens a static port on every worker node's network interface.

> [!IMPORTANT]
> **CKAD Multi-Port Rule:** Whenever a Kubernetes `Service` defines **more than one port** in `spec.ports`, **every port entry MUST have a unique `name:` field** (e.g., `name: web`, `name: admin`). Omitting `name` on a multi-port Service causes `kubectl apply` to fail validation!

---

### 1.2 Hands-On: Deploying & Testing a Multi-Port Service

Review [manifests/multi-port-svc.yaml](manifests/multi-port-svc.yaml). It deploys `multi-port-pod` (listening on ports `8080` and `9090`) and `multi-port-svc` (exposing Service port `80 -> http-api` and Service port `8081 -> 9090`).

1.  **Apply the manifest and wait for the Pod:**
    ```bash
    cd "section 9"
    kubectl apply -f manifests/multi-port-svc.yaml
    kubectl wait --for=condition=Ready pod/multi-port-pod --timeout=60s
    ```

2.  **Inspect the Service and its Endpoints:**
    ```bash
    kubectl get svc multi-port-svc
    kubectl describe svc multi-port-svc
    ```
    *Look at the `Endpoints` lines in `describe`: Kubernetes automatically resolved `targetPort: http-api` to `<PodIP>:8080` and `targetPort: 9090` to `<PodIP>:9090`!*

3.  **Call both Service ports (`80` and `8081`):**
    ```bash
    # Port 80 routes to container port 8080 (app-api):
    kubectl exec multi-port-pod -c debug-client -- wget -qO- http://multi-port-svc:80

    # Port 8081 routes to container port 9090 (admin-diag):
    kubectl exec multi-port-pod -c debug-client -- wget -qO- http://multi-port-svc:8081
    ```
    *Output:*
    ```text
    Main Application API (Container Port 8080)
    Admin Diagnostics Endpoint (Container Port 9090)
    ```

---

## 🧭 Module 2: Service Types & CoreDNS Service Discovery

### 2.1 Comparing All Four Kubernetes Service Types

| Service Type | Scope | How It Works |
| :--- | :--- | :--- |
| **`ClusterIP`** *(Default)* | Internal to the cluster | Allocates a stable virtual IP (`10.24.x.x`) and CoreDNS `A` record (`<svc>.<ns>.svc.cluster.local`). |
| **`NodePort`** | Cluster nodes (`30000–32767`) | Builds on `ClusterIP` and opens a static port on every worker node (`<NodeIP>:<NodePort>`). |
| **`LoadBalancer`** | External (L4 Cloud LB) | Builds on `NodePort` and provisions a dedicated cloud load balancer per Service. *(Disabled by quota on our shared cluster in favor of the shared L7 Ingress/Gateway below!)* |
| **`ExternalName`** | DNS Alias (`CNAME`) | Allocates **no IP address** and proxies no traffic. Instead, CoreDNS returns a **`CNAME` record** pointing `<svc>.<ns>.svc.cluster.local` to an external hostname (e.g., a managed cloud database `db.example.com`). |

### 2.2 Hands-On: Creating an `ExternalName` Service & Testing CoreDNS

Suppose your application code is hardcoded to connect to `http://external-payments`, which lives outside your namespace (or outside the cluster at `api.amlcoftherockies.org`).

1.  **Create an `ExternalName` Service imperatively:**
    ```bash
    kubectl create service externalname external-payments --external-name=amlcoftherockies.org
    kubectl get svc external-payments
    ```
    *Notice `TYPE` is `ExternalName`, `CLUSTER-IP` is `<none>`, and `EXTERNAL-IP` shows `amlcoftherockies.org`!*

2.  **Query CoreDNS for the `ExternalName` Service FQDN:**
    ```bash
    NS=$(kubectl config view --minify -o jsonpath='{..namespace}')
    kubectl exec multi-port-pod -c debug-client -- nslookup external-payments.$NS.svc.cluster.local
    ```
    *CoreDNS resolves `external-payments.<ns>.svc.cluster.local` directly via a `CNAME` to `amlcoftherockies.org`!*

---

## 🌐 Module 3: HTTP(S) Routing with Kubernetes `Ingress` (`networking.k8s.io/v1`)

While a `LoadBalancer` Service operates at **Layer 4 (TCP/UDP)** and requires a separate cloud load balancer (and public IP) for every single Service, an **`Ingress`** operates at **Layer 7 (HTTP/HTTPS)**. One shared Ingress Controller (in our cluster, **Traefik** behind `136.80.107.173`) can route traffic for dozens of hostnames and URL paths!

```text
┌────────────────────────────────────┐
│ Internet Client                    │
│ http://<ns>.amlcoftherockies.net   │
└─────────────────┬──────────────────┘
                  │ DNS *.amlcoftherockies.net -> 136.80.107.173
                  ▼
┌────────────────────────────────────┐
│ Shared Traefik Ingress / Gateway   │
│ (namespace: lab-ingress)           │
└────────┬──────────────────┬────────┘
Path: /v1│                  │Path: /v2
         ▼                  ▼
┌───────────────────┐    ┌───────────────────┐
│ Service: v1-svc   │    │ Service: v2-svc   │
│ (:80 -> Pod :5678)│    │ (:80 -> Pod :5678)│
└───────────────────┘    └───────────────────┘
```

### 3.1 Key `Ingress` Concepts for CKAD
1.  **`ingressClassName`**: Tells Kubernetes which Ingress Controller should implement the Ingress. Check the cluster's available classes:
    ```bash
    kubectl get ingressclass
    ```
    *You will see `traefik`.*
2.  **`pathType` (Required on every path!)**:
    *   **`Prefix`**: Matches the URL path prefix split by `/` (e.g., `/v1` matches `/v1`, `/v1/`, and `/v1/users`, but NOT `/v10`).
    *   **`Exact`**: Matches the exact URL path only (`/v1` matches `/v1`, not `/v1/`).

---

### 3.2 Hands-On: Exposing `/v1` and `/v2` on the Internet with `Ingress`

1.  **Deploy the two backend Deployments (`app-v1`, `app-v2`) and Services (`v1-svc`, `v2-svc`):**
    Review and apply [manifests/backends.yaml](manifests/backends.yaml). Notice that the containers listen on port **`5678`**, while `v1-svc` and `v2-svc` expose port **`80`** (`targetPort: 5678`):
    ```bash
    kubectl apply -f manifests/backends.yaml
    kubectl rollout status deployment/app-v1 deployment/app-v2
    ```

2.  **Set your personal workshop hostname and apply [manifests/ingress-paths.yaml](manifests/ingress-paths.yaml):**
    ```bash
    NS=$(kubectl config view --minify -o jsonpath='{..namespace}')
    export MY_HOST="${NS}.amlcoftherockies.net"
    echo "My live hostname is: http://${MY_HOST}"

    sed "s/MY_HOST/${MY_HOST}/g" manifests/ingress-paths.yaml | kubectl apply -f -
    kubectl get ingress app-ingress
    ```

3.  **Test live HTTP path routing from your laptop!**
    ```bash
    curl http://${MY_HOST}/v1
    curl http://${MY_HOST}/v2
    ```
    *Output:*
    ```text
    Served by Backend v1 (Stable)
    Served by Backend v2 (New Release)
    ```

4.  **Delete the `Ingress` before testing the Gateway API in Module 4** (so both don't claim the same hostname at once):
    ```bash
    kubectl delete ingress app-ingress
    ```

---

## 🚀 Module 4: Modern L7 Routing with the Gateway API (`HTTPRoute`)

### 4.1 The Purpose of Gateway API & Key Evolutionary Differences

The **Kubernetes Gateway API** (`gateway.networking.k8s.io/v1`) was built to standardize advanced traffic routing across the Kubernetes ecosystem. It replaces the reliance on custom, vendor-specific `Ingress` annotations with a highly expressive, natively extensible set of Custom Resource Definitions (CRDs).

#### Key Evolutionary Differences from `Ingress`:

1.  **Role-Oriented Architecture**: Gateway API splits configuration across three distinct organizational roles:
    *   **Infrastructure Providers** manage the **`GatewayClass`** (defining the underlying controller/load-balancer implementation, such as `traefik`, `gke-l7-global-external-managed`, or `istio`).
    *   **Cluster Operators / Platform Admins** configure the **`Gateway`** (provisioning shared entry points, listeners, ports, and TLS certificates—like `lab-gateway` in namespace `lab-ingress`).
    *   **Application Developers (You!)** independently define **`HTTPRoute`**, **`GRPCRoute`**, or **`TCPRoute`** resources in their own namespace and attach them to the shared `Gateway` via `parentRefs`.
2.  **Native Expressiveness**: Advanced capabilities like **weighted traffic splitting** for canary deployments, **HTTP header matching/modifications**, query parameter matching, URL rewrites, and **request mirroring** are built directly into the core API spec—removing the need for non-portable vendor annotations (`nginx.ingress.kubernetes.io/...`).
3.  **Multi-Protocol Support**: While `Ingress` is strictly limited to HTTP and HTTPS, Gateway API natively supports a wide range of protocols—including **HTTP/HTTPS (`HTTPRoute`), gRPC (`GRPCRoute`), TCP (`TCPRoute`), UDP (`UDPRoute`), and TLS passthrough (`TLSRoute`)**—providing a unified routing standard for all traffic types.

```text
┌───────────────────────────┐   ┌──────────────────────────────────────────┐
│  ORGANIZATIONAL ROLE      │   │  GATEWAY API RESOURCE                    │
├───────────────────────────┤   ├──────────────────────────────────────────┤
│  Infrastructure Provider  │──►│  GatewayClass (name: traefik)            │
│                           │   └────────────────────┬─────────────────────┘
│                           │                        ▲
│  Cluster Operator / Admin │──►┌────────────────────┴─────────────────────┐
│  (namespace: lab-ingress) │   │  Gateway (name: lab-gateway, port 80/443)│
│                           │   └────────────────────┬─────────────────────┘
│                           │                        ▲ parentRefs
│  Application Developer    │──►┌────────────────────┴─────────────────────┐
│  (your namespace)         │   │  HTTPRoute / GRPCRoute / TCPRoute        │
└───────────────────────────┘   └──────────┬────────────────────┬──────────┘
                                  75% /v1  ▼                    ▼ 25% /v2 (or X-Canary)
                                ┌────────────────────┐ ┌────────────────────┐
                                │  Service: v1-svc   │ │  Service: v2-svc   │
                                └────────────────────┘ └────────────────────┘
```

---

### 4.2 Hands-On: Canary Rollouts (Header Routing & Weighted Traffic Splitting) with `HTTPRoute`

> [!TIP]
> **Why Gateway API Canary Beats Pod-Count Canary:**
> With a standard Kubernetes `Service` (which load-balances evenly across matching Pods), achieving a `95% / 5%` canary split requires running **20 Pods** (`19` stable + `1` canary).
> With **Gateway API `HTTPRoute`**, traffic splitting is controlled by **`backendRefs[*].weight`** at Layer 7 in the Gateway (Traefik). Even with **just 1 Pod** behind `v1-svc` and **1 Pod** behind `v2-svc`, you can split traffic `75% / 25%`, `99% / 1%`, or route internal QA testers via an HTTP header (`X-Canary: true`)—and promote or roll back instantaneously without scaling Pods!

1.  **Inspect the cluster's `GatewayClass` and shared `Gateway`:**
    ```bash
    kubectl get gatewayclass
    kubectl get gateway -n lab-ingress
    ```

2.  **Review and apply [manifests/httproute-advanced.yaml](manifests/httproute-advanced.yaml):**
    It defines two canary rules on your `MY_HOST` hostname:
    *   **Rule 1 (Header-Based Canary)**: Requests carrying HTTP header `X-Canary: true` are routed **100% to `v2-svc`**.
    *   **Rule 2 (Weighted Canary Split)**: All other requests to `/` are split **75% to `v1-svc`** (`weight: 75`) and **25% to `v2-svc`** (`weight: 25`).
    ```yaml
    rules:
    # Rule 1: Header-based Canary (QA / Internal testing -> 100% v2-svc)
    - matches:
      - headers:
        - name: X-Canary
          value: "true"
      backendRefs:
      - name: v2-svc
        port: 80
    # Rule 2: Progressive Weighted Canary (75% v1-svc / 25% v2-svc)
    - matches:
      - path:
          type: PathPrefix
          value: /
      backendRefs:
      - name: v1-svc
        port: 80
        weight: 75
      - name: v2-svc
        port: 80
        weight: 25
    ```
    Apply the `HTTPRoute` on your live workshop hostname:
    ```bash
    sed "s/MY_HOST/${MY_HOST}/g" manifests/httproute-advanced.yaml | kubectl apply -f -
    kubectl get httproute app-httproute
    ```

3.  **Test Weighted Canary Traffic Splitting (`75% v1 / 25% v2`):**
    Send 8 regular HTTP requests from your laptop:
    ```bash
    for i in 1 2 3 4 5 6 7 8; do curl -s http://${MY_HOST}/; done
    ```
    *You will see roughly 6 responses from `Backend v1 (Stable)` and 2 responses from `Backend v2 (New Release)`!*

4.  **Test Header-Based Canary Routing (`X-Canary: true`):**
    Now pass `-H "X-Canary: true"` — every single request is deterministically routed to `Backend v2`:
    ```bash
    for i in 1 2 3 4; do curl -s -H "X-Canary: true" http://${MY_HOST}/; done
    ```
    *All 4 responses return `Served by Backend v2 (New Release)`!*

5.  **Promote the Canary to 100% (`weight: 0` on `v1`, `weight: 100` on `v2`) Live:**
    Once you are confident in `v2`, shift `100%` of production traffic to `v2-svc` (without restarting a single Pod!) by patching the weights on `app-httproute`:
    ```bash
    kubectl patch httproute app-httproute --type='json' \
      -p='[{"op":"replace","path":"/spec/rules/1/backendRefs/0/weight","value":0},{"op":"replace","path":"/spec/rules/1/backendRefs/1/weight","value":100}]'

    # Verify 100% of normal traffic now lands on Backend v2:
    for i in 1 2 3 4; do curl -s http://${MY_HOST}/; done
    ```
    *All 4 regular requests now return `Served by Backend v2 (New Release)`—and if an alert fires, patching the weights back to `100 / 0` gives you an instant, zero-downtime rollback!*

---

## 🧹 Cleaning Up

Clean up all resources created in this section:
```bash
kubectl delete httproute app-httproute --ignore-not-found
kubectl delete ingress app-ingress --ignore-not-found
kubectl delete svc external-payments --ignore-not-found
kubectl delete -f manifests/backends.yaml -f manifests/multi-port-svc.yaml --ignore-not-found
```
