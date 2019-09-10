/**
Custom node pool
*/
resource "google_container_node_pool" "node-pool" {
  name        = "${var.cluster_name}-pool"
  location    = "${var.gke_location}"
  cluster     = "${google_container_cluster.gke_cluster.name}"
  node_count = "${var.min_application_nodes}"

  node_config {
    machine_type = "${var.node_machine_type}"
    disk_size_gb = "${var.node_disk_size}"
    image_type   = "COS"
    disk_type  =  "pd-ssd"
    preemptible  = false
    oauth_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
       "https://www.googleapis.com/auth/monitoring"
    ]
  }

  autoscaling {
    min_node_count  = "${var.min_application_nodes}"
    max_node_count  = "${var.max_application_nodes}"
  }
  management {
    auto_repair  = "${var.node_auto_repair}"
    auto_upgrade = "${var.node_auto_upgrade}"
  }
}
