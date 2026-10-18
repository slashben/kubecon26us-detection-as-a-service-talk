variable "cluster_name" {
  description = "Name of the DOKS cluster created by 01-cluster."
  type        = string
  default     = "dac-demo"
}

variable "repo_url" {
  description = "HTTPS URL of this repository (your fork). Also used in gitops/root/*.yaml."
  type        = string
  default     = "https://github.com/slashben/kubecon26us-detection-as-a-service-talk.git"
}

variable "repo_revision" {
  description = "Branch the root Application tracks."
  type        = string
  default     = "main"
}

variable "repo_private" {
  description = "Create an Argo CD repository credential using the GitHub App. Set false once the repo is public."
  type        = bool
  default     = true
}

variable "argocd_chart_version" {
  type    = string
  default = "10.10.5"
}

variable "argocd_apps_chart_version" {
  type    = string
  default = "2.0.6"
}

variable "github_app_id" {
  description = "GitHub App ID (or client ID) used by ARC and, while private, by Argo CD."
  type        = string
  sensitive   = true
}

variable "github_app_installation_id" {
  description = "Installation ID of the GitHub App on the repository."
  type        = string
  sensitive   = true
}

variable "github_app_private_key" {
  description = "PEM private key of the GitHub App."
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook for Alertmanager. Empty keeps the route with a placeholder URL."
  type        = string
  sensitive   = true
  default     = ""
}
