# Section 10: Packaging with Helm, Kustomize & Extending Kubernetes (CRDs & Operators)

Welcome to Section 10! This standalone lab completes the remaining **CKAD Application Deployment (20%)** and **Application Environment (25%)** topics: **Helm package management**, **Kustomize overlays (`kubectl apply -k`)**, and **discovering and using CustomResourceDefinitions (CRDs) & Operators**.

> [!NOTE]
> **Self-Contained Lab:** All exercises run inside your own workshop namespace with zero cluster-admin privileges required.

In this section, you will practice:
1.  **Helm (The Kubernetes Package Manager)**: Adding a Helm repository, inspecting chart `values.yaml`, installing a real CNCF microservice (**`podinfo`**) into your namespace, exposing it on your live `<namespace>.amlcoftherockies.net` hostname, upgrading values (`helm upgrade`), and rolling back (`helm rollback`).
2.  **Kustomize (`kubectl kustomize` & `kubectl apply -k`)**: Managing a real multi-environment application (`base/` + `overlays/dev` and `overlays/prod`) using `namePrefix`, `labels`, `replicas`, `configMapGenerator` (with content-hash suffixes), and strategic-merge patches—without duplicating YAML templates!
3.  **Extending Kubernetes with CRDs & Operators**: Understanding how the **Operator Pattern** (`CRD` + `Custom Resource` + `Controller`) works, discovering installed CRDs (`kubectl api-resources`, `kubectl get crd`, `kubectl explain`), and deploying a live **Custom Resource (`CR`)** in your namespace.

---

## ⎈ Module 1: Using the Helm Package Manager

Real-world Kubernetes applications (like Redis, PostgreSQL, Prometheus, or multi-tier microservices) consist of dozens of interdependent YAML manifests. **Helm** packages those manifests into a versioned **Chart** where environment-specific settings are injected from a **`values.yaml`** file into Go templates (`templates/*.yaml`).

