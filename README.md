# Scaling the Kubernetes Mountain

Hands-on Kubernetes workshop curriculum by **AMLC of the Rockies**.

---

## 🎯 Tracks

### 1. CKAD Track (Certified Kubernetes Application Developer) — *Active*
You receive a personal `ckad-lab.kubeconfig` via email connected to your own isolated namespace on our shared Kubernetes cluster. No cloud account or Terraform required!

- **[Section 3: Connect to the Workshop Cluster](section%203/README.md)** *(Verify `kubectl`, set up your emailed `ckad-lab.kubeconfig`, and run [`./scripts/ckad-lab-smoke-test.sh`](scripts/ckad-lab-smoke-test.sh))*
- **[Section 4: Core Kubernetes Architecture & Workloads](section%204/README.md)** *(Pods, Multi-Container Patterns, ReplicaSets, Deployments, DaemonSets, Jobs & CronJobs, Blue-Green & Canary, Services, DNS)*
- **[Section 5: Configuration, Persistent Storage & StatefulSets](section%205/README.md)** *(ConfigMaps, Secrets, PVCs/PVs, StorageClasses, StatefulSets)*
- **[Section 6: Container Image Lifecycle & Runtime Sandboxing](section%206/README.md)** *(OCI Standards, Image Optimization, Multi-Stage Builds, Registries, Digests, `imagePullPolicy`, gVisor `RuntimeClass`)*
- **[Section 7: Application Observability and Maintenance](section%207/README.md)** *(Startup/Readiness/Liveness Probes, Logs & `--previous`, `kubectl top`, Prometheus `/metrics`, Troubleshooting, API Deprecations)*
- **[Section 8: Application Security, RBAC & Network Policies](section%208/README.md)** *(Pod Security Standards, `SecurityContext`, ServiceAccounts, RBAC & `auth can-i`, `NetworkPolicy` Isolation, Resource Requests/Limits/Quotas)*
- **[Section 9: Services, Multi-Port Exposure, Ingress & HTTP Routing](section%209/README.md)** *(Multi-Port & Named-Port Services, `ExternalName` DNS, `Ingress` Path Routing, Gateway API `HTTPRoute` Header & Weighted Canary Routing)*
- **[Section 10: Packaging with Helm, Kustomize & Extending Kubernetes (CRDs & Operators)](section%2010/README.md)** *(Helm Charts & Rollbacks with `podinfo`, Kustomize `base/` + `overlays/`, Discovering & Using CRDs & Operators)*

---

### 2. CKA Track (Certified Kubernetes Administrator) — *Scaffolding*
For cluster administrators: each participant receives dedicated Linux VMs (`1 control-plane + 2 workers`) to bootstrap and operate a cluster from scratch.

- **[CKA Track Overview (`cka/README.md`)](cka/README.md)**
