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
Look at the **`CONTAINER-RUNTIME`** column. If you deployed your cluster using the GKE setup from Section 3, you will see `containerd://1.7.x-gke...`.

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
kubectl run nginx-imperative --image=nginx:1.25-alpine
```
*Verify it is running:*
```bash
kubectl get pods
```

#### 1.2.2 The Declarative Way (YAML Configuration)
Review the file [pod-single.yaml](file:///Users/chasechristensen/scaling-the-kubernetes-mountain/section%204/manifests/pod-single.yaml):
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
    image: nginx:1.25-alpine
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

Review [pod-multi.yaml](file:///Users/chasechristensen/scaling-the-kubernetes-mountain/section%204/manifests/pod-multi.yaml). It defines a web-server container and a sidecar container that generates content and writes it to a shared `emptyDir` volume.

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
1.  Create a new namespace imperatively:
    ```bash
    kubectl create namespace practice-ns
    ```
2.  Deploy a pod inside the new namespace:
    ```bash
    kubectl run nginx-isolated --image=nginx:1.25-alpine -n practice-ns
    ```
3.  Check if the pod is visible in your default view:
    ```bash
    kubectl get pods
    ```
    *(The pod will not appear, because you are currently looking at the `default` namespace).*
4.  Query the namespace explicitly:
    ```bash
    kubectl get pods -n practice-ns
    ```

---

## 🔄 Module 2: Application Lifecycle Management (Deployments & ReplicaSets)

In production, you rarely deploy Pods directly. Instead, you use controllers like **ReplicaSets** and **Deployments** to manage scaling, health, self-healing, and rolling updates.

### 2.1 ReplicaSets

A **ReplicaSet**'s purpose is to maintain a stable, running set of replica Pods at any given time.

1.  Review and deploy [replicaset.yaml](file:///Users/chasechristensen/scaling-the-kubernetes-mountain/section%204/manifests/replicaset.yaml):
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
kubectl create deployment nginx-deployment --image=nginx:1.25-alpine --replicas=2 --dry-run=client -o yaml > dry-run-deployment.yaml
```
*Inspect `dry-run-deployment.yaml` to see how easy it is to generate clean YAML skeleton configurations.*

#### 2.2.2 Deploy and Inspect a Deployment
Deploy the pre-written [deployment.yaml](file:///Users/chasechristensen/scaling-the-kubernetes-mountain/section%204/manifests/deployment.yaml):
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

#### 2.3.1 Scaling a Deployment
*   **The Imperative Way** (Instant scaling):
    ```bash
    kubectl scale deployment nginx-deployment --replicas=4
    ```
    *Verify:* `kubectl get pods` (you should now see 4 pods).
*   **The Declarative Way**:
    Open [deployment.yaml](file:///Users/chasechristensen/scaling-the-kubernetes-mountain/section%204/manifests/deployment.yaml) and modify `replicas: 2` to `replicas: 3`. Apply the changes:
    ```bash
    kubectl apply -f manifests/deployment.yaml
    ```
    *Verify:* `kubectl get pods` (the count reconciles back to 3).

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
    Open [deployment.yaml](file:///Users/chasechristensen/scaling-the-kubernetes-mountain/section%204/manifests/deployment.yaml) in your editor and update the container image from `nginx:1.25-alpine` to `nginx:1.26-alpine`. Apply the update:
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
    kubectl run tmp-client --image=busybox:1.36 --restart=Never -- sleep 3600
    ```
2.  Retrieve the IP address of `nginx-single`:
    ```bash
    kubectl get pod nginx-single -o custom-columns=IP:.status.podIP
    ```
    *(Let's assume the IP is `10.244.1.5`).*
3.  **Test Pod DNS**:
    From inside your `tmp-client` container, query the DNS name of the pod. Replace dots in the IP with hyphens (`10-244-1-5`):
    ```bash
    kubectl exec tmp-client -- nslookup 10-244-1-5.default.pod.cluster.local
    ```
    *CoreDNS will successfully resolve the DNS entry back to the Pod IP.*

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
Review and deploy [service-clusterip.yaml](file:///Users/chasechristensen/scaling-the-kubernetes-mountain/section%204/manifests/service-clusterip.yaml):
```bash
kubectl apply -f manifests/service-clusterip.yaml
```

#### 3.3.3 Inspecting Service Endpoints
A Service routes traffic to Pods using a dynamic tracking resource called **Endpoints**:
```bash
# Get service details
kubectl get svc nginx-clusterip

# Get endpoints linked to the service
kubectl get endpoints nginx-clusterip
```
*(Notice that the endpoints list contains the exact internal IP addresses of all pods managed by the `nginx-deployment`)*.

#### 3.3.4 Test Service DNS Resolution
From the `tmp-client` pod, check if the service name resolves to the stable ClusterIP:
```bash
kubectl exec tmp-client -- nslookup nginx-clusterip
```
Test web traffic routing via the service name:
```bash
kubectl exec tmp-client -- wget -O- http://nginx-clusterip
```

---

### 3.4 Traffic Exposure (NodePort & Port Forwarding)

A **NodePort Service** exposes the service on each Node's IP at a statically allocated port in the `30000-32767` range. This allows external clients to connect to your cluster.

1.  Review and deploy [service-nodeport.yaml](file:///Users/chasechristensen/scaling-the-kubernetes-mountain/section%204/manifests/service-nodeport.yaml):
    ```bash
    kubectl apply -f manifests/service-nodeport.yaml
    ```
2.  Find the dynamically allocated port assigned by Kubernetes:
    ```bash
    kubectl get svc nginx-nodeport
    ```
    *Look at the `PORT(S)` column. It will show something like `80:31942/TCP`. In this case, `31942` is the NodePort.*

3.  **Accessing NodePort**:
    If you are running GKE, node IPs are protected by default cloud firewalls. However, any local VM or routing client can access the web application by running:
    ```bash
    curl http://<ANY_NODE_PUBLIC_IP>:<ASSIGNED_NODEPORT>
    ```

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
kubectl delete namespace practice-ns
```
