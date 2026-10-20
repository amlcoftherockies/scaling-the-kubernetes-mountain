# Section 4: Kubernetes Core Concepts (Pods, Deployments, and Networking)

Welcome to Section 4 of the Kubernetes Scaling Workshop! 

This section covers the core concepts required for the **CKAD (Certified Kubernetes Application Developer)** exam. We will explore **Pods, Containers, Runtimes, Deployments, ReplicaSets, Services, and Networking**.

For each concept, you will practice:
1.  **The Imperative Way**: Creating resources quickly using `kubectl` CLI commands (essential for saving time during the CKAD exam).
2.  **The Declarative Way**: Defining resources in YAML manifests and applying them (essential for real-world production setups).
3.  **State Inspection**: Investigating resources using `kubectl describe`, `-o yaml`, and `kubectl get -w` to understand the difference between the **desired state** (what you configured) and the **deployed state** (what is actually running).

---

## 📦 Module 1: Pods, Containers, and Runtimes

A **Pod** is the smallest deployable unit in Kubernetes. It represents a single instance of a running process and can contain one or more tightly coupled containers.

### 1.1 Container Runtime Interface (CRI)

The Kubernetes control plane communicates with the container runtime (e.g., `containerd` or `CRI-O`) on each node via the **CRI** to manage container lifecycles.

#### How to Inspect the Active Container Runtime:
Run the following command on your local machine:
```bash
kubectl get nodes -o wide
```
Look at the **`CONTAINER-RUNTIME`** column. Depending on your cluster you will see `containerd://1.x.x` (GKE, most clusters) or `cri-o://1.x.x` (Oracle OKE). Kubernetes doesn't care which one: both speak the same CRI.

> [!NOTE]
> On the shared workshop cluster you have **read-only** access to nodes: `get` and `describe` work, but changing nodes doesn't.

> [!NOTE]
> On self-managed clusters (like the `kubeadm` setup), if you SSH directly into a node, you can use the low-level **`crictl`** command-line tool (which is pre-configured to talk to the CRI socket) to inspect containers:
> ```bash
> # Run these on a node VM:
> sudo crictl info
> sudo crictl ps
> ```

---

### 1.2 Pod Fundamentals

#### 1.2.1 The Imperative Way (Fast Deployment)
Generate and deploy a single Nginx pod instantly:
```bash
kubectl run nginx-imperative --image=docker.io/library/nginx:1.25-alpine
```
*Verify it is running:*
```bash
kubectl get pods
```

#### 1.2.2 The Declarative Way (YAML Configuration)
Review the file [pod-single.yaml](manifests/pod-single.yaml):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-single
  labels:
    app: web-server
spec:
  containers:
  - name: nginx
    image: docker.io/library/nginx:1.25-alpine
    ports:
    - containerPort: 80
```
Deploy the manifest:
```bash
kubectl apply -f manifests/pod-single.yaml
```

#### 1.2.3 Inspecting Deployed vs. Desired State
To inspect the detailed state of a running resource, output it as YAML:
```bash
kubectl get pod nginx-single -o yaml
```
*   **Desired State**: Defined in the **`spec`** block. This is the blueprint you submitted.
*   **Deployed (Actual) State**: Stored in the **`status`** block. It contains dynamic information like `podIP`, `phase: Running`, container statuses, start times, and node placement.

#### 1.2.4 Multi-Container Pods (Shared Network & Storage)
Containers inside a single Pod share the same network namespace (they share the same IP address and can talk to each other via `localhost`) and can share volumes.

Review [pod-multi.yaml](manifests/pod-multi.yaml). It defines a web-server container and a sidecar container that generates content and writes it to a shared `emptyDir` volume.

Deploy the multi-container pod:
```bash
kubectl apply -f manifests/pod-multi.yaml
```
Verify that both containers in the pod are ready (`READY 2/2`):
```bash
kubectl get pods
```
Verify they share storage. SSH/exec into the `web-server` container to check if it serves the file written by the `content-generator` container:
```bash
kubectl exec nginx-multi -c web-server -- wget -O- http://localhost:80
```
*You should see output similar to:*
`Hello from the Sidecar Container! Time: Tue May 26 15:35:10 UTC 2026`

---

### 1.3 Isolation (Linux Kernel Namespaces vs. Kubernetes Namespaces)

Kubernetes achieves container isolation using native Linux Kernel features:
*   **Cgroups (Control Groups)**: Directs resource usage (CPU, memory, disk I/O limit).
*   **Linux Namespaces**: Partitions kernel resources (Processes, Network interfaces, Mount points) so a process in a container cannot see processes or networks in other containers.

At the cluster layer, Kubernetes provides **Namespaces** to logically partition resources and scope access control.

#### Hands-On: Namespace Isolation

> [!NOTE]
> **Shared workshop cluster:** you can't create namespaces. You've been given one, and it's already your default. Steps 1–2 will return `Forbidden`, which is the isolation lesson itself. Do steps 3–4 with `kube-system` instead of `practice-ns`. On **your own cluster** you're the admin, and every step works.

1.  Create a new namespace imperatively:
    ```bash
    kubectl create namespace practice-ns
    ```
2.  Deploy a pod inside the new namespace:
    ```bash
    kubectl run nginx-isolated --image=docker.io/library/nginx:1.25-alpine -n practice-ns
    ```
3.  Check whether the pod is visible in your default view:
    ```bash
    kubectl get pods
    ```
    *(The pod won't appear: `kubectl` only shows your current namespace. Check which one that is with `kubectl config view --minify -o jsonpath='{..namespace}'`.)*
4.  Query the namespace explicitly:
    ```bash
    kubectl get pods -n practice-ns
    ```

---

### 1.4 Working with Labels (Imperative vs. Declarative)

**Labels** are key-value pairs attached to Kubernetes objects (like Pods). They do not provide direct function to the container, but are used to organize resources and select subsets of objects.

#### 1.4.1 The Imperative Way
You can add, update, and remove labels on running Pods directly using the `kubectl label` command:

```bash
# Add a label 'env=prod' to a pod
kubectl label pod nginx-single env=prod

