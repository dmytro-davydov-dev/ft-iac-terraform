# ---------------------------------------------------------------------------
# EMQX VM — Managed Instance Group (size=1, auto-heal)
#
# Runs EMQX OSS 5.x on Debian 12 (package install).
# A Python sidecar service subscribes to EMQX on localhost and forwards
# every inbound MQTT message to the flowterra-iot-ingress Pub/Sub topic
# using the VM's service account (ADC — no key file needed).
#
# Firewall: external MQTT/TLS (8883) only. SSH via IAP. Dashboard localhost.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Required APIs
# ---------------------------------------------------------------------------

resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Service account for the EMQX VM
# ---------------------------------------------------------------------------

resource "google_service_account" "emqx" {
  project      = var.project_id
  account_id   = "flowterra-emqx-vm"
  display_name = "Flowterra EMQX VM"
}

# Publish to Pub/Sub (bridge sidecar)
resource "google_project_iam_member" "emqx_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.emqx.email}"
}

# Read MQTT gateway credentials from Secret Manager
resource "google_project_iam_member" "emqx_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.emqx.email}"
}

# Write logs to Cloud Logging
resource "google_project_iam_member" "emqx_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.emqx.email}"
}

# ---------------------------------------------------------------------------
# Firewall rules
# ---------------------------------------------------------------------------

# External: MQTT over TLS only (gateways → broker)
resource "google_compute_firewall" "emqx_mqtt_tls" {
  project     = var.project_id
  name        = "flowterra-emqx-mqtt-tls"
  network     = var.network
  description = "Allow MQTT/TLS (8883) from BLE gateways."

  allow {
    protocol = "tcp"
    ports    = ["8883"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["flowterra-emqx"]

  depends_on = [google_project_service.compute]
}

# SSH from IAP only — no direct public SSH
resource "google_compute_firewall" "emqx_iap_ssh" {
  project     = var.project_id
  name        = "flowterra-emqx-iap-ssh"
  network     = var.network
  description = "Allow SSH from Google IAP range only."

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["flowterra-emqx"]

  depends_on = [google_project_service.compute]
}

# ---------------------------------------------------------------------------
# Instance template
# ---------------------------------------------------------------------------

resource "google_compute_instance_template" "emqx" {
  project      = var.project_id
  name_prefix  = "flowterra-emqx-"
  machine_type = "e2-small"
  region       = var.region

  labels = var.labels
  tags   = ["flowterra-emqx"]

  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
    disk_size_gb = 20
    disk_type    = "pd-standard"
  }

  network_interface {
    network = var.network
    # Ephemeral public IP — required for EMQX → Pub/Sub egress and package installs.
    # Restrict to private IP + Cloud NAT when a NAT gateway is provisioned.
    access_config {}
  }

  service_account {
    email  = google_service_account.emqx.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script = templatefile("${path.module}/startup.sh.tpl", {
      project_id   = var.project_id
      pubsub_topic = var.pubsub_topic
    })
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_project_service.compute,
    google_project_iam_member.emqx_pubsub_publisher,
  ]
}

# ---------------------------------------------------------------------------
# Regional health check (TCP on MQTT/TLS port)
# ---------------------------------------------------------------------------

resource "google_compute_region_health_check" "emqx" {
  project = var.project_id
  name    = "flowterra-emqx-health"
  region  = var.region

  tcp_health_check {
    port = 8883
  }

  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 1
  unhealthy_threshold = 3

  depends_on = [google_project_service.compute]
}

# ---------------------------------------------------------------------------
# Managed Instance Group (size=1, auto-heal)
# ---------------------------------------------------------------------------

resource "google_compute_region_instance_group_manager" "emqx" {
  project            = var.project_id
  name               = "flowterra-emqx-mig"
  region             = var.region
  base_instance_name = "flowterra-emqx"

  version {
    instance_template = google_compute_instance_template.emqx.id
  }

  target_size = 1

  auto_healing_policies {
    health_check      = google_compute_region_health_check.emqx.id
    initial_delay_sec = 180 # allow time for EMQX + bridge to start
  }

  # update_policy omitted — GCP default (OPPORTUNISTIC) is fine for a
  # size=1 MVP MIG. Re-add with zone-aware surge counts before production.
}
