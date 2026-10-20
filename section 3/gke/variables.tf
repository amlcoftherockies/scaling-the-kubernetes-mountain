variable "project_id" {
  description = "GCP project ID to build in, e.g. ckad-lab-511603 (the workshop) or your own project."
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster."
  type        = string
  default     = "ckad-lab"
}

variable "region" {
  description = "Region for the network and NAT."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zone for the cluster. A ZONAL cluster's control-plane fee is covered by GKE's free tier (one per billing account)."
  type        = string
  default     = "us-central1-a"
}

variable "machine_type" {
  description = "Worker node machine type. e2-standard-4 = 4 vCPU / 16 GB."
  type        = string
  default     = "e2-standard-4"
}

variable "min_nodes" {
  description = "Autoscaler minimum. Workshop: 3. Build-your-own: 1."
  type        = number
  default     = 3
}

variable "max_nodes" {
  description = "Autoscaler maximum. Must fit the project's CPU quota: E2 uses the regional CPUS quota, and the global CPUS_ALL_REGIONS quota is 32 on a new project (max 8 x 4 vCPU). Raise both together."
  type        = number
  default     = 5
}

variable "enable_gvisor_pool" {
  description = "Add a small GKE Sandbox (gVisor) node pool so the Section 6 RuntimeClass demo works. Costs one extra node."
  type        = bool
  default     = false
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API. Participants' laptops need access, so open by default (auth is still required)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "budget_amount_usd" {
  description = "Monthly budget alert in USD for the project. 0 disables. Needs billing_account_id."
  type        = number
  default     = 0
}

variable "billing_account_id" {
  description = "Billing account ID (XXXXXX-XXXXXX-XXXXXX), only needed for the budget alert."
  type        = string
  default     = ""
}
