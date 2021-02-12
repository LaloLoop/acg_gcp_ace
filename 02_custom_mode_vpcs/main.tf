terraform {
  backend "remote" {
      organization = "laloloop"

      workspaces {
          name = "gce_ace_02_custom_mode_vpcs"
      }
  }
  required_providers {
    google = {
        source = "hashicorp/google"
        version = "~> 3.56"
    }
  }
}

// Common variables

locals {
    region = "us-central1"
    tiers = {
        "backend" = google_service_account.backend-sa.email,
        "frontend" = google_service_account.frontend-sa.email
    }
}

// Custom VPC
resource "google_compute_network" "my-custom-net" {
    name = "custom-net"
    description = "Custom network for two-tier setup"
    auto_create_subnetworks = false
    routing_mode = "REGIONAL"
}

// Subnetworks
resource "google_compute_subnetwork" "custom-subnet-0" {
    name = "custom-subnet"
    ip_cidr_range = "10.2.0.0/16"
    description = "Custom subnet for two-tier setup"
    region = local.region
    network = google_compute_network.my-custom-net.id
}

// Accept SSH connections from the internet.
resource "google_compute_firewall" "ssh-firewall" {
    name = "ssh-two-tier-setup"
    network = google_compute_network.my-custom-net.name

    priority = 800

    allow {
        protocol = "tcp"
        ports = [ "22" ]
    }

    source_ranges = [ "0.0.0.0/0" ]

    target_tags = [ "open-ssh-tag" ]
}

// -------- Frontend --------

// Accept incoming from internet
resource "google_compute_firewall" "icmp-frontend-incoming" {
    name = "icmp-frontend-incoming"
    network = google_compute_network.my-custom-net.name

    allow {
        protocol = "icmp"
    }

    priority = 0

    source_ranges = [ "0.0.0.0/0" ]

    target_service_accounts = [
        google_service_account.frontend-sa.email
    ]
}

// Rule to allow outbound connection is ommitted, since it is the default

// -------- Backend --------

// Deny the outbound traffic from the backend
resource "google_compute_firewall" "icmp-backend-outgoing" {
    name = "icmp-backend-outgoing"
    network = google_compute_network.my-custom-net.name

    deny {
        protocol = "all"
    }

    destination_ranges = [ "0.0.0.0/0" ]

    source_service_accounts = [
        google_service_account.backend-sa.email
    ]
}

// Allow incoming traffic from frontend
resource "google_compute_firewall" "icmp-backend-incoming" {
    name = "icmp-backend-incoming"
    network = google_compute_network.my-custom-net.name

    allow {
        protocol = "icmp"
    }

    priority = 900

    source_service_accounts = [
        google_service_account.frontend-sa.email,
        google_service_account.backend-sa.email
    ]

    target_service_accounts = [
        google_service_account.backend-sa.email
    ]
}

// Service accounts

// Frontend
resource "google_service_account" "frontend-sa" {
    account_id = "frontend-sa"
    display_name = "Frontend service account"
}

// Backend
resource "google_service_account" "backend-sa" {
    account_id = "backend-sa"
    display_name = "Backend service account"
}

// Compute instances with autoscaling

data "google_compute_image" "debian_9" {
    family = "debian-9"
    project = "debian-cloud"
}

resource "google_compute_instance_template" "instance_template" {
    for_each = local.tiers
    name = "${each.key}-instance-template"
    machine_type = "f1-micro"
    
    disk {
      source_image = data.google_compute_image.debian_9.id
    }

    network_interface {
      network = google_compute_network.my-custom-net.name
      subnetwork = google_compute_subnetwork.custom-subnet-0.name
    }

    service_account {
        email = each.value
        scopes = []
    }
}

resource "google_compute_target_pool" "target-pool" {
    for_each = local.tiers
    name = "${each.key}-target-pool"
}

resource "google_compute_region_instance_group_manager" "instance_group_manager" {
    for_each = local.tiers
    name = "${each.key}-igm"
    region = local.region

    version {
        instance_template = google_compute_instance_template.instance_template["${each.key}"].id
        name = "primary"
    }

    target_pools = [ google_compute_target_pool.target-pool["${each.key}"].id ]
    base_instance_name = each.key
}

resource "google_compute_region_autoscaler" "region-autoscaler" {
    for_each = local.tiers
    name = "${each.key}-autoscaler"
    region = local.region
    target = google_compute_region_instance_group_manager.instance_group_manager["${each.key}"].id

    autoscaling_policy {
      max_replicas = 4
      min_replicas = 3
      cooldown_period = 60

      cpu_utilization {
        target = 0.5
      }
    }
}