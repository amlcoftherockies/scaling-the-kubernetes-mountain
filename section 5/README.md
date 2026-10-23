# Section 5: Application Config, Persistent Storage, and Stateful Workloads

Welcome to Section 5 of the Kubernetes Scaling Workshop! 

This section covers core topics required for the **CKAD (Certified Kubernetes Application Developer)** exam. We will master **ConfigMaps, Secrets, PersistentVolumes (PV), PersistentVolumeClaims (PVC), StorageClasses, and StatefulSets**.

In this guide, we will focus heavily on **describing resources** to understand their detailed characteristics, comparing **desired state** with **deployed state**, and verifying storage persistence across Pod restarts and scaling events.

---

## 📦 Module 1: Managing Application Configuration (ConfigMaps & Secrets)

Applications require configuration settings (ports, database names) and credentials (passwords, tokens). In Kubernetes, we separate these from the application code.

### 1.1 ConfigMaps

A **ConfigMap** stores non-confidential key-value configuration data.

#### 1.1.1 ConfigMap Creation (Three Ways)

##### 1. The Imperative Way (From Literals)
Create a ConfigMap instantly by passing key-value pairs directly in the CLI:
```bash
kubectl create configmap app-config-literal \
  --from-literal=APP_COLOR=red \
  --from-literal=APP_MODE=production
```

##### 2. The Imperative Way (From Local Files)
Create a temporary file:
```bash
echo "theme=dark" > config.txt
echo "timeout=30" >> config.txt
```
Create a ConfigMap from that file. The key will be the filename, and the value will be the file content:
```bash
kubectl create configmap app-config-file --from-file=config.txt
rm config.txt # Clean up local file
```

##### 3. The Declarative Way (YAML Manifest)
Review the file [configmap.yaml](manifests/configmap.yaml):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  APP_COLOR: blue
  APP_MODE: interactive
  ui.properties: |
    color=blue
    size=12
    font=sans-serif
```
Deploy the manifest:
```bash
kubectl apply -f manifests/configmap.yaml
```

#### 1.1.2 Describing the ConfigMap Resource
To inspect the properties, data keys, and binary sizes of the ConfigMap, use `describe`:
```bash
kubectl describe configmap app-config
```
*Observe the output shows all keys (`APP_COLOR`, `APP_MODE`, and `ui.properties`) and their values or sizes.*

---

### 1.2 Secrets

A **Secret** stores sensitive information (passwords, API tokens). Secret values are Base64 obfuscated to prevent shoulder-surfing, though they are not fully encrypted on their own without KMS integration.

#### 1.2.1 Secret Creation (Two Ways)

##### 1. The Imperative Way (From Literals)
Create a generic secret:
```bash
kubectl create secret generic app-secret-literal \
  --from-literal=API_TOKEN=super-secret \
  --from-literal=DB_PASSWORD=admin123
```

##### 2. The Declarative Way (YAML Manifest)
Secret values in YAML **must** be Base64 encoded. Let's encode a secret values manually:
```bash
echo -n "super-secret-token" | base64
# Output: c3VwZXItc2VjcmV0LXRva2Vu
```
Review and deploy [secret.yaml](manifests/secret.yaml):
```bash
kubectl apply -f manifests/secret.yaml
```

#### 1.2.2 Describing and Decoding Secrets
If you describe a Secret, the values are masked:
```bash
kubectl describe secret app-secret
```
*Note that the output lists the keys and sizes (e.g. `API_TOKEN: 18 bytes`) but hides the actual content to prevent leaks.*

To view and decode a Secret's contents:
```bash
# Retrieve base64 encoded data
kubectl get secret app-secret -o yaml

