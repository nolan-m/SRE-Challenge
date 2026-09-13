# Overview

Thank you for taking the extra time to complete this challenge.  The solution you provide will be used to help asses your ability to create a working solution based on a real-world use case.  We know your time is valuable, so please spend as much time as you think is appropriate (2-10 hours).

# Challenge

Welcome, you are the newest member of the DynamicEnablement team! You have been hand picked because of your ability to implement DevOps principles in a meaningful way and maximize value.

The DynamicEnablement team has created an app that will provide the answer to everything, but they are not sure how to deploy, scale, or even monitor.  As the SRE, they rely on you to guide them down this path and trust that you will make sure their product is "reliable".

The development team has provided their container for you, and now it is up to you to configure the rest.

As you design and deploy your solution, please make sure you keep these concepts in mind:
* Is everything automated? (IaC, CI/CD)
* Do I have security in place?
* How will this scale? (Cluster)
* How am I notified when a problem occurs?
* What is my reliability? (Monitoring and dashboard)
* How can I improve my reliability, or do I need to?

Ideally, the solution would be in GCP, however AWS would also be acceptable.

A complete solution should include:
* Infrastructure deployed using IaC
* Service deployed
* Automated deployment pipeline
* Monitoring
* SLI/SLO dashboard

# Solution

The solution uses Terraform to deploy secure GCP infrastructure and a regional Autopilot GKE cluster, deploys the application as a scalable Kubernetes service, and provides an automated GitHub Actions delivery pipeline. Cloud Monitoring provides alerting for traffic, errors, latency, and saturation, together with an SLI/SLO dashboard for measuring service reliability. The application is available at http://8.232.127.195/.


# Documentation

* [Deployment](docs/deployment.md): bootstrap, infrastructure deployment, verification, rollback, and teardown.
* [CI/CD](docs/ci-cd.md): validation, releases, image publishing, authentication, and workflow boundaries.
* [Architecture](docs/architecture.md): infrastructure, reliability, security, scaling, and monitoring.
* [Development](docs/development.md): Dev Container setup and local development commands.