*   **How Helm 3 works inside a single namespace:** Helm v3 has **no server-side daemon** (unlike legacy Helm v2's `Tiller`). It uses your existing `KUBECONFIG` and stores release history as regular Kubernetes Secrets (`type: helm.sh/release.v1`) right inside your namespace!

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. HELM REPO / OCI REGISTRY: Chart (templates/ + default values.yaml)   │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 2. HELM CLI: helm install / upgrade -f helm/podinfo-values.yaml         │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │ Renders YAML & applies via KUBECONFIG
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 3. YOUR NAMESPACE:                                                      │
│    • Deployment & Service resources                                     │
│    • Release history Secret (sh.helm.release.v1.my-podinfo.v1)          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

### 1.1 Install the `helm` CLI (if not already installed)
*   **macOS:** `brew install helm`
*   **Windows:** `winget install Helm.Helm`
*   **Linux:** `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`

Verify it: `helm version`

---

### 1.2 Hands-On: Installing, Upgrading & Rolling Back **`podinfo`** with Helm

[**`podinfo`**](https://github.com/stefanprodan/podinfo) is a real CNCF microservice reference application used across the Kubernetes ecosystem to test Helm, Kustomize, GitOps, and service meshes.

1.  **Add the `podinfo` Helm repository and search available versions:**
    ```bash
    cd "section 10"
    helm repo add podinfo https://stefanprodan.github.io/podinfo
    helm repo update
    helm search repo podinfo
    ```

2.  **Inspect the chart's configurable values (`helm show values` — CKAD Essential!):**
    Before installing any chart on the CKAD exam, inspect its default `values.yaml` so you know the exact keys to override:
    ```bash
    helm show values podinfo/podinfo | head -n 35
    ```

3.  **Install `podinfo` into your namespace using [helm/podinfo-values.yaml](helm/podinfo-values.yaml):**
    Review [helm/podinfo-values.yaml](helm/podinfo-values.yaml). It sets `replicaCount: 2`, customizes `ui.message` and `ui.color`, and sets `serviceAccount.enabled: false`.
    ```bash
    helm install my-podinfo podinfo/podinfo -f helm/podinfo-values.yaml
    ```

4.  **Verify the Helm release and the Kubernetes resources it created:**
    ```bash
    helm list
    kubectl get deploy,pods,svc -l app.kubernetes.io/name=my-podinfo
    kubectl get secrets -l owner=helm
    ```
    *Notice the `sh.helm.release.v1.my-podinfo.v1` Secret—that's where Helm stores Revision 1's state!*

5.  **Upgrade the Release with `--set` (Revision 2) and Expose It on Your Live Domain:**
    You can override individual keys on the command line with `--set` (or `--reuse-values` to keep your previous overrides). Let's update `ui.message`, scale to `1` replica, and enable its built-in `Ingress` on your `<namespace>.amlcoftherockies.net` hostname:
    ```bash
    NS=$(kubectl config view --minify -o jsonpath='{..namespace}')
    export MY_HOST="${NS}.amlcoftherockies.net"

    helm upgrade my-podinfo podinfo/podinfo \
      -f helm/podinfo-values.yaml \
      --set replicaCount=1 \
      --set ui.message="Upgraded to Revision 2!" \
      --set ingress.enabled=true \
      --set ingress.className=traefik \
      --set "ingress.hosts[0].host=${MY_HOST}" \
      --set "ingress.hosts[0].paths[0].path=/" \
      --set "ingress.hosts[0].paths[0].pathType=Prefix"

    kubectl rollout status deployment/my-podinfo
    ```

6.  **Test your live Helm-deployed microservice from your laptop (or browser!):**
    ```bash
    curl -s http://${MY_HOST}/ | grep -E "hostname|message|version"
    ```
    *You will see `"message": "Upgraded to Revision 2!"` served live from `my-podinfo`!* (You can also open `http://${MY_HOST}` in your web browser to see the `podinfo` UI!).

7.  **Inspect Release History & Roll Back to Revision 1:**
    ```bash
    helm history my-podinfo
    helm rollback my-podinfo 1
    helm history my-podinfo
    ```
    *Notice rolling back to Revision `1` creates **Revision `3`**! Clean up the release when done:*
    ```bash
    helm uninstall my-podinfo
    ```

---

## 🧩 Module 2: Template-Free Configuration with Kustomize (`kubectl apply -k`)

Unlike Helm (which uses Go `{{ .Values.foo }}` templates), **Kustomize** is built directly into `kubectl` (`kubectl kustomize` and `kubectl apply -k`) and works on **plain, valid Kubernetes YAML** using a **`base/` + `overlays/`** directory structure:

```text
              ┌────────────────────────────────────────────┐
              │              kustomize/base/               │
              │  • kustomization.yaml                      │
              │  • deployment.yaml & service.yaml          │
              │  • configMapGenerator                      │
              └───────────┬────────────────────┬───────────┘
                          │                    │
                          ▼                    ▼
┌───────────────────────────────────┐  ┌───────────────────────────────────┐
│      kustomize/overlays/dev/      │  │     kustomize/overlays/prod/      │
│  • namePrefix: dev-               │  │  • namePrefix: prod-              │
│  • replicas: 1                    │  │  • replicas: 3                    │
│  • LOG_LEVEL=debug                │  │  • LOG_LEVEL=warn                 │
│                                   │  │  • patch-resources.yaml           │
└───────────────────────────────────┘  └───────────────────────────────────┘
```

### 2.1 Why Kustomize's `configMapGenerator` is Magic
In normal Kubernetes, if you edit a `ConfigMap` that a `Deployment` consumes via `envFrom`, **the Pods do NOT automatically restart**.
When you use **`configMapGenerator`** in `kustomization.yaml`, Kustomize appends a **10-character content hash** to the ConfigMap name (e.g., `dev-storefront-config-8g9m2k4b7t`) and automatically updates the Deployment's `configMapRef` to match! Whenever a config value changes, the hash changes, which automatically triggers a **zero-downtime Rolling Update** of your Deployment!

---

### 2.2 Hands-On: Previewing & Deploying `dev` and `prod` Overlays

1.  **Inspect the directory structure in `kustomize/`:**
    *   [kustomize/base/kustomization.yaml](kustomize/base/kustomization.yaml): Defines the shared `storefront` Deployment, Service, and base `configMapGenerator`.
    *   [kustomize/overlays/dev/kustomization.yaml](kustomize/overlays/dev/kustomization.yaml): Adds `namePrefix: dev-`, `environment: dev`, `replicas: 1`, and merges `LOG_LEVEL="debug"`.
    *   [kustomize/overlays/prod/kustomization.yaml](kustomize/overlays/prod/kustomization.yaml): Adds `namePrefix: prod-`, `environment: prod`, `replicas: 3`, merges `LOG_LEVEL="warn"`, and applies [patch-resources.yaml](kustomize/overlays/prod/patch-resources.yaml).

2.  **Preview the rendered YAML using `kubectl kustomize` (without applying yet):**
    ```bash
    kubectl kustomize kustomize/overlays/dev
    kubectl kustomize kustomize/overlays/prod
    ```
    *Compare the two outputs: notice how `name: dev-storefront` vs `name: prod-storefront`, the hashed ConfigMap names, replica counts (`1` vs `3`), and the `resources:` patch in `prod` were all generated without a single template variable!*

3.  **Deploy BOTH environments side-by-side in your namespace using `kubectl apply -k`:**
    ```bash
    kubectl apply -k kustomize/overlays/dev
    kubectl apply -k kustomize/overlays/prod
    kubectl rollout status deployment/dev-storefront deployment/prod-storefront
    ```

4.  **Verify the deployed resources and injected environment variables:**
    ```bash
    kubectl get deploy,svc,cm -l app=storefront
    kubectl exec deploy/dev-storefront -- env | grep -E "APP_TITLE|LOG_LEVEL|FEATURE_BANNER"
    kubectl exec deploy/prod-storefront -- env | grep -E "APP_TITLE|LOG_LEVEL|FEATURE_BANNER"
    ```
    *Output from `dev-storefront`:*
    ```text
    APP_TITLE=AMLC Mountain Store
    LOG_LEVEL=debug
    FEATURE_BANNER=DEV SANDBOX
    ```
    *Output from `prod-storefront`:*
    ```text
    APP_TITLE=AMLC Mountain Store
    LOG_LEVEL=warn
    FEATURE_BANNER=PRODUCTION LIVE
    ```

5.  **Delete an overlay cleanly using `kubectl delete -k`:**
    ```bash
    kubectl delete -k kustomize/overlays/dev
    kubectl delete -k kustomize/overlays/prod
    ```

---

## 🧩 Module 3: Extending Kubernetes — Discovering & Using CRDs and Operators

Kubernetes doesn't only manage built-in objects like `Pod`s and `Deployment`s. Anyone can extend the Kubernetes API by registering a **`CustomResourceDefinition` (`CRD`)** and running a custom controller (**Operator**) that watches and reconciles those new objects.

### 3.1 The Operator Pattern & Why Cluster Scope vs. Namespace Scope Matters

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. PLATFORM ADMIN (Cluster Scope)                                       │
│    Installs CRD & Operator Controller (Gateway API, Prometheus, etc.)   │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │ Registers New API Kind
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 2. KUBERNETES API SERVER                                                │
│    Exposes Custom Resource Kinds (HTTPRoute, PodMonitoring, ...)        │
└───────────────────────────────────▲─────────────────────────────────────┘
                                    │
┌───────────────────────────────────┴─────────────────────────────────────┐
│ 3. APP DEVELOPER — YOU! (Namespace Scope)                               │
│    Runs `kubectl apply` to create Custom Resources in your namespace    │
│    ──► Operator Controller watches API & reconciles live infrastructure │
└─────────────────────────────────────────────────────────────────────────┘
```

*   **Installing an Operator** (registering the `CRD` and `ClusterRole`) is a **cluster-admin** task done once per cluster.
*   **Using an Operator** (discovering installed CRDs and creating **namespaced Custom Resources (`CR`s)**) is an **application developer (CKAD)** task done inside your own namespace!

---

### 3.2 Hands-On: Discovering Installed CRDs & Deploying a Custom Resource

Our GKE cluster has several real Operators pre-installed—including the **Gateway API controller** (Traefik) and the **Google Cloud Managed Service for Prometheus (GMP) Operator**.

1.  **Discover all CustomResourceDefinitions (`CRD`s) installed on the cluster:**
    ```bash
    kubectl get crd
    ```
    *You will see CRDs across multiple API groups: `httproutes.gateway.networking.k8s.io`, `podmonitorings.monitoring.googleapis.com`, `backendconfigs.cloud.google.com`, etc.*

2.  **Find which API resources are namespaced (`NAMESPACED = true`):**
    ```bash
    kubectl api-resources --namespaced=true | grep -E "monitoring|gateway|cloud.google.com"
    ```

3.  **Inspect a Custom Resource's schema using `kubectl explain` (CKAD Exam Superpower!):**
    Even if you have never seen `PodMonitoring` before on the exam, `kubectl explain` reads the OpenAPI schema directly from its `CRD`:
    ```bash
    kubectl explain podmonitoring.spec
    kubectl explain podmonitoring.spec.endpoints
    ```

4.  **Deploy a `PodMonitoring` Custom Resource ([manifests/podmonitoring-cr.yaml](manifests/podmonitoring-cr.yaml)) in your namespace:**
    Review [manifests/podmonitoring-cr.yaml](manifests/podmonitoring-cr.yaml)—it tells the cluster's Managed Prometheus Operator to scrape `/metrics` on port `http` every `30s` from Pods labeled `app.kubernetes.io/name: podinfo`:
    ```bash
    kubectl apply -f manifests/podmonitoring-cr.yaml
    kubectl get podmonitoring
    kubectl describe podmonitoring podinfo-scraper
    ```
    *Look at the `Status:` block in `kubectl describe podmonitoring podinfo-scraper`—the cluster's GMP Operator controller immediately detected your Custom Resource in your namespace and updated its status (`ConfigurationCreateSuccess`)!*

---

## 🧹 Cleaning Up

Clean up all resources created in this section:
```bash
kubectl delete -f manifests/podmonitoring-cr.yaml --ignore-not-found
kubectl delete -k kustomize/overlays/dev --ignore-not-found
kubectl delete -k kustomize/overlays/prod --ignore-not-found
helm uninstall my-podinfo 2>/dev/null || true
```