# Extract and decode the API_TOKEN value (essential CKAD skill!)
kubectl get secret app-secret -o jsonpath='{.data.API_TOKEN}' | base64 --decode
```

---

### 1.3 Injecting Configurations & Secrets into a Pod

We can inject ConfigMap and Secret data into containers either as **Environment Variables** or as **Mounted Files**.

Review and deploy [pod-config.yaml](manifests/pod-config.yaml):
```bash
kubectl apply -f manifests/pod-config.yaml
```
Verify the Pod is running:
```bash
kubectl get pod pod-config-demo
```

#### 1.3.1 Verifying Environment Variables
Exec into the container and print the environment:
```bash
kubectl exec pod-config-demo -- env | grep -E "COLOR|MODE|SECRET_TOKEN"
```
*Verify that `COLOR=blue` and `MODE=interactive` (from ConfigMap) and `SECRET_TOKEN=super-secret-token` (from Secret) are successfully injected.*

#### 1.3.2 Verifying Mounted Volume Files
ConfigMaps and Secrets mounted as volumes appear as directories containing a file for each key.
```bash
# Inspect mounted ConfigMap
kubectl exec pod-config-demo -- cat /config/ui.properties

# Inspect mounted Secret files
kubectl exec pod-config-demo -- cat /secrets/DB_PASSWORD
```

#### 1.3.3 Pro-Tip: Memory-Backed Storage (`tmpfs`)
Kubernetes mounts Secrets inside the pod using **tmpfs** (RAM-backed, temporary filesystems). This ensures sensitive tokens are never written to the physical storage disk of the node VM.

Verify the filesystem type for `/secrets` inside the running container:
```bash
kubectl exec pod-config-demo -- df -hT /secrets
```
*Observe that the Type column displays **`tmpfs`**.*

---

## 💾 Module 2: Persistent Storage Fundamentals (PVs and PVCs)

Pods are ephemeral: if they die, their local filesystems are lost. To persist data, Kubernetes splits storage into two objects:

| Object | Scope | Who creates it |
|---|---|---|
| **PersistentVolume (PV)** | **Cluster-wide** | A cluster admin by hand, or (almost always) a **provisioner** automatically |
| **PersistentVolumeClaim (PVC)** | **Your namespace** | **You, the app developer.** It's your request: "I need 1Gi, read-write" |


As an app developer (and on the CKAD exam) you **ask for storage with a PVC**. A PV is then found for you, or created on the spot, and bound to your claim.

> [!NOTE]
> **Shared workshop cluster:** you can **see** PVs (`kubectl get pv`) but not create them, because PVs are cluster-wide. That's normal on real teams too. Everything below works the same on GKE, OKE or any cluster with a default StorageClass.

### 2.1 What a PersistentVolume looks like

Look at the cluster's existing PVs. On a shared cluster you'll see other people's volumes too:
```bash
kubectl get pv
```
Note the columns: `CAPACITY`, `ACCESS MODES`, `RECLAIM POLICY`, `STATUS` and `CLAIM` (`<namespace>/<pvc-name>`), plus the `STORAGECLASS`.

For reference, [admin/pv-static.yaml](manifests/admin/pv-static.yaml) is a PV an admin would write by hand (a `hostPath` volume with `storageClassName: manual`).

> [!TIP]
> **Own single-node cluster only:** try static binding with `kubectl apply -f manifests/admin/pv-static.yaml -f manifests/admin/pvc-static.yaml`, then `kubectl get pv,pvc` shows them `Bound` to each other. On the shared cluster, skip this: you can't create PVs, and hostPath volumes are an admin decision.

---

### 2.2 Ask for storage: the PersistentVolumeClaim

Review [pvc-demo.yaml](manifests/pvc-demo.yaml). It requests `1Gi` of `ReadWriteOnce` storage and deliberately has **no `storageClassName`**, so the cluster's **default StorageClass** handles it.

1.  Create the claim:
    ```bash
    kubectl apply -f manifests/pvc-demo.yaml
    ```
2.  Check it:
    ```bash
    kubectl get pvc pvc-demo
    ```
    *You'll most likely see **`Pending`**. That's expected: most default StorageClasses wait until a Pod actually uses the claim before creating the disk (more in Module 3). If yours shows `Bound` immediately, your default class uses `Immediate` binding.*

---

### 2.3 Deploying a Pod with Storage

1.  Review and deploy [pod-storage.yaml](manifests/pod-storage.yaml), which mounts `pvc-demo` at `/data`:
    ```bash
    kubectl apply -f manifests/pod-storage.yaml
    kubectl get pod pod-storage -w     # wait for Running, then Ctrl+C
    ```
2.  The claim is now `Bound`, and a PV exists **that you never wrote**:
    ```bash
    kubectl get pvc pvc-demo
    kubectl get pv | grep pvc-demo     # CLAIM column = <your-namespace>/pvc-demo
    ```
3.  Describe the Pod to see the volume wiring:
    ```bash
    kubectl describe pod pod-storage
    ```
    *Look at the `Volumes` block: `data-vol` maps back to your PVC.*

---

### 2.4 Persistence Test

Let's verify that data survives Pod deletion.

1.  Write a test file into the mounted directory (`/data`):
    ```bash
    kubectl exec pod-storage -- sh -c "echo 'Kubernetes Persistent Storage Test' > /data/test.txt"
    ```
2.  Delete the Pod:
    ```bash
    kubectl delete pod pod-storage
    ```
3.  Recreate it:
    ```bash
    kubectl apply -f manifests/pod-storage.yaml
    ```
4.  Once it's `Running`, read the file from the new Pod:
    ```bash
    kubectl exec pod-storage -- cat /data/test.txt
    ```
    *You should see `Kubernetes Persistent Storage Test`. The data survived because it lives on the PV, outside the Pod's lifecycle.*

---

## ⚡ Module 3: Dynamic Provisioning & Storage Topology

Who created that PV? A **StorageClass**. It names a **provisioner** (a CSI driver for your cloud's disks) and the settings to use. When a PVC asks for storage, the provisioner creates a disk plus a matching PV automatically. This is called **dynamic provisioning**.

### 3.1 Find the Default StorageClass

1.  List the StorageClasses:
    ```bash
    kubectl get storageclass
    ```
    *One is marked **`(default)`**. That's the one your PVC used because it didn't name a class. Common defaults:*

    | Cluster | Default class | Provisioner |
    |---|---|---|
    | GKE | `standard-rwo` | `pd.csi.storage.gke.io` (Persistent Disk) |
    | Oracle OKE | `oci-bv` | `blockvolume.csi.oraclecloud.com` (Block Volume, 50 GB minimum) |
    | kind / minikube | `standard` | a local-path / hostPath provisioner |

2.  Describe it (replace `<default-class>` with yours):
    ```bash
    kubectl describe storageclass <default-class>
    ```
    *Note `Provisioner`, `ReclaimPolicy` and `VolumeBindingMode`.*

3.  See the provisioning story in your PVC's events:
    ```bash
    kubectl describe pvc pvc-demo
    ```
    *You'll see `WaitForFirstConsumer` → `Provisioning` → `ProvisioningSucceeded`.*

> [!TIP]
> **CKAD:** to pick a non-default class, set `spec.storageClassName: <name>` in the PVC. To force *no* dynamic provisioning (static binding to an existing PV), set `storageClassName: ""`.

---

### 3.2 Inspecting the CSI Driver & `kube-system` Node DaemonSets

How does Kubernetes actually talk to Google Cloud (or AWS/Oracle) to attach and mount a disk onto a worker node? Through the **Container Storage Interface (CSI)**!

When `standard-rwo` says `Provisioner: pd.csi.storage.gke.io`, that string isn't built into the Kubernetes core binary—it is a **CSI Driver plugin** registered on the cluster and running as system Pods inside **`kube-system`**:

1.  **List the CSI Drivers registered in the cluster and the CSI status of each worker node:**
    ```bash
    kubectl get csidrivers
    kubectl get csinodes
    ```
    *You will see `pd.csi.storage.gke.io` (Google Persistent Disk), `filestore.csi.storage.gke.io` (Cloud Filestore NFS), and `podcertificate.gke.io`, along with all 4 worker nodes registered as `CSINode`s.*

2.  **Inspect the CSI Driver `DaemonSet`s and `Pod`s running in `kube-system`:**
    Because *every* worker node needs to be able to format (`mkfs.ext4`) and mount block volumes into container filesystems, the node portion of a CSI driver runs as a **`DaemonSet`** in `kube-system`:
    ```bash
    # View the CSI node DaemonSets in kube-system (pdcsi-node and filestore-node)
    kubectl get daemonsets -n kube-system | grep -E "NAME|csi|filestore"

    # View the CSI driver Pods running across every worker node
    kubectl get pods -n kube-system -o wide | grep -E "NAME|pdcsi|filestore"
    ```
    *Notice how `pdcsi-node` runs 1 Pod per worker node (`3/3` containers: the CSI node-driver-registrar sidecar, the livenessprobe sidecar, and the `gce-pd-driver` plugin container that mounts disks onto the node)!*

---

### 3.3 Access Modes

Kubernetes supports different access modes for volumes:
*   **`ReadWriteOnce` (RWO)**: mounted read-write by a single **node**. This is standard block storage (Persistent Disk, OCI Block Volume, EBS).
*   **`ReadOnlyMany` (ROX)**: mounted read-only by many nodes.
*   **`ReadWriteMany` (RWX)**: mounted read-write by many nodes. This needs a shared filesystem (Filestore, OCI File Storage, NFS) so Pods on different VMs can read and write concurrently.
*   **`ReadWriteOncePod` (RWOP)**: mounted read-write by a single **Pod**.

---

### 3.4 Storage Topology & Wait For First Consumer

Cloud disks are **zonal** (Oracle calls zones *availability domains*). If a disk is created in zone A and the scheduler puts the Pod on a node in zone B, the disk can't attach and the Pod never starts.

1.  See which zone each node is in:
    ```bash
    kubectl get nodes -L topology.kubernetes.io/zone
    ```
2.  See which zone **your** PV was created in:
    ```bash
    kubectl get pv $(kubectl get pvc pvc-demo -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.nodeAffinity}'; echo
    ```

#### The Solution: `volumeBindingMode: WaitForFirstConsumer`
```bash
kubectl get storageclass <default-class> -o jsonpath='{.volumeBindingMode}'; echo
```
**`WaitForFirstConsumer`** tells Kubernetes **not** to create the disk when the PVC is created. It waits until the scheduler has picked a node for the Pod, then creates the disk in that node's zone. That's why your PVC was `Pending` until the Pod existed.

### 3.4 Reclaim Policy: What Happens When You Delete the Claim

Dynamically provisioned PVs usually have `RECLAIM POLICY: Delete`. Delete the claim, and the PV and the cloud disk go with it:
```bash
kubectl delete pod pod-storage
kubectl delete pvc pvc-demo
kubectl get pv | grep pvc-demo     # gone after a few seconds
```
*With `Retain`, the PV would stay (`Released`) and an admin would have to clean it up. That's useful for precious data.*

---

## 🏛️ Module 4: Stateful Workloads (StatefulSets)

Deployments are designed for stateless applications. For applications that require stable identities and dedicated, isolated storage (e.g. database replicas, Kafka clusters), we use **StatefulSets**.

### 4.1 Headless Services & StatefulSets

A StatefulSet requires a **Headless Service** (a Service with `clusterIP: None`) to handle DNS resolution for individual pods.

> [!IMPORTANT]
> **Why Use a Headless Service for SQL Databases?**
> Stateful databases like **MySQL** or **PostgreSQL** usually run in a **Primary-Replica (Master-Slave)** topology where:
> *   **Writes** must go to **only one specific Pod** (the Primary).
> *   **Reads** can be spread across multiple Replica Pods.
>
> If you used a regular `ClusterIP` Service for writes, `kube-proxy` would randomly load-balance your `INSERT` statements across all Pods—accidentally sending writes to Read-Only Replica Pods and failing!
>
> With a **Headless Service (`clusterIP: None`)** paired with a **StatefulSet**:
> *   **Direct Pod Addressing (Deterministic Hostnames)**: Kubernetes assigns a unique, stable network identity to each Pod in the StatefulSet:
>     *   `postgres-0.postgres-headless.<namespace>.svc.cluster.local`
>     *   `postgres-1.postgres-headless.<namespace>.svc.cluster.local`
>     *   `postgres-2.postgres-headless.<namespace>.svc.cluster.local`
> *   Your application (or database operator) can target **`postgres-0`** directly for all write operations because its hostname and underlying volume remain stable across restarts!

1.  Review and deploy the Headless Service [service-headless.yaml](manifests/service-headless.yaml):
    ```bash
    kubectl apply -f manifests/service-headless.yaml
    ```
2.  Review and deploy the StatefulSet [statefulset.yaml](manifests/statefulset.yaml):
    ```bash
    kubectl apply -f manifests/statefulset.yaml
    ```

---

### 4.2 Ordered Startup and Hostname Stability

1.  Watch the StatefulSet Pod creation sequence:
    ```bash
    kubectl get pods -l app=stateful-web -w
    ```
    *Notice the ordering: `web-0` is created first and must be fully Running/Ready before `web-1` starts provisioning. (StatefulSets build replicas sequentially).*

2.  Verify the stable Hostname inside the Pods:
    ```bash
    kubectl exec web-0 -- hostname
    kubectl exec web-1 -- hostname
    ```
    *(Unlike Deployments, which generate random hashes in pod names, StatefulSet pods maintain a stable index name (`web-0`, `web-1`) that persists across restarts).*

---

### 4.3 Stable DNS Resolution

Because we deployed a Headless Service, CoreDNS creates a direct A record for each individual Pod.

1.  Spin up a temporary busybox testing pod:
    ```bash
    kubectl run tmp-dns --image=docker.io/library/busybox:1.36 --restart=Never -- sleep 3600
    ```
2.  Resolve the individual Pod DNS names. The format is `<pod>.<headless-service>.<namespace>.svc.cluster.local`:
    ```bash
    NS=$(kubectl config view --minify -o jsonpath='{..namespace}'); NS=${NS:-default}
    kubectl exec tmp-dns -- nslookup web-0.nginx-headless.$NS.svc.cluster.local
    kubectl exec tmp-dns -- nslookup web-1.nginx-headless.$NS.svc.cluster.local
    ```
    > [!NOTE]
    > Why the full name? `busybox:1.36`'s `nslookup` doesn't apply search domains to names that already contain a dot, so the short `web-0.nginx-headless` returns `NXDOMAIN` even though the record exists. Apps don't have this problem: `kubectl exec tmp-dns -- wget -qO- http://web-0.nginx-headless` resolves fine.
    *Observe that each DNS query resolves directly to the unique IP address of that specific Pod.*