# View all labels on your pods
kubectl get pods --show-labels

# Query/filter pods using a label selector (-l)
kubectl get pods -l env=prod

# Update/overwrite an existing label (requires --overwrite flag)
kubectl label pod nginx-single env=dev --overwrite

# Verify the label changed
kubectl get pods -l env=dev

# Remove a label (append a minus '-' sign to the key)
kubectl label pod nginx-single env-

# Verify the label is gone
kubectl get pods --show-labels
```

#### 1.4.2 The Declarative Way
In production, labels are defined inside the YAML manifest.
1. Open [pod-single.yaml](manifests/pod-single.yaml) in your editor.
2. Add a new label under `metadata.labels`:
   ```yaml
   metadata:
     name: nginx-single
     labels:
       app: web-server
       stage: training
   ```
3. Apply the changes:
   ```bash
   kubectl apply -f manifests/pod-single.yaml
   ```
4. Verify the label was added dynamically:
   ```bash
   kubectl get pod nginx-single --show-labels
   ```

---

### 1.5 Reading Container Logs

Reading container logs is one of the most critical troubleshooting skills for the CKAD.

#### 1.5.1 Single-Container Pod Logs
To view stdout/stderr from a standard single-container pod:
```bash
# Dump all current logs
kubectl logs nginx-single

# Stream logs in real-time (follow)
kubectl logs -f nginx-single

# View only the last 10 lines of logs
kubectl logs nginx-single --tail=10

# View logs from a container that recently crashed (previous run)
kubectl logs nginx-single --previous # Or -p
```

#### 1.5.2 Multi-Container Pod Logs
If a pod has more than one container, you **must** specify which container you want to query using the `-c` (or `--container`) flag. If you do not, the command will error.

Try running this:
```bash
# This will fail and list the container names:
kubectl logs nginx-multi
```
Now, retrieve logs from each specific container:
```bash
# View logs from the web server container
kubectl logs nginx-multi -c web-server

