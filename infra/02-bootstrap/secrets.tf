resource "kubernetes_secret_v1" "arc_github_app" {
  metadata {
    name      = "dac-github-app"
    namespace = kubernetes_namespace_v1.arc_runners.metadata[0].name
  }
  data = {
    github_app_id              = var.github_app_id
    github_app_installation_id = var.github_app_installation_id
    github_app_private_key     = var.github_app_private_key
  }
}

resource "kubernetes_secret_v1" "alertmanager_slack" {
  metadata {
    name      = "alertmanager-slack"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = {
    # Placeholder keeps the Slack route valid when no webhook is configured;
    # Alertmanager then only logs failed deliveries.
    "webhook-url" = var.slack_webhook_url != "" ? var.slack_webhook_url : "https://hooks.slack.com/services/placeholder/not/configured"
  }
}

resource "kubernetes_secret_v1" "argocd_repo" {
  count = var.repo_private ? 1 : 0

  metadata {
    name      = "repo-talk"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }
  data = {
    type                    = "git"
    url                     = var.repo_url
    githubAppID             = var.github_app_id
    githubAppInstallationID = var.github_app_installation_id
    githubAppPrivateKey     = var.github_app_private_key
  }
}
