#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME=${SERVICE_NAME:-"kubepanel"}
RELEASE_NAME=${RELEASE_NAME:-""}
RELEASE_NAMESPACE=${RELEASE_NAMESPACE:-""}
CHART_PATH=${CHART_PATH:-"./charts/kubepanel"}
HELM_OPTS=${HELM_OPTS:-""}
HELM_OPTIONS=${HELM_OPTIONS:-""}
AUTO_CONFIG_HELM_OPTS=""
USER_VALUES_PATH=${USER_VALUES_PATH:-"/root/.sealos/cloud/values/apps/${SERVICE_NAME}/kubepanel-values.yaml"}

get_cm_value() {
  local namespace="$1"
  local name="$2"
  local key="$3"
  kubectl get configmap "${name}" -n "${namespace}" -o "jsonpath={.data.${key}}" 2>/dev/null || true
}

add_set_string() {
  local key="$1"
  local value="$2"
  if [ -n "${value}" ]; then
    AUTO_CONFIG_HELM_OPTS="${AUTO_CONFIG_HELM_OPTS} --set-string ${key}=${value}"
  fi
}

detect_existing_helm_release() {
  local existing_release_name
  local existing_release_namespace
  local candidate

  existing_release_name="$(kubectl -n app-system get apps.app.sealos.io kubepanel -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null || true)"
  existing_release_namespace="$(kubectl -n app-system get apps.app.sealos.io kubepanel -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-namespace}' 2>/dev/null || true)"

  if [ -n "${existing_release_name}" ] && [ -n "${existing_release_namespace}" ]; then
    RELEASE_NAME=${RELEASE_NAME:-"${existing_release_name}"}
    RELEASE_NAMESPACE=${RELEASE_NAMESPACE:-"${existing_release_namespace}"}
    return
  fi

  if ! command -v helm >/dev/null 2>&1; then
    return
  fi

  for candidate in kubepanel/kubepanel kubepanel-frontend/kubepanel-frontend; do
    existing_release_namespace="${candidate%/*}"
    existing_release_name="${candidate#*/}"
    if helm -n "${existing_release_namespace}" status "${existing_release_name}" >/dev/null 2>&1; then
      RELEASE_NAME=${RELEASE_NAME:-"${existing_release_name}"}
      RELEASE_NAMESPACE=${RELEASE_NAMESPACE:-"${existing_release_namespace}"}
      return
    fi
  done
}

assert_app_ownership_compatible() {
  local existing_release_name
  local existing_release_namespace

  existing_release_name="$(kubectl -n app-system get apps.app.sealos.io kubepanel -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null || true)"
  existing_release_namespace="$(kubectl -n app-system get apps.app.sealos.io kubepanel -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-namespace}' 2>/dev/null || true)"

  if [ -z "${existing_release_name}" ] && [ -z "${existing_release_namespace}" ]; then
    return
  fi

  if [ "${existing_release_name}" = "${RELEASE_NAME}" ] && [ "${existing_release_namespace}" = "${RELEASE_NAMESPACE}" ]; then
    return
  fi

  echo "Existing Helm-managed App app-system/kubepanel belongs to release ${existing_release_namespace}/${existing_release_name}." >&2
  echo "Set RELEASE_NAME=${existing_release_name} and RELEASE_NAMESPACE=${existing_release_namespace}, or upgrade that release directly." >&2
  exit 1
}

is_helm_owned_namespaced() {
  local namespace="$1"
  local kind="$2"
  local name="$3"
  local release_name
  local release_namespace

  release_name="$(kubectl -n "${namespace}" get "${kind}" "${name}" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null || true)"
  release_namespace="$(kubectl -n "${namespace}" get "${kind}" "${name}" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-namespace}' 2>/dev/null || true)"
  [ -n "${release_name}" ] || [ -n "${release_namespace}" ]
}

