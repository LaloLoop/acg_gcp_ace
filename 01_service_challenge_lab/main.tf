terraform {
    backend "remote" {
        organization = "laloloop"

        workspaces {
            name = "gcp_ace_01_services_challenge"
        }
    }
}

// Enable required APIS

resource "google_project_service" "cloud_resource_manager_api" {
    service = "cloudresourcemanager.googleapis.com"

    disable_dependent_services = false
    disable_on_destroy = false
}

resource "google_project_service" "compute_engine_api" {
    service "compute.googleapis.com"

    disable_dependent_services = false
    disable_on_destroy = false
}

// Variables

variable "dest-bucket" {
    description = "Destination bucket for logs"
    default = "lab-logs-bucket"
}

// Dest bucket for logs

resource "random_string" "random" {
    length = 8
    special = false
}

resource "google_storage_bucke" "gce-logs" {
    name = "${substr(var.dest-bucket, 0, 75)}-${random_string.result}"
    location = "US"
}

