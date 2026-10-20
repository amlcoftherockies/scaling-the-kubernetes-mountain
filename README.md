# Scaling the Kubernetes Mountain

Hands-on Kubernetes workshop curriculum by **AMLC of the Rockies**.

---

## 🎯 Tracks

### 1. CKAD Track (Certified Kubernetes Application Developer) — *Active*
You receive a personal `ckad-lab.kubeconfig` via email connected to your own isolated namespace on our shared Kubernetes cluster. No cloud account or Terraform required!

- **[Section 3: Connect to the Workshop Cluster](section%203/gke/README.md)** *(Optional smoke test — cluster is already running!)*
- **[Section 4: Core Kubernetes Architecture & Workloads](section%204/README.md)** *(Pods, ReplicaSets, Deployments, Rollouts, Services, DNS)*
- **[Section 5: Configuration, Persistent Storage & StatefulSets](section%205/README.md)** *(ConfigMaps, Secrets, PVCs/PVs, StorageClasses, StatefulSets)*
- **[Section 6: Container Image Lifecycle & Runtime Sandboxing](section%206/README.md)** *(Multi-stage builds, registries, digests, `imagePullPolicy`, gVisor `RuntimeClass`)*

---

### 2. CKA Track (Certified Kubernetes Administrator) — *Scaffolding*
For cluster administrators: each participant receives dedicated Linux VMs (`1 control-plane + 2 workers`) to bootstrap and operate a cluster from scratch.

- **[CKA Track Overview (`cka/README.md`)](cka/README.md)**
