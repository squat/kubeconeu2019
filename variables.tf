variable "cluster_name" {
  type        = "string"
  description = "Unique cluster name (prepended to dns_zone)"
}

variable "digitalocean_region" {
  type        = "string"
  description = "DigitalOcean Region (e.g. nyc3)"
}

variable "worker_count" {
  type        = "string"
  description = "Number of workers"
}

variable "gpu_worker_count" {
  type        = "string"
  description = "Number of workers"
}

variable "gpu_worker_type" {
  type        = "string"
  description = "Type of GPU workers"
}

variable "dns_zone" {
  type        = "string"
  description = "Digital Ocean domain (i.e. DNS zone) (e.g. do.example.com)"
}

variable "os_image" {
  type        = "string"
  description = "Container Linux image for compute instances (e.g. coreos-stable)"
}

variable "ssh_authorized_key" {
  type        = "string"
  description = "SSH public key for user 'core'"
}

variable "ssh_fingerprint" {
  type        = "string"
  description = "SSH public key fingerprint 'core'"
}

variable "pod_cidr" {
  description = "CIDR IPv4 range to assign Kubernetes pods"
  type        = "string"
  default     = "10.2.0.0/16"
}

variable "service_cidr" {
  description = <<EOD
CIDR IPv4 range to assign Kubernetes services.
The 1st IP will be reserved for kube_apiserver, the 10th IP will be reserved for coredns.
EOD

  type    = "string"
  default = "10.3.0.0/16"
}

variable "asset_dir" {
  description = "Path to a directory where generated assets should be placed (contains secrets)"
  type        = "string"
}

variable "host_cidr" {
  description = "CIDR IPv4 range to assign to EC2 nodes"
  type        = "string"
  default     = "10.0.0.0/16"
}

variable "worker_target_groups" {
  type        = "list"
  description = "Additional target group ARNs to which worker instances should be added"
  default     = []
}
