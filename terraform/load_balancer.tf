# Cross-region Global External Application Load Balancer, HTTP-only (port 80), no domain or TLS.
# Backends are standalone zonal NEGs created by the Kubernetes Service `cloud.google.com/neg`
# annotation in kubernetes/manifest.yaml. The NEG data sources only exist once the manifest has
# been deployed to both clusters, so they are gated behind var.enable_load_balancer_backends:
# apply once with it false to get the IP/proxy/forwarding rule, deploy the app, then set it true
# and re-apply to wire in the real backends.

resource "google_compute_global_address" "lb" {
  name       = "${var.cluster_name}-lb-ip"
  ip_version = "IPV4"
}

resource "google_compute_health_check" "lb" {
  name = "${var.cluster_name}-lb-health-check"

  http_health_check {
    port         = 80
    request_path = "/"
  }
}

# GFE ranges that issue health checks and proxy requests directly to backend NEGs.
resource "google_compute_firewall" "lb_health_check" {
  name          = "${var.network_name}-allow-lb-health-check"
  network       = google_compute_network.main.id
  direction     = "INGRESS"
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

data "google_compute_network_endpoint_group" "primary" {
  for_each = var.enable_load_balancer_backends ? toset(var.primary_zones) : toset([])

  name    = var.neg_name
  zone    = each.value
  project = var.project_id
}

data "google_compute_network_endpoint_group" "secondary" {
  for_each = var.enable_load_balancer_backends ? toset(var.secondary_zones) : toset([])

  name    = var.neg_name
  zone    = each.value
  project = var.project_id
}

resource "google_compute_backend_service" "app" {
  name                  = "${var.cluster_name}-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks         = [google_compute_health_check.lb.id]

  dynamic "backend" {
    for_each = data.google_compute_network_endpoint_group.primary
    content {
      group                 = backend.value.id
      balancing_mode        = "RATE"
      max_rate_per_endpoint = 100
    }
  }

  dynamic "backend" {
    for_each = data.google_compute_network_endpoint_group.secondary
    content {
      group                 = backend.value.id
      balancing_mode        = "RATE"
      max_rate_per_endpoint = 100
    }
  }
}

resource "google_compute_url_map" "app" {
  name            = "${var.cluster_name}-url-map"
  default_service = google_compute_backend_service.app.id
}

resource "google_compute_target_http_proxy" "app" {
  name    = "${var.cluster_name}-http-proxy"
  url_map = google_compute_url_map.app.id
}

resource "google_compute_global_forwarding_rule" "app" {
  name                  = "${var.cluster_name}-forwarding-rule"
  ip_address            = google_compute_global_address.lb.address
  port_range            = "80"
  target                = google_compute_target_http_proxy.app.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