# View logs from the background content-generator sidecar
kubectl logs nginx-multi -c content-generator
```

---

## 🔄 Module 2: Application Lifecycle Management (Deployments & ReplicaSets)

In production, you rarely deploy Pods directly. Instead, you use controllers like **ReplicaSets** and **Deployments** to manage scaling, health, self-healing, and rolling updates.

### 2.1 ReplicaSets

A **ReplicaSet**'s purpose is to maintain a stable, running set of replica Pods at any given time.

1.  Review and deploy [replicaset.yaml](manifests/replicaset.yaml):
    ```bash
    kubectl apply -f manifests/replicaset.yaml
    ```
2.  Inspect the ReplicaSet and its pods:
    ```bash
    kubectl get replicaset
    kubectl get pods --show-labels
    ```
    *(Observe that 3 pods were spun up with the label `app=rs-web` matching the ReplicaSet selector).*

3.  **Self-Healing Experiment**:
    Open a second terminal window and watch the pods in real-time:
    ```bash
    kubectl get pods -w
    ```
    In your first terminal, manually delete one of the ReplicaSet pods:
    ```bash
    kubectl delete pod <name-of-one-replicaset-pod>
    ```
    *Observe that the moment the deletion begins, the ReplicaSet controller detects the difference between the desired state (3) and the actual state (2), and instantly triggers the creation of a replacement pod.*

---

### 2.2 Declarative Deployments

A **Deployment** wraps around a ReplicaSet. It provides declarative updates for Pods and ReplicaSets, enabling rolling releases and rollbacks.

#### 2.2.1 CKAD Tip: Generate a manifest template imperatively
Rather than writing YAML from scratch, you can generate a template:
```bash
kubectl create deployment nginx-deployment --image=docker.io/library/nginx:1.25-alpine --replicas=2 --dry-run=client -o yaml > dry-run-deployment.yaml
```
*Inspect `dry-run-deployment.yaml` to see how easy it is to generate clean YAML skeleton configurations.*

#### 2.2.2 Deploy and Inspect a Deployment
Deploy the pre-written [deployment.yaml](manifests/deployment.yaml):
```bash
kubectl apply -f manifests/deployment.yaml
```
Verify the hierarchy:
```bash
# Check the deployment
kubectl get deployments

# Check the ReplicaSet automatically generated by the Deployment
kubectl get replicasets

# Check the pods generated by the ReplicaSet
kubectl get pods
```

---

### 2.3 Scaling and Self-Healing

#### 2.3.1 Scaling a Deployment Up and Down
Scaling changes the **desired state** (number of replicas) of your deployment. The deployment controller will immediately spin up or terminate pods to reconcile the actual state.

*   **The Imperative Way (Scale Up to 5)**:
    Let's scale our deployment up to 5 replicas:
    ```bash
    kubectl scale deployment nginx-deployment --replicas=5
    ```
    *Track the scale-up in real-time:*
    ```bash
    kubectl rollout status deployment/nginx-deployment
    ```
    *Verify that you have 5 pods running:*
    ```bash
    kubectl get pods -l app=deploy-web
    ```

*   **The Declarative Way (Scale Down to 3)**:
    1. Open [deployment.yaml](manifests/deployment.yaml) in your editor.
    2. Change `replicas: 2` to `replicas: 3`.
    3. Apply the modified manifest:
       ```bash
       kubectl apply -f manifests/deployment.yaml
       ```
    4. Watch the deployment controller terminate 2 excess pods to match the new desired state:
       ```bash
       kubectl get pods -l app=deploy-web -w
       ```

#### 2.3.2 Self-Healing with Liveness Probes
Our Deployment configuration contains a **Liveness Probe**:
```yaml
livenessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 5
  periodSeconds: 5
