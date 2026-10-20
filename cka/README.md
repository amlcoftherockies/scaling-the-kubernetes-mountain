# CKA (Certified Kubernetes Administrator) Track — Scaffolding

While the main **CKAD Track** (`section 3` through `section 6+`) focuses on **designing, building, configuring, and exposing cloud-native applications** inside an existing Kubernetes cluster, the **CKA Track** focuses on **cluster architecture, installation, maintenance, and troubleshooting** on raw Linux VMs (`kubeadm`).

## Planned CKA Modules (Compute Engine VMs via `labctl-cka`)

1. **Module 1: Cluster Architecture & Bootstrapping with `kubeadm`**
   - Installing `containerd`, `kubelet`, `kubeadm`, and `kubectl` on Linux nodes
   - Bootstrapping the control plane (`kubeadm init`) and joining worker nodes (`kubeadm join`)
   - Installing a CNI plugin (Cilium / Calico)
2. **Module 2: `etcd` Operations & Disaster Recovery**
   - Inspecting the `etcd` static pod and TLS certificates
   - Taking an `etcdctl snapshot save` backup and restoring cluster state (`etcdctl snapshot restore`)
3. **Module 3: Cluster Lifecycle & Control Plane Upgrades**
   - Draining nodes (`kubectl cordon` / `kubectl drain`)
   - Upgrading control plane and worker nodes across minor versions with `kubeadm upgrade`
4. **Module 4: Cluster-Level RBAC, Certificates & Node Troubleshooting**
   - Inspecting and renewing control-plane certificates (`kubeadm certs`)
   - Debugging broken `kubelet` systemd units, static pod manifests (`/etc/kubernetes/manifests`), and CNI networking
