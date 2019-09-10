variable "gke_location" {
  description = "GKE region or zone, e.g. us-east1 or us-east1-a"
}

variable "gke_region" {
  description = "GKE region, e.g. us-east1"
}

variable "gke_service_account" {}

variable "gke_project" {
  description = "GKE project name"
}

variable "project_shortname" {
  description = "3 letter squad name. IE, frt"
}

variable "k8s_project_name" {
  description = "Logical squad name. IE, frontend"
}

variable "domain" {
  description = "Project domain name"
}

variable "cluster_name" {
  description = "Name of the K8s cluster"
}

variable "cluster_description" {
  description = "Description of the K8s cluster"
}

variable "node_machine_type" {
  description = "GCE machine type"
}

variable "node_disk_size" {
  description = "Node disk size in GB"
}

variable "environment" {
  description = "value passed to Environment tag"
}

variable "min_application_nodes" {}

variable "max_application_nodes" {}

variable "uuid" {
  description = "Generated to act as a trigger for the bootstrap script"
}

variable "ipv4_main_range" {
  description = "Defines the ip range for the master"
}

variable "ipv4_pods_range" {
  description = "Defines the ip range the pods would get"
}

variable "ipv4_services_range" {
  description = "Defines the ip range the services would get"
}

variable "node_auto_upgrade" {
  description = "Wether the nodes should be upgrading automatically on new stable Kubernetes version (true/fase)"
}

variable "node_auto_repair" {
  description = "Wether the nodes should be repairing automatically on failure (true/fase)"
}

variable "secret_location" {
  description = "Vault secret location"
}