```
This instructs the Node's `kubelet` agent to query `/` on port 80 every 5 seconds. If the container returns a failure code (or doesn't respond), Kubernetes will restart the container.

Let's break one of the pods to watch self-healing in action:
1.  Get the names of your deployment pods:
    ```bash
    kubectl get pods -l app=deploy-web
    ```
2.  SSH/exec into one of the pods and delete the index file. This will cause Nginx to return a `403 Forbidden` response:
    ```bash
    kubectl exec -it <nginx-deployment-pod-name> -- rm /usr/share/nginx/html/index.html
    ```
3.  Monitor the pod status immediately:
    ```bash
    kubectl get pods -l app=deploy-web -w
    ```
    *Within 5-10 seconds, the liveness probe fails. You will see the pod status temporarily drop. Once the kubelet restarts the container, it transitions back to `Running` and the `RESTARTS` count increments to `1`:*
    ```text
    NAME                                READY   STATUS    RESTARTS   AGE
    nginx-deployment-85b4f6587c-xxxxx   1/1     Running   1          3m
    ```

---

### 2.4 Automated Rollouts (Rolling Updates)

When you modify the Pod Template spec of a Deployment (such as updating an image version), the Deployment controller triggers a **Rolling Update**. It replaces old pods with new pods at a controlled rate, ensuring zero downtime.

1.  **Declaratively Trigger a Rollout**:
    Open [deployment.yaml](manifests/deployment.yaml) in your editor and update the container image from `nginx:1.25-alpine` to `nginx:1.26-alpine`. Apply the update:
    ```bash
    kubectl apply -f manifests/deployment.yaml
    ```
2.  **Monitor the Rollout Status**:
    ```bash
    kubectl rollout status deployment/nginx-deployment
    ```
    *(Observe that new pods are created and initialized before old ones are terminated).*

3.  **Inspect Rollout History**:
    ```bash
    kubectl rollout history deployment/nginx-deployment
    ```
4.  **Perform an Undo (Rollback)**:
    If a rollout goes wrong, you can undo it immediately:
    ```bash
    kubectl rollout undo deployment/nginx-deployment
    ```
    *Verify the rollout status to watch it roll back to the previous image version.*

---

## 🌐 Module 3: Networking and Service Discovery

By default, Pod IP addresses are ephemeral. If a Pod is restarted or rescheduled, it receives a new IP address. We use **Services** to provide stable endpoints.

### 3.1 Pod Networking (Shared IPs)

Kubernetes allocates a unique IP address to every Pod. 
1.  Inspect the IP addresses of your deployed pods:
    ```bash
    kubectl get pods -o wide
    ```
2.  Compare the IPs. Note that `nginx-multi` has a single IP, meaning both internal containers (`web-server` and `content-generator`) share this single address.

---

### 3.2 DNS Resolution inside the Cluster

Kubernetes runs a cluster-dns service (CoreDNS) that automatically registers hostnames for services and pods.

1.  Spin up a temporary busybox client pod:
    ```bash
    kubectl run tmp-client --image=docker.io/library/busybox:1.36 --restart=Never -- sleep 3600
    ```
2.  Retrieve the IP address of `nginx-single`, and your current namespace:
    ```bash
    kubectl get pod nginx-single -o custom-columns=IP:.status.podIP
    NS=$(kubectl config view --minify -o jsonpath='{..namespace}'); NS=${NS:-default}; echo $NS
    ```
    *(Let's assume the IP is `10.244.1.5`.)*
3.  **Test Pod DNS**:
    From inside your `tmp-client` container, query the DNS name of the pod. Replace the dots in the IP with hyphens (`10-244-1-5`):
    ```bash
    kubectl exec tmp-client -- nslookup 10-244-1-5.$NS.pod.cluster.local
    ```
    *CoreDNS resolves the name back to the Pod IP.*

---

### 3.3 Kubernetes Services (ClusterIP)

A **ClusterIP Service** exposes the application on a stable virtual IP internal to the cluster. Traffic sent to this IP is load-balanced across the matching Pods.

#### 3.3.1 The Imperative Way (Fast Exposure)
Expose the deployment instantly:
```bash
kubectl expose deployment nginx-deployment --name=nginx-imperative-svc --port=80 --target-port=80
```
*Verify it exists:*
```bash
kubectl get svc nginx-imperative-svc
```

#### 3.3.2 The Declarative Way
Review and deploy [service-clusterip.yaml](manifests/service-clusterip.yaml):
```bash
kubectl apply -f manifests/service-clusterip.yaml
```

#### 3.3.3 Inspecting Endpoints (How Services Track Pods)
A Service load-balances traffic across multiple Pods. It tracks which Pods are active and healthy using an internal resource called **Endpoints** (or `EndpointSlices`).

Whenever a Pod matching the Service selector is created, destroyed, or fails a readiness check, Kubernetes automatically updates the Endpoints list.

1.  Inspect the Service definition and look at its IP mapping:
    ```bash
    kubectl get svc nginx-clusterip
    ```
2.  View the linked Endpoints. Note the list of IP addresses matches your deployment Pods:
    ```bash
    kubectl get endpoints nginx-clusterip
    ```
    *Output will look similar to:*
    ```text
    NAME              ENDPOINTS                                   AGE
    nginx-clusterip   10.244.1.8:80,10.244.1.9:80,10.244.1.10:80   5m
    ```

3.  **Hands-On Demonstration of Dynamic Endpoints**:
    Let's watch how scaling changes our endpoints in real-time.
    *   In a second terminal window, watch the endpoints:
        ```bash
        kubectl get endpoints nginx-clusterip -w
        ```
    *   In your main terminal, scale up the deployment:
        ```bash
        kubectl scale deployment nginx-deployment --replicas=5
        ```
    *   Go back to the watching terminal. Notice how the IPs of the new Pods are automatically appended to the endpoints list.
    *   Scale the deployment back down to 2:
        ```bash
        kubectl scale deployment nginx-deployment --replicas=2
        ```
        *Observe the IPs instantly being removed from the endpoints list. This decoupling prevents your frontend clients from trying to connect to dead container IPs!*

#### 3.3.4 Test DNS Resolution & Service Connectivity
CoreDNS provides internal hostname resolution inside the cluster.

*   **Service DNS Name Format**: `<service-name>.<namespace>.svc.cluster.local`
*   **Pod DNS Name Format**: `<pod-ip-with-hyphens>.<namespace>.pod.cluster.local`

1.  SSH/exec into the `tmp-client` testing pod:
    ```bash
    kubectl exec -it tmp-client -- sh
    ```
2.  Resolve the Service name:
    ```bash
    nslookup nginx-clusterip
    ```
    *(This returns the stable virtual ClusterIP of the Service. On cloud clusters busybox may also print `** server can't find ...: NXDOMAIN` for extra search domains, such as `*.internal`, and exit 1. Ignore those lines: the first `Name:`/`Address:` answer is the one that matters.)*