delete_manual_namespaced_resource() {
  local namespace="$1"
  local kind="$2"
  local name="$3"

  if ! kubectl -n "${namespace}" get "${kind}" "${name}" >/dev/null 2>&1; then
    return
  fi

  if is_helm_owned_namespaced "${namespace}" "${kind}" "${name}"; then
    echo "Keep Helm-managed ${kind} ${namespace}/${name}."
    return
  fi

  echo "Delete previous manual ${kind} ${namespace}/${name}."
  kubectl -n "${namespace}" delete "${kind}" "${name}" --ignore-not-found
}

cleanup_previous_manual_deployment() {
  delete_manual_namespaced_resource kubepanel deployment kubepanel
  delete_manual_namespaced_resource kubepanel service kubepanel
  delete_manual_namespaced_resource kubepanel ingress kubepanel
  delete_manual_namespaced_resource kubepanel configmap kubepanel
  delete_manual_namespaced_resource kubepanel configmap kubepanel-config

  delete_manual_namespaced_resource kubepanel-frontend deployment kubepanel-frontend
  delete_manual_namespaced_resource kubepanel-frontend service kubepanel-frontend
  delete_manual_namespaced_resource kubepanel-frontend ingress kubepanel-frontend
  delete_manual_namespaced_resource kubepanel-frontend configmap kubepanel-frontend
  delete_manual_namespaced_resource kubepanel-frontend configmap kubepanel-frontend-config

  delete_manual_namespaced_resource app-system apps.app.sealos.io kubepanel
}

detect_existing_helm_release
RELEASE_NAME=${RELEASE_NAME:-"${SERVICE_NAME}"}
RELEASE_NAMESPACE=${RELEASE_NAMESPACE:-"${SERVICE_NAME}"}
assert_app_ownership_compatible

SEALOS_CLOUD_DOMAIN=${SEALOS_CLOUD_DOMAIN:-"${cloudDomain:-$(get_cm_value sealos-system sealos-config cloudDomain)}"}
add_set_string kubepanelConfig.cloudDomain "${SEALOS_CLOUD_DOMAIN}"
SEALOS_CLOUD_PORT=${SEALOS_CLOUD_PORT:-"${cloudPort:-$(get_cm_value sealos-system sealos-config cloudPort)}"}
add_set_string kubepanelConfig.cloudPort "${SEALOS_CLOUD_PORT}"
SEALOS_HTTP_PORT=${SEALOS_HTTP_PORT:-"${httpPort:-$(get_cm_value sealos-system sealos-config httpPort)}"}
add_set_string kubepanelConfig.httpPort "${SEALOS_HTTP_PORT}"
SEALOS_DISABLE_HTTPS=${SEALOS_DISABLE_HTTPS:-"${disableHttps:-$(get_cm_value sealos-system sealos-config disableHttps)}"}
add_set_string kubepanelConfig.disableHttps "${SEALOS_DISABLE_HTTPS}"
SEALOS_CERT_SECRET_NAME=${SEALOS_CERT_SECRET_NAME:-"${certSecretName:-$(get_cm_value sealos-system sealos-config certSecretName)}"}
add_set_string kubepanelConfig.certSecretName "${SEALOS_CERT_SECRET_NAME}"

cleanup_previous_manual_deployment

if [ ! -f "${USER_VALUES_PATH}" ]; then
  mkdir -p "$(dirname "${USER_VALUES_PATH}")"
  cp "./charts/kubepanel/kubepanel-values.yaml" "${USER_VALUES_PATH}"
fi

HELM_ARGS="${AUTO_CONFIG_HELM_OPTS} ${HELM_OPTIONS} ${HELM_OPTS}"

echo "Deploying Helm chart..."
helm upgrade -i "${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" --create-namespace "${CHART_PATH}" \
  -f "./charts/kubepanel/values.yaml" \
  -f "${USER_VALUES_PATH}" \
  ${HELM_ARGS}
