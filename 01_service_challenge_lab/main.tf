terraform {
    backend "remote" {
        organization = "laloloop"

        workspaces {
            name = "gcp_ace_01_services_challenge"
        }
    }
    required_providers {
        google = {
            source = "hashicorp/google"
            version = "~> 3.53"
        }
        random = {
            source = "hashicorp/random"
            version = "~> 3.0"
        }
    }
}

// Variables

// variable "gcp-credentials" {
//    description = "GCP access token"
// }

variable "dest-bucket-prefix" {
    description = "Destination bucket for logs"
    default = "lab-logs-bucket"
}

variable "log-viewers" {
    description = "Allowed accounts to view logs"
    default = []
}

// Proviers configuration

// provider "google" {
//    credentials = var.gcp-credentials
// }


// Enable required APIS

resource "google_project_service" "cloud_resource_manager_api" {
    service = "cloudresourcemanager.googleapis.com"

    disable_dependent_services = false
    disable_on_destroy = false
}

resource "google_project_service" "compute_engine_api" {
    service = "compute.googleapis.com"

    disable_dependent_services = false
    disable_on_destroy = false
}

// Destination bucket for logs

resource "random_string" "random" {
    length = 8
    special = false
}

resource "google_storage_bucket" "gce-logs" {
    name = "${substr(var.dest-bucket-prefix, 0, 75)}-${random_string.random.result}"
    location = "US"
}

// Default service account

resource "google_service_account" "default" {
    account_id = "logging-machine"
    display_name = "Logging machine"
}

// Permissions to write

resource "google_storage_bucket_iam_binding" "write-binding" {
  bucket = google_storage_bucket.gce-logs.name
  role = "roles/storage.objectCreator"
  members = [
    "serviceAccount:${google_service_account.default.email}",
  ]
}

// Permissions to view

resource "google_storage_bucket_iam_binding" "view-binding" {
  count = length(var.log-viewers) > 0 ? 1 : 0
  bucket = google_storage_bucket.gce-logs.name
  role = "roles/storage.objectViewer"
  members = var.log-viewers
}

// Main machine

resource "google_compute_instance" "main" {
    name = "logging-vm"
    zone = "us-central1-f"
    machine_type = "f1-micro"

    boot_disk {
        initialize_params {
            size = 20
            image = "ubuntu-2004-lts"
        }
    }

    network_interface {
        network = "default"

        access_config {

        }
    }

    labels = {
        "purpose"="learning",
        "course"="GCP-ACE"
    }

    metadata = {
        "lab-logs-bucket" = google_storage_bucket.gce-logs.name
    }

    metadata_startup_script = file("./scripts/startup.sh")

    service_account {
        email = google_service_account.default.email
        scopes = ["cloud-platform"]
    }
}