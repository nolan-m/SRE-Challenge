resource "google_monitoring_notification_channel" "email" {
  for_each     = var.notification_emails
  project      = var.project_id
  display_name = "${var.cluster_name} alerts - ${each.value}"
  type         = "email"

  labels = {
    email_address = each.value
  }
}

locals {
  notification_channel_ids = [for channel in google_monitoring_notification_channel.email : channel.id]
}

resource "google_monitoring_service" "nolan_sre" {
  service_id   = var.cluster_name
  display_name = "${var.cluster_name} HTTP service"
  project      = var.project_id

  basic_service {
    service_type = "GKE_SERVICE"
    service_labels = {
      project_id     = var.project_id
      location       = var.region
      cluster_name   = var.cluster_name
      namespace_name = var.cluster_name
      service_name   = var.cluster_name
    }
  }
}

resource "google_monitoring_slo" "availability" {
  service             = google_monitoring_service.nolan_sre.service_id
  display_name        = "${var.cluster_name} HTTP availability"
  project             = var.project_id
  goal                = 0.999
  rolling_period_days = 30

  lifecycle {
    ignore_changes = [service]
  }

  request_based_sli {
    good_total_ratio {
      total_service_filter = join(" AND ", [
        "metric.type=\"loadbalancing.googleapis.com/https/request_count\"",
        "resource.type=\"https_lb_rule\"",
        "resource.labels.backend_target_name=starts_with(\"k8s1-\")",
      ])
      good_service_filter = join(" AND ", [
        "metric.type=\"loadbalancing.googleapis.com/https/request_count\"",
        "resource.type=\"https_lb_rule\"",
        "resource.labels.backend_target_name=starts_with(\"k8s1-\")",
        "metric.labels.response_code_class=200",
      ])
    }
  }
}

resource "google_monitoring_dashboard" "nolan_sre" {
  project = var.project_id
  dashboard_json = jsonencode({
    displayName = "${var.cluster_name} SRE dashboard"
    gridLayout = {
      columns = "2"
      widgets = [
        {
          title = "HTTP request rate"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" resource.type=\"https_lb_rule\""
                  aggregation = {
                    perSeriesAligner   = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_SUM"
                    groupByFields      = ["resource.label.backend_target_name"]
                  }
                }
              }
              plotType = "LINE"
            }]
            yAxis = {
              label = "requests/second"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "HTTP error rate"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" resource.type=\"https_lb_rule\" metric.labels.response_code_class=500"
                  aggregation = {
                    perSeriesAligner   = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_SUM"
                  }
                }
              }
              plotType = "STACKED_AREA"
            }]
            yAxis = {
              label = "5xx requests/second"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "HTTP request latency"
          xyChart = {
            dataSets = [
              {
                legendTemplate = "p95"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"loadbalancing.googleapis.com/https/total_latencies\" resource.type=\"https_lb_rule\""
                    aggregation = {
                      perSeriesAligner   = "ALIGN_PERCENTILE_95"
                      crossSeriesReducer = "REDUCE_MAX"
                    }
                  }
                }
                plotType = "LINE"
              },
              {
                legendTemplate = "p99"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"loadbalancing.googleapis.com/https/total_latencies\" resource.type=\"https_lb_rule\""
                    aggregation = {
                      perSeriesAligner   = "ALIGN_PERCENTILE_99"
                      crossSeriesReducer = "REDUCE_MAX"
                    }
                  }
                }
                plotType = "LINE"
              },
            ]
            yAxis = {
              label = "milliseconds"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "Container CPU request utilization"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = join(" AND ", [
                    "metric.type=\"kubernetes.io/container/cpu/request_utilization\"",
                    "resource.type=\"k8s_container\"",
                    "resource.labels.namespace_name=\"${var.cluster_name}\"",
                    "resource.labels.container_name=\"nginx\"",
                  ])
                  aggregation = {
                    perSeriesAligner   = "ALIGN_MEAN"
                    crossSeriesReducer = "REDUCE_MEAN"
                    groupByFields      = ["resource.label.location"]
                  }
                }
              }
              plotType = "LINE"
            }]
            yAxis = {
              label = "utilization"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "Container restart count"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = join(" AND ", [
                    "metric.type=\"kubernetes.io/container/restart_count\"",
                    "resource.type=\"k8s_container\"",
                    "resource.labels.namespace_name=\"${var.cluster_name}\"",
                  ])
                  aggregation = {
                    perSeriesAligner   = "ALIGN_DELTA"
                    crossSeriesReducer = "REDUCE_SUM"
                  }
                }
              }
              plotType = "STACKED_AREA"
            }]
          }
        },
      ]
    }
  })
}

resource "google_monitoring_alert_policy" "availability" {
  project               = var.project_id
  display_name          = "${var.cluster_name} availability below SLO"
  combiner              = "OR"
  enabled               = true
  notification_channels = local.notification_channel_ids

  conditions {
    display_name = "HTTP 5xx error rate above 1%"
    condition_threshold {
      filter          = "metric.type=\"loadbalancing.googleapis.com/https/request_count\" resource.type=\"https_lb_rule\" metric.labels.response_code_class=500"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.01
      duration        = "300s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  documentation {
    content   = "HTTP 5xx traffic has exceeded 1% for five minutes. Check the GKE Ingress, Service endpoints, Pod readiness, and recent rollout."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "cpu" {
  project               = var.project_id
  display_name          = "${var.cluster_name} container CPU saturation"
  combiner              = "OR"
  enabled               = true
  notification_channels = local.notification_channel_ids

  conditions {
    display_name = "NGINX CPU request utilization above 80%"
    condition_threshold {
      filter          = "metric.type=\"kubernetes.io/container/cpu/request_utilization\" resource.type=\"k8s_container\" resource.labels.namespace_name=\"${var.cluster_name}\" resource.labels.container_name=\"nginx\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "600s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MEAN"
      }
    }
  }

  documentation {
    content   = "NGINX CPU request utilization has exceeded 80% for ten minutes. Review HPA behavior and Pod resource requests."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "latency" {
  project               = var.project_id
  display_name          = "${var.cluster_name} HTTP p95 latency"
  combiner              = "OR"
  enabled               = true
  notification_channels = local.notification_channel_ids

  conditions {
    display_name = "HTTP p95 latency above 500 ms"
    condition_threshold {
      filter          = "metric.type=\"loadbalancing.googleapis.com/https/total_latencies\" resource.type=\"https_lb_rule\""
      comparison      = "COMPARISON_GT"
      threshold_value = 500
      duration        = "300s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_PERCENTILE_95"
        cross_series_reducer = "REDUCE_MAX"
      }
    }
  }

  documentation {
    content   = "HTTP p95 latency has exceeded 500 ms for five minutes. Check the GKE Ingress, Service endpoints, Pod readiness, resource saturation, and recent rollout."
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "restarts" {
  project               = var.project_id
  display_name          = "${var.cluster_name} container restarts"
  combiner              = "OR"
  enabled               = true
  notification_channels = local.notification_channel_ids

  conditions {
    display_name = "NGINX container restarted"
    condition_threshold {
      filter          = "metric.type=\"kubernetes.io/container/restart_count\" resource.type=\"k8s_container\" resource.labels.namespace_name=\"${var.cluster_name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "300s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  documentation {
    content   = "One or more NGINX containers restarted during the last five minutes. Check Pod events, memory pressure, and rollout history."
    mime_type = "text/markdown"
  }
}