3.  Perform a network query using the service name. Traffic is automatically distributed to one of the active backend pods:
    ```bash
    wget -O- http://nginx-clusterip
    ```
4.  Exit the pod shell:
    ```bash
    exit
    ```

---

### 3.4 Traffic Exposure (NodePort, LoadBalancer & Port Forwarding)

A **NodePort Service** exposes the service on each Node's IP at a statically allocated port in the `30000-32767` range. This allows external clients to connect to your cluster.

1.  Review and deploy [service-nodeport.yaml](manifests/service-nodeport.yaml):
    ```bash
    kubectl apply -f manifests/service-nodeport.yaml
    ```
2.  Find the dynamically allocated port assigned by Kubernetes:
    ```bash
    kubectl get svc nginx-nodeport
    ```
    *Look at the `PORT(S)` column. It will show something like `80:31942/TCP`. In this case, `31942` is the NodePort.*

3.  **Accessing NodePort**:
    Workshop clusters (OKE and GKE alike) keep worker nodes in a **private network with no public IPs**, so you can't reach a NodePort from your laptop directly. Prove the NodePort works from *inside* the cluster network by calling a node's internal IP:
    ```bash
    # Grab one node's INTERNAL-IP
    kubectl get nodes -o wide

    # Call the NodePort from a throwaway pod
    kubectl run np-test --rm -it --image=docker.io/library/busybox:1.36 --restart=Never -- \
      wget -qO- http://<NODE_INTERNAL_IP>:<ASSIGNED_NODEPORT>
    ```
    *On a cluster whose nodes do have public IPs (and a firewall rule allowing the port), `curl http://<NODE_PUBLIC_IP>:<NODEPORT>` works from anywhere.*

4.  **Exposing to the Internet with a LoadBalancer**:
    This is how many clusters publish apps. A `type: LoadBalancer` Service is a NodePort Service *plus* a cloud load balancer that forwards to those NodePorts. Change the existing Service's type in place:
    ```bash
    kubectl patch svc nginx-nodeport -p '{"spec":{"type":"LoadBalancer"}}'
    kubectl get svc nginx-nodeport -w   # wait for EXTERNAL-IP (1-3 min), then Ctrl+C
    curl http://<EXTERNAL-IP>
    ```
    *Notice the NodePort number in `PORT(S)` didn't change: the cloud load balancer simply sends traffic to it on every node.*

    Load balancers cost money while they exist, so switch it back when you're done:
    ```bash
    kubectl patch svc nginx-nodeport -p '{"spec":{"type":"NodePort"}}'
    ```

    > [!NOTE]
    > **Shared workshop cluster:** the patch fails with `exceeded quota: ... services.loadbalancers=0`. That's on purpose: 30 people × 1 load balancer each would be slow and expensive. Instead, everyone shares **one** load balancer and attaches their app to it with an HTTPRoute or Ingress on their own hostname. That's the [shared Gateway](../section%203/gke/README.md#expose-an-application-shared-gateway), and it's how most production clusters do it too.

#### 🔌 Pro-Tip: Port Forwarding (Quick local testing)
During CKAD exams or local dev work, instead of setting up NodePorts or LoadBalancers, you can tunnel traffic from your local host port directly to the Service:
```bash
kubectl port-forward svc/nginx-clusterip 8080:80
```
*Open a web browser on your local laptop and navigate to `http://localhost:8080` to see the Nginx welcome page.* (Press `Ctrl+C` to terminate the tunnel).

---

## 🧹 Cleaning Up

After finishing this section, clean up all practice resources:
```bash
kubectl delete -f manifests/
kubectl delete pod tmp-client nginx-imperative
kubectl delete svc nginx-imperative-svc
kubectl delete namespace practice-ns   # own cluster only (on the shared cluster you never created it)
```
