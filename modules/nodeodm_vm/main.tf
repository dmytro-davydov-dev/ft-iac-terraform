# ---------------------------------------------------------------------------
# NodeODM VM — GCP Spot VM (n1-standard-4 + T4 GPU)
#
# Runs the NodeODM Docker container (port 3000) for drone image processing.
# Only reachable from the ft-api Cloud Run service account (TCP 3000).
# NodeODM token auth pulled from Secret Manager at startup.
# Logs forwarded to Cloud Logging via the gcplogs Docker driver.
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
# Service account for the NodeODM VM
# ---------------------------------------------------------------------------

resource "google_service_account" "nodeodm" {
  project      = var.project_id
  account_id   = "flowterra-nodeodm-vm"
  display_name = "Flowterra NodeODM VM"
  description  = "Workload identity for the NodeODM Spot VM."
}

# Read NODE_ODM_TOKEN from Secret Manager
resource "google_project_iam_member" "nodeodm_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.nodeodm.email}"
}

# Write container logs to Cloud Logging (used by gcplogs Docker driver)
resource "google_project_iam_member" "nodeodm_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.nodeodm.email}"
}

# ---------------------------------------------------------------------------
# Firewall rules
# ---------------------------------------------------------------------------

# TCP 3000 — NodeODM API, allowed from ft-api Cloud Run SA only
resource "google_compute_firewall" "nodeodm_allow_cloud_run" {
  project     = var.project_id
  name        = "flowterra-nodeodm-allow-cloud-run"
  network     = var.network
  description = "Allow NodeODM (TCP 3000) from ft-api Cloud Run SA only."

  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }

  source_service_accounts = [var.cloud_run_sa_email]
  target_tags             = ["flowterra-nodeodm"]

  depends_on = [google_project_service.compute]
}

# SSH from Google IAP range only — no direct public SSH
resource "google_compute_firewall" "nodeodm_iap_ssh" {
  project     = var.project_id
  name        = "flowterra-nodeodm-iap-ssh"
  network     = var.network
  description = "Allow SSH from Google IAP range only."

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["flowterra-nodeodm"]

  depends_on = [google_project_service.compute]
}

# ---------------------------------------------------------------------------
# Spot VM instance
# ---------------------------------------------------------------------------

resource "google_compute_instance" "nodeodm" {
  project      = var.project_id
  name         = "flowterra-nodeodm-vm"
  machine_type = "n1-standard-4"
  zone         = var.zone

  labels = var.labels
  tags   = ["flowterra-nodeodm"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 50
      type  = "pd-ssd"
    }
  }

  guest_accelerator {
    type  = "nvidia-tesla-t4"
    count = 1
  }

  # Spot VM — must terminate on host maintenance; no automatic restart
  scheduling {
    provisioning_model  = "SPOT"
    automatic_restart   = false
    on_host_maintenance = "TERMINATE"
  }

  network_interface {
    network = var.network
    # Ephemeral public IP required for outbound calls (Docker pull, Secret Manager,
    # Cloud Logging) until a Cloud NAT gateway is provisioned.
    # The NodeODM API on TCP 3000 is restricted by the firewall to ft-api SA only.
    access_config {}
  }

  service_account {
    email  = google_service_account.nodeodm.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    startup-script = templatefile("${path.module}/startup.sh.tpl", {
      project_id              = var.project_id
      nodeodm_token_secret_id = var.nodeodm_token_secret_id
    })
  }

  # desired_status = "TERMINATED" ensures the VM is stopped by default after
  # provisioning.  vm_manager.py starts/stops it on demand to keep GPU costs
  # at $0/hr when no captures are processing.
  desired_status = "TERMINATED"

  depends_on = [
    google_project_service.compute,
    google_project_iam_member.nodeodm_secret_accessor,
    google_project_iam_member.nodeodm_log_writer,
  ]
}
