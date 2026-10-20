# -- the three values you set in terraform.tfvars ----------------------------

variable "lab_compartment_ocid" {
  description = "OCID of the workshop (parent) compartment. Prefilled in terraform.tfvars.example -- leave it."
  type        = string
  validation {
    condition     = startswith(var.lab_compartment_ocid, "ocid1.compartment.")
    error_message = "lab_compartment_ocid must start with ocid1.compartment. -- copy it from terraform.tfvars.example."
  }
}

variable "email" {
  description = "The email address your Oracle Cloud invite was sent to. Used to find your own compartment (lab:<email with @ -> _>)."
  type        = string
  validation {
    condition     = !strcontains(var.email, "CHANGEME") && can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.email))
    error_message = "Set email to the address your invite was sent to, e.g. jsmith@example.com."
  }
}

variable "oci_profile" {
  description = "Profile in ~/.oci/config to authenticate with. `oci setup bootstrap` creates DEFAULT unless you named it otherwise."
  type        = string
  default     = "DEFAULT"
}

# -- defaults you normally leave alone ----------------------------------------

variable "region" {
  description = "Region the workshop runs in."
  type        = string
  default     = "us-ashburn-1"
}

variable "kubernetes_version" {
  description = "Kubernetes version, e.g. \"v1.31.1\". Empty = newest version OKE offers."
  type        = string
  default     = ""
}

variable "node_count" {
  description = "Worker nodes. Two lets you see scheduling across nodes while staying inside your compartment quota."
  type        = number
  default     = 2
}

variable "node_ocpus" {
  description = "OCPUs per node (1 OCPU = 2 vCPUs on AMD E5)."
  type        = number
  default     = 1
}

variable "node_memory_gbs" {
  description = "Memory per node in GB."
  type        = number
  default     = 8
}

variable "api_allowed_cidr" {
  description = "Who may reach the Kubernetes API on 6443. Open by default (OCI auth is still required)."
  type        = string
  default     = "0.0.0.0/0"
}
