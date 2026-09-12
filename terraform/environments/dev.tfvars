# Replace these environment-specific values before running terraform apply.
project_id = "nolan-sre-challenge"
region     = "us-central1"

cluster_name                 = "nolan-sre"
network_name                 = "nolan-sre-vpc"
subnetwork_name              = "nolan-sre-gke"
artifact_registry_repository = "nolan-sre"
github_repository            = "nolan-m/SRE-Challenge"

nodes_cidr    = "10.10.0.0/20"
pods_cidr     = "10.20.0.0/16"
services_cidr = "10.30.0.0/20"

pods_secondary_range_name     = "nolan-sre-pods"
services_secondary_range_name = "nolan-sre-services"
master_ipv4_cidr              = "172.16.0.0/28"

release_channel        = "REGULAR"
deletion_protection    = true
notification_emails    = []
maintenance_start_time = "2026-01-04T02:00:00Z"
maintenance_end_time   = "2026-01-04T06:00:00Z"
maintenance_recurrence = "FREQ=WEEKLY;BYDAY=SU"
