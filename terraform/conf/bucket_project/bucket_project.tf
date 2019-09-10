resource "google_storage_bucket" "bucket_project-assets" {
  name     = "bucket_project-assets"
  location = "europe-west4"
  labels {
    team = "${var.project_shortname}"
    created_by = "terraform"
  }
  force_destroy = true
}

resource "google_storage_bucket_acl" "bucket_project-assets-acl" {
  bucket = "${google_storage_bucket.bucket_project-assets.name}"

  role_entity = [
    "OWNER:project-owners-637281463921",
    "OWNER:project-editors-637281463921",
    "READER:project-viewers-637281463921",
    "READER:allUsers",

  ]
}
