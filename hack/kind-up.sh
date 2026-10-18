#!/usr/bin/env bash
# Bring up a local kind cluster that mirrors infra/02-bootstrap: Argo CD, the three
# secrets, the root Application. Used to validate the gitops/ tree before any cloud spend.
#
# Env (all optional):
#   KIND_CLUSTER_NAME            default: dac-kind
#   REPO_URL                     default: this repo's origin URL (https form)
#   REPO_REVISION                default: current branch
#   REPO_PRIVATE                 default: true; "false" skips the Argo CD repo credential
#   ARGOCD_REPO_TOKEN            optional: a GitHub token for the Argo CD repo credential
#                                instead of the GitHub App (local validation shortcut)
#   GITHUB_APP_ID, GITHUB_APP_INSTALLATION_ID, GITHUB_APP_PRIVATE_KEY_FILE
#                                default: placeholders; arc-runners stays degraded without real ones
#   SLACK_WEBHOOK_URL            default: placeholder
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/.." && pwd)"
cluster="${KIND_CLUSTER_NAME:-dac-kind}"
argocd_chart_version="${ARGOCD_CHART_VERSION:-10.10.5}"
argocd_apps_chart_version="${ARGOCD_APPS_CHART_VERSION:-2.0.6}"

origin="$(git -C "$repo_root" remote get-url origin)"
origin_https="$(sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##' <<<"$origin").git"
REPO_URL="${REPO_URL:-$origin_https}"
REPO_REVISION="${REPO_REVISION:-$(git -C "$repo_root" rev-parse --abbrev-ref HEAD)}"
REPO_PRIVATE="${REPO_PRIVATE:-true}"
GITHUB_APP_ID="${GITHUB_APP_ID:-0}"
GITHUB_APP_INSTALLATION_ID="${GITHUB_APP_INSTALLATION_ID:-0}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-https://hooks.slack.com/services/placeholder/not/configured}"

if [[ -n "${GITHUB_APP_PRIVATE_KEY_FILE:-}" ]]; then
  key_file="$GITHUB_APP_PRIVATE_KEY_FILE"
else
  key_file="$(mktemp)"
  echo "placeholder" >"$key_file"
fi

if ! kind get clusters 2>/dev/null | grep -qx "$cluster"; then
  kind create cluster --name "$cluster" --wait 120s
fi
kubectl config use-context "kind-$cluster" >/dev/null

for ns in argocd arc-runners monitoring; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl -n arc-runners create secret generic dac-github-app \
  --from-literal=github_app_id="$GITHUB_APP_ID" \
  --from-literal=github_app_installation_id="$GITHUB_APP_INSTALLATION_ID" \
  --from-file=github_app_private_key="$key_file" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n monitoring create secret generic alertmanager-slack \
  --from-literal=webhook-url="$SLACK_WEBHOOK_URL" \
  --dry-run=client -o yaml | kubectl apply -f -

if [[ "$REPO_PRIVATE" == "true" && -n "${ARGOCD_REPO_TOKEN:-}" ]]; then
  # Local shortcut: a personal access token instead of the GitHub App.
  kubectl -n argocd create secret generic repo-talk \
    --from-literal=type=git \
    --from-literal=url="$REPO_URL" \
    --from-literal=username=x-access-token \
    --from-literal=password="$ARGOCD_REPO_TOKEN" \
    --dry-run=client -o yaml \
    | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
    | kubectl apply -f -
elif [[ "$REPO_PRIVATE" == "true" ]]; then
  kubectl -n argocd create secret generic repo-talk \
    --from-literal=type=git \
    --from-literal=url="$REPO_URL" \
    --from-literal=githubAppID="$GITHUB_APP_ID" \
    --from-literal=githubAppInstallationID="$GITHUB_APP_INSTALLATION_ID" \
    --from-file=githubAppPrivateKey="$key_file" \
    --dry-run=client -o yaml \
    | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
    | kubectl apply -f -
fi

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null

helm upgrade --install argocd argo/argo-cd \
  --version "$argocd_chart_version" -n argocd \
  -f "$repo_root/infra/02-bootstrap/argocd-values.yaml" \
  --wait --timeout 10m

helm upgrade --install root argo/argocd-apps \
  --version "$argocd_apps_chart_version" -n argocd \
  --set-json "applications={\"root\":{\"namespace\":\"argocd\",\"project\":\"default\",\"source\":{\"repoURL\":\"$REPO_URL\",\"targetRevision\":\"$REPO_REVISION\",\"path\":\"gitops/root\"},\"destination\":{\"server\":\"https://kubernetes.default.svc\",\"namespace\":\"argocd\"},\"syncPolicy\":{\"automated\":{\"prune\":true,\"selfHeal\":true},\"syncOptions\":[\"CreateNamespace=true\"]}}}"

echo
echo "Argo CD is up. Watch the apps with:"
echo "  kubectl -n argocd get applications -w"
echo "UI: kubectl -n argocd port-forward svc/argocd-server 8080:80"
echo "    password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