---

### 4.4 Dedicated Storage Persistence

A StatefulSet uses **`volumeClaimTemplates`** to dynamically provision a dedicated PVC for each Pod replica.

1.  View the dynamically generated PVCs:
    ```bash
    kubectl get pvc
    ```
    *Observe that Kubernetes created `www-web-0` and `www-web-1` respectively.*

2.  **Scale Down Experiment**:
    Scale the StatefulSet down to 0 replicas:
    ```bash
    kubectl scale statefulset web --replicas=0
    ```
    Verify the pods are terminated:
    ```bash
    kubectl get pods -l app=stateful-web
    ```
3.  Check the PVCs:
    ```bash
    kubectl get pvc
    ```
    *Note that the PVCs `www-web-0` and `www-web-1` **are still present and Bound**! Kubernetes purposefully does not delete volume claims during scale-downs to protect your data.*

4.  Scale the StatefulSet back up to 2:
    ```bash
    kubectl scale statefulset web --replicas=2
    ```
    Watch the pods recreate: they will bind to their exact matching historical volumes (`web-0` binds to `www-web-0`, `web-1` to `www-web-1`), recovering their state.

---

## 🧹 Cleaning Up

After completing this section, clean up all configuration, storage, and stateful resources:

```bash
kubectl delete -f manifests/ --ignore-not-found      # admin/ is not included (not recursive)
kubectl delete pvc www-web-0 www-web-1 --ignore-not-found   # StatefulSet claims are never auto-deleted
kubectl delete pod tmp-dns
kubectl delete configmap app-config-file app-config-literal --ignore-not-found
kubectl delete secret app-secret-literal --ignore-not-found
```
