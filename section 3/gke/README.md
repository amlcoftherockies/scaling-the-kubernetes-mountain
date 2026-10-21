# Section 3 (GCP lab version): Connect to the Workshop Cluster

In the GCP version of the workshop, the instructor runs **one shared Google Kubernetes Engine (GKE) cluster**. You get your **own namespace** on it, and you'll find a ready-made **kubeconfig** attached to your workshop email.

This matches the CKAD exam: you're given a working cluster and a context, and all your work is application work inside a namespace.

> You do **not** need a Google Cloud account, and you will not install `gcloud`. All you need is `kubectl`.

---

## 🏛️ What you get

| You can | You cannot |
|---|---|
| Create, edit and delete Pods, Deployments, Jobs, CronJobs, Services, Ingress, ConfigMaps, Secrets, PVCs, NetworkPolicies, HPAs… **in your namespace** | See or change other participants' namespaces |
| Expose apps on the internet through the workshop's **shared Gateway** (`HTTPRoute`) or **Ingress**, on your own hostname | Create cluster-wide objects (Nodes, Namespaces, ClusterRoles, CRDs) or your own `type: LoadBalancer` Service |
| Get storage with **PVCs** (the default StorageClass creates the PV for you) | Create PersistentVolumes or other cluster-wide objects directly |
| **See** nodes, PVs, StorageClasses, RuntimeClasses (read-only) | Run privileged pods or mount host paths (Pod Security `baseline`) |
| Run sandboxed Pods with `runtimeClassName: gvisor` | Change anything outside your namespace |
| Use up to 2 CPU / 4 GiB memory / 20 pods | Touch anything in Google Cloud itself |

Your namespace is the slug of your email address. For example, `jsmith@example.com` becomes `jsmith-example-com`, and that's already the default namespace in your kubeconfig.

Your access token **expires** after the workshop window (the email says when). If it expires early, ask the instructor to run `labctl-gke rotate`.

---

## 🛠️ Step 1: Install kubectl

Pick your OS:

- **macOS:** `brew install kubectl`
- **Windows:** `winget install -e --id Kubernetes.kubectl`
- **Linux:** follow <https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/>

Check it: `kubectl version --client`

---

## 🔑 Step 2: Use the kubeconfig from your email

1. Save the attachment `ckad-lab.kubeconfig` into a folder such as `~/.kube/`.
2. Point kubectl at it:

```bash
# macOS / Linux
export KUBECONFIG=~/.kube/ckad-lab.kubeconfig
```

```powershell
# Windows PowerShell
$env:KUBECONFIG="$HOME\.kube\ckad-lab.kubeconfig"
```

> Treat this file like a password. Anyone who has it can act as you in your namespace.

### Useful context commands (CKAD essentials)

```bash
kubectl config view --minify            # what am I connected to?
kubectl config get-contexts
kubectl config current-context
kubectl config set-context --current --namespace=<ns>
```

---

## 🔍 Step 3: Verify

```bash
kubectl get pods                         # "No resources found" means it worked
kubectl auth can-i create deployments    # yes
kubectl get nodes                        # read-only view of cluster worker nodes
kubectl get resourcequota,limitrange     # your guardrails
```

Or run the automated **CKAD Lab Smoke Test & Security Audit** script from the root of the repository to validate your connection, least-privilege guardrails, and live HTTP routing across all CKAD lab modules (Sections 4–10):

```bash
./scripts/ckad-lab-smoke-test.sh
```

### Expose an application (shared Gateway)

The whole workshop shares **one** load balancer. Traefik runs behind it and serves both the **Gateway API** (Gateway `lab-gateway`) and **Ingress** (class `traefik`). You attach your app with a route that uses **your hostname** from the welcome email, for example `jsmith-example-com.amlcoftherockies.net`.

```bash
MY_HOST=<your hostname from the email>
sed "s/MY_HOST/$MY_HOST/" manifests/hello-gateway.yaml | kubectl apply -f -
kubectl get httproute hello              # check that the route is attached
curl http://$MY_HOST                     # Welcome to nginx!
kubectl delete -f manifests/hello-gateway.yaml --ignore-not-found
```

The guardrails will reject:
- a route for a hostname that isn't yours;
- a route or Ingress with no hostname;
- `type: LoadBalancer`, which gets `exceeded quota`. Use the shared Gateway instead.

---

## 🧯 Troubleshooting

| Symptom | Fix |
|---|---|
| `error: You must be logged in` / `Unauthorized` | Your token expired. Ask the instructor to rotate it. |
| `forbidden: ... cannot list resource ... at the cluster scope` | Expected: you only have namespace access. Add `-n <your-namespace>` or drop `-A`. |
| `exceeded quota` | Delete old resources (`kubectl get all`), or lower your requests. |
| `violates PodSecurity "baseline"` | Remove `privileged`, `hostPath`, `hostNetwork` and similar settings. These are never needed for CKAD tasks. |
| Pending PVC | Use `storageClassName: standard-rwo`, or leave it out to get the default. |
| `denied request: ... hostnames must be set to ...` | Use your own hostname (from the email), or a subdomain of it. |
| `curl` gives `503` right after you apply | The route is live but your pods aren't ready yet. Wait a few seconds and retry. |
| `curl` gives `404 page not found` | Traefik is reachable but no route matches. Check `kubectl describe httproute` (look for `Accepted`/`ResolvedRefs`) and that the Service name and port match. |

---

## ➡️ Next Step

Once `kubectl get pods` works, head straight to [**Section 4: Core Kubernetes Architecture & Workloads**](../../section%204/README.md)!
