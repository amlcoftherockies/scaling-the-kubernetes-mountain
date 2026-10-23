# Section 3: Connect to the Workshop Cluster

> [!IMPORTANT]
> **Instructor-Led Workshop Participants:**
> You do **not** need to provision a cluster or create a cloud account! The workshop cluster is already running, and you should have received an email (`Your CKAD workshop cluster access`) with your personal **`ckad-lab.kubeconfig`** attached.
>
> All you need to do in this section is make sure **`kubectl` is installed**, configure your **`kubeconfig`**, and verify your connection before jumping into [Section 4](../section%204/README.md).

This setup mirrors the **CKAD (Certified Kubernetes Application Developer)** exam: you are given a running cluster and a pre-configured namespace context, and all of your work happens inside your own namespace using `kubectl`.

---

## 🛠️ Step 1: Ensure You Have `kubectl` Installed

First, check if `kubectl` is already installed on your machine:

```bash
kubectl version --client
```

If `kubectl` is not installed, install it for your operating system:

- **macOS (Homebrew):**
  ```bash
  brew install kubectl
  ```
- **Windows (Winget / PowerShell):**
  ```powershell
  winget install -e --id Kubernetes.kubectl
  ```
- **Linux:** Follow the [official Kubernetes Linux install guide](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/).

*(Optional for Section 10: you can also install Helm now via `brew install helm` on macOS or `winget install Helm.Helm` on Windows.)*

---

## 🔑 Step 2: Set Up Your `kubeconfig` from Your Email

1. Open the welcome email from **AMLC of the Rockies** (`Your CKAD workshop cluster access`) and download the attached **`ckad-lab.kubeconfig`** file.
   *(If you haven't received the email, check your spam folder or let the instructor know!)*
2. Move the file into your `~/.kube/` directory and point `kubectl` to it:

**macOS / Linux:**
```bash
mkdir -p ~/.kube
mv ~/Downloads/ckad-lab.kubeconfig ~/.kube/ckad-lab.kubeconfig
chmod 600 ~/.kube/ckad-lab.kubeconfig

# Point kubectl at your workshop kubeconfig for this terminal session:
export KUBECONFIG=~/.kube/ckad-lab.kubeconfig
```
*(Tip: If you don't use Kubernetes for anything else on your laptop, you can also copy it to the default location `cp ~/.kube/ckad-lab.kubeconfig ~/.kube/config` so every new terminal tab uses it automatically!)*

**Windows (PowerShell):**
```powershell
New-Item -ItemType Directory -Force -Path "$HOME\.kube"
Move-Item -Force "$HOME\Downloads\ckad-lab.kubeconfig" "$HOME\.kube\ckad-lab.kubeconfig"

# Point kubectl at your workshop kubeconfig for this PowerShell window:
$env:KUBECONFIG="$HOME\.kube\ckad-lab.kubeconfig"
```

> [!CAUTION]
> Treat your `ckad-lab.kubeconfig` file like a password—it contains a bearer token that grants access to your workshop namespace for the duration of the lab.

### Useful Context Commands (CKAD Exam Essentials)

```bash
kubectl config view --minify            # Inspect active cluster, user & default namespace
kubectl config current-context          # Show current context name
kubectl config get-contexts             # List all contexts in your kubeconfig
```

---

## 🔍 Step 3: Verify Your Connection & Run the Smoke Test

Run these commands to confirm you are connected to your namespace:

```bash
kubectl get pods                         # "No resources found in <your-namespace> namespace." = Success!
kubectl auth can-i create deployments    # yes
kubectl get nodes                        # Read-only view of the cluster worker nodes
kubectl get resourcequota,limitrange     # View your namespace resource guardrails
```

You can also run the automated **CKAD Lab Smoke Test** from the root of this repository to verify your `kubeconfig`, least-privilege guardrails, and live external HTTP routing (`http://<your-namespace>.amlcoftherockies.net`):

```bash
./scripts/ckad-lab-smoke-test.sh
```

---

## 🏛️ What You Can & Cannot Do in Your Workshop Namespace

| You Can (`<your-namespace>`) | You Cannot (Cluster-Wide / Other Namespaces) |
| :--- | :--- |
| Create, edit, and delete `Pod`s, `Deployment`s, `DaemonSet`s, `StatefulSet`s, `Job`s, `CronJob`s, `Service`s, `Ingress`es, `HTTPRoute`s, `ConfigMap`s, `Secret`s, `PVC`s, `ServiceAccount`s, `Role`s, `RoleBinding`s, `NetworkPolicy`s, and `PodMonitoring` CRs **in your namespace** | View or modify other participants' namespaces or `kube-system` |
| Expose live HTTP applications on the internet via the shared Traefik Gateway (`HTTPRoute`) or `Ingress` on **`<your-namespace>.amlcoftherockies.net`** | Create cluster-wide objects (`Namespace`, `Node`, `PersistentVolume`, `ClusterRole`, `CRD`) or `type: LoadBalancer` Services (use `Ingress` or `HTTPRoute` instead) |
| Request persistent disks via **`PVC`s** (`storageClassName: standard-rwo`) | Run `privileged: true` containers or mount node `hostPath` volumes (blocked by Pod Security `baseline`) |
| Inspect cluster-wide `Node`s, `PersistentVolume`s, `StorageClass`es, `RuntimeClass`es, `CRD`s, and `kubectl top` metrics (read-only) | Access Google Cloud IAM or cloud provider APIs |

*(For additional details on exposing a test app via the shared Gateway and common troubleshooting tips, see [`gke/README.md`](gke/README.md).)*

---

## ➡️ Next Step

Once `kubectl get pods` works, head straight to **[Section 4: Core Kubernetes Architecture & Workloads](../section%204/README.md)**!
