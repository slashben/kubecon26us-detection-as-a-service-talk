#!/usr/bin/env bash
# Validate every Rules object under gitops/rules/ against the Rules CRD schema.
#
#   ./hack/validate-rules.sh              # all of gitops/rules/*.yaml
#   ./hack/validate-rules.sh FILE...      # specific files
#
# Needs kubeconform (https://github.com/yannh/kubeconform). The schema in
# hack/schemas/ is the openAPIV3Schema of rules.kubescape.io/v1 from the
# kubescape-operator Helm chart, converted to JSON Schema. Regenerate it when the
# chart's CRD changes. The RuntimeRuleAlertBinding file is skipped (no schema here).
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v kubeconform >/dev/null; then
  echo "kubeconform not found: go install github.com/yannh/kubeconform/cmd/kubeconform@latest" >&2
  exit 1
fi

files=("$@")
if [ ${#files[@]} -eq 0 ]; then
  mapfile -t files < <(grep -l '^kind: Rules$' gitops/rules/*.yaml)
fi

# kubeconform resolves {{.ResourceKind}} etc. from each document; the single
# schema file below serves every Rules object.
kubeconform -strict -summary \
  -schema-location 'hack/schemas/rules-kubescape.io-v1.json' \
  "${files[@]}"
