# Only OCI Always Free shapes and sizes are accepted (zero-cost-mvp.md §7):
# validation fails before anything is created.

variable "region" {
  description = "Home region of the tenancy, e.g. eu-frankfurt-1."
  type        = string
}

variable "compartment_ocid" {
  description = "Compartment for all resources (the tenancy OCID for the root compartment)."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for the ubuntu user."
  type        = string
}

variable "admin_cidr" {
  description = "CIDR allowed to reach SSH (22). Empty closes SSH; 443 is the only public port."
  type        = string
  default     = ""
}

variable "ocpus" {
  description = "Ampere A1 OCPUs."
  type        = number
  default     = 2
  validation {
    condition     = var.ocpus >= 1 && var.ocpus <= 2
    error_message = "Always Free allows at most 2 A1 OCPUs (as of 2026); use 1 or 2."
  }
}

variable "memory_gb" {
  description = "Ampere A1 memory in GB."
  type        = number
  default     = 12
  validation {
    condition     = var.memory_gb >= 6 && var.memory_gb <= 12
    error_message = "Always Free allows at most 12 GB of A1 memory (as of 2026)."
  }
}

variable "data_volume_gb" {
  description = "Block volume for ClickHouse, buffers and Postgres (k3s local-path)."
  type        = number
  default     = 100
  validation {
    condition     = var.data_volume_gb >= 50 && var.data_volume_gb <= 150
    error_message = "Keep boot (~47 GB) plus data within the ~200 GB Always Free block storage."
  }
}

variable "bucket_name" {
  description = "Object Storage bucket for the lake and raw archive (S3 API)."
  type        = string
  default     = "fibrik-lake"
}

variable "k3s_version" {
  description = "k3s release installed by cloud-init."
  type        = string
  default     = "v1.37.1+k3s1"
}
