terraform {
  required_version = ">= 0.11.0"
}

data "vault_generic_secret" "gke_service_account" {
  path = "${var.gke_service_account}"
}

provider "google" {
  credentials = "${data.vault_generic_secret.gke_service_account.data["value"]}"
  project     = "${var.gke_project}"
}

resource "google_compute_network" "compute-network" {
  name                    = "network-${var.cluster_name}"
  auto_create_subnetworks = "false"
}

resource "google_compute_subnetwork" "subnetwork-ip-alias" {
  name          = "subnet-${var.cluster_name}"
  ip_cidr_range = "${var.ipv4_main_range}"
  region    = "${var.gke_region}"
  network       = "${google_compute_network.compute-network.self_link}"
  secondary_ip_range {
    range_name    = "k8s-pods-secondary-range"
    ip_cidr_range = "${var.ipv4_pods_range}"
  }
  secondary_ip_range {
    range_name    = "k8s-services-secondary-range"
    ip_cidr_range = "${var.ipv4_services_range}"
  }
}

resource "google_container_cluster"  "gke_cluster" {
  name               = "${var.cluster_name}"
  description        = "${var.cluster_description}"
  logging_service    = "logging.googleapis.com"
  monitoring_service = "monitoring.googleapis.com"
  location           = "${var.gke_location}"
  min_master_version = "1.13.7-gke.8"
  initial_node_count = 1
  enable_kubernetes_alpha = "false"
  enable_legacy_abac = "false"
  remove_default_node_pool = "true"
  network            = "${google_compute_network.compute-network.self_link}"
  subnetwork         = "${google_compute_subnetwork.subnetwork-ip-alias.self_link}"
  ip_allocation_policy = {
    cluster_secondary_range_name = "k8s-pods-secondary-range"
    services_secondary_range_name  = "k8s-services-secondary-range"
  }
  resource_labels {
    team = "${var.project_shortname}"
    created_by = "terraform"
  }

  addons_config {
    kubernetes_dashboard  {
      disabled = true
    }
  }
}
