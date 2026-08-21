#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
AGENTS_DIR="${CHART_DIR}/agents"
# shellcheck source=../versions.env
source "${CHART_DIR}/versions.env"
# shellcheck source=hpa-common.sh
source "${SCRIPT_DIR}/hpa-common.sh"

[[ "${NEMOCLAW_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "${NEMOCLAW_COMMIT}" =~ ^[0-9a-f]{40}$ ]]
[[ "${OPENSHELL_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "${AGENT_SANDBOX_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]

INSTALL_SCRIPT="${SCRIPT_DIR}/install-openshell-k8s.sh"

grep -Fq -- '--set "server.auth.allowUnauthenticatedUsers=${UNAUTHENTICATED_VALUE}"' "${INSTALL_SCRIPT}"
if grep -Fq -- '--set-string "server.auth.allowUnauthenticatedUsers=' "${INSTALL_SCRIPT}"; then
  echo "FAIL: OpenShell unauthenticated-user policy must be a Helm boolean, not a truthy string" >&2
  exit 1
fi
grep -Fq 'service.type=ClusterIP' "${INSTALL_SCRIPT}"
grep -Fq 'kubectl get crd sandboxes.agents.x-k8s.io' "${INSTALL_SCRIPT}"
grep -Fq 'hpa_common_verify_target_node 1' "${INSTALL_SCRIPT}"
grep -Fq 'hpa_common_target_node_helm_value' "${INSTALL_SCRIPT}"
grep -Fq "'tolerations[0].key=nvidia.com/gpu'" "${INSTALL_SCRIPT}"
grep -Fq 'hpa_common_inference_secret_contract' "${SCRIPT_DIR}/hpa-load-test.sh"
grep -Fq 'ENABLE_ENVOY_LB' "${SCRIPT_DIR}/install-hpa.sh"
grep -Fq 'ingress.gateway.enabled' "${SCRIPT_DIR}/hpa-common.sh"

# --- Per-agent sandbox script contract ---------------------------------------
# Every agent folder under agents/<name>/ shares the same build/create/verify
# script shape; run-sandbox.sh (long-running gateway agents) or run-prompt.sh
# (Deep Agents Code's headless terminal harness) differs by agent shape.

check_common_agent_scripts() {
  local agent="${1:?agent}"
  local dir="${2:?dir}"
  local policy_file="${3:?policy_file}"

  local build_script="${dir}/build-sandbox-image.sh"
  local create_script="${dir}/create-sandbox.sh"
  local verify_script="${dir}/verify-sandbox.sh"

  [[ -x "${build_script}" ]] || { echo "FAIL: ${agent} build-sandbox-image.sh missing or not executable" >&2; exit 1; }
  [[ -x "${create_script}" ]] || { echo "FAIL: ${agent} create-sandbox.sh missing or not executable" >&2; exit 1; }
  [[ -x "${verify_script}" ]] || { echo "FAIL: ${agent} verify-sandbox.sh missing or not executable" >&2; exit 1; }

  grep -Fq 'NEMOCLAW_MANAGED_IMAGE_CAPABILITY_UNION=0' "${build_script}"
  grep -Fq 'ACTUAL_NEMOCLAW_COMMIT' "${build_script}"
  grep -Fq 'NEMOCLAW_INFERENCE_BASE_URL=https://inference.local/v1' "${build_script}"
  grep -Fq 'umask 022' "${build_script}"

  grep -Fq 'hpa_common_verify_target_node 1' "${create_script}"
  grep -Fq -- '--credential OPENAI_API_KEY' "${create_script}"
  grep -Fq 'hpa_common_inference_secret_contract' "${create_script}"
  grep -Fq 'ACTUAL_NEMOCLAW_COMMIT' "${create_script}"
  grep -Fq -- '--policy "${POLICY_FILE}"' "${create_script}"
  grep -Fq "${policy_file}" "${create_script}"
  grep -Fq 'effective sandbox policy still permits NVIDIA-hosted inference' "${create_script}"
  grep -Fq -- '-- /bin/true' "${create_script}"
  grep -Fq -- '--driver-config-json "${DRIVER_CONFIG_JSON}"' "${create_script}"
  grep -Fq '"node_selector": {"kubernetes.io/hostname": sys.argv[1]}' "${create_script}"
  grep -Fq '"key": "nvidia.com/gpu"' "${create_script}"
  grep -Fq 'hpa_common_openshell_inference_base_url' "${create_script}"
  grep -Fq 'OpenShell → Envoy Gateway (LeastRequest)' "${create_script}"
  grep -Fq 'Envoy LB disabled' "${create_script}"
  grep -Fq -- '--no-tty -- /bin/true' "${create_script}"
  grep -Fq 'curl -fsS https://inference.local/v1/models' "${create_script}"

  if grep -Eq 'NVIDIA_API_KEY' "${build_script}" "${create_script}"; then
    echo "FAIL: ${agent} native Kubernetes path contains a cloud inference API key" >&2
    exit 1
  fi
  if grep -Fq 'integrate.api.nvidia.com' "${build_script}"; then
    echo "FAIL: ${agent} native Kubernetes path configures a cloud inference endpoint" >&2
    exit 1
  fi
  if grep -Fq -- '--gpu' "${create_script}"; then
    echo "FAIL: ${agent} sandbox must not request a GPU" >&2
    exit 1
  fi
}

# OpenClaw and Hermes are long-running gateway agents that both install their
# agent-specific start.sh as /usr/local/bin/nemoclaw-start (verified against
# the NemoClaw Dockerfiles); run-sandbox.sh execs that entrypoint in the
# foreground and removes the upstream integrate.api.nvidia.com grant.
check_gateway_agent_scripts() {
  local agent="${1:?agent}"
  local dir="${2:?dir}"

  local create_script="${dir}/create-sandbox.sh"
  local run_script="${dir}/run-sandbox.sh"

  [[ -x "${run_script}" ]] || { echo "FAIL: ${agent} run-sandbox.sh missing or not executable" >&2; exit 1; }

  grep -Fq -- '--remove-endpoint integrate.api.nvidia.com:443' "${create_script}"
  grep -Fq 'curl -fsS https://inference.local/v1/chat/completions' "${create_script}"
  grep -Fq 'exec openshell sandbox exec' "${run_script}"
  grep -Fq '/usr/local/bin/nemoclaw-start' "${run_script}"

  if grep -Fq 'integrate.api.nvidia.com' "${run_script}"; then
    echo "FAIL: ${agent} native Kubernetes path configures a cloud inference endpoint" >&2
    exit 1
  fi
  if grep -Eq 'NVIDIA_API_KEY' "${run_script}"; then
    echo "FAIL: ${agent} native Kubernetes path contains a cloud inference API key" >&2
    exit 1
  fi
}

OPENCLAW_DIR="${AGENTS_DIR}/openclaw"
check_common_agent_scripts openclaw "${OPENCLAW_DIR}" 'nemoclaw-blueprint/policies/openclaw-sandbox.yaml'
check_gateway_agent_scripts openclaw "${OPENCLAW_DIR}"
grep -Fq 'openclaw plugins inspect nemoclaw --json' "${OPENCLAW_DIR}/create-sandbox.sh"
grep -Fq 'https://inference.local/v1/chat/completions' "${OPENCLAW_DIR}/verify-sandbox.sh"

HERMES_DIR="${AGENTS_DIR}/hermes"
check_common_agent_scripts hermes "${HERMES_DIR}" 'agents/hermes/policy-additions.yaml'
check_gateway_agent_scripts hermes "${HERMES_DIR}"
grep -Fq 'hermes --version' "${HERMES_DIR}/create-sandbox.sh"
grep -Fq 'http://localhost:8642/health' "${HERMES_DIR}/create-sandbox.sh"
grep -Fq 'hermes --version' "${HERMES_DIR}/verify-sandbox.sh"
grep -Fq 'http://localhost:8642/health' "${HERMES_DIR}/verify-sandbox.sh"
grep -Fq 'https://inference.local/v1/chat/completions' "${HERMES_DIR}/verify-sandbox.sh"

# Deep Agents Code (dcode) is a terminal harness with no gateway/dashboard:
# no run-sandbox.sh, no integrate.api.nvidia.com grant to remove (its upstream
# policy never grants it), and its smoke test is the real binary (`dcode -n`)
# rather than a curl-based chat/completions probe.
DEEPAGENTS_DIR="${AGENTS_DIR}/langchain-deepagents-code"
check_common_agent_scripts deepagents "${DEEPAGENTS_DIR}" 'agents/langchain-deepagents-code/policy-additions.yaml'
DEEPAGENTS_CREATE_SCRIPT="${DEEPAGENTS_DIR}/create-sandbox.sh"
DEEPAGENTS_VERIFY_SCRIPT="${DEEPAGENTS_DIR}/verify-sandbox.sh"
DEEPAGENTS_RUN_SCRIPT="${DEEPAGENTS_DIR}/run-prompt.sh"
[[ -x "${DEEPAGENTS_RUN_SCRIPT}" ]] || { echo "FAIL: deepagents run-prompt.sh missing or not executable" >&2; exit 1; }
if [[ -f "${DEEPAGENTS_DIR}/run-sandbox.sh" ]]; then
  echo "FAIL: deepagents must not ship run-sandbox.sh; dcode is a headless terminal harness (use run-prompt.sh)" >&2
  exit 1
fi
grep -Fq 'dcode --version' "${DEEPAGENTS_CREATE_SCRIPT}"
grep -Fq 'NEMOCLAW_DEEPAGENTS_CONFIG_OK' "${DEEPAGENTS_CREATE_SCRIPT}"
grep -Fq 'dcode -n' "${DEEPAGENTS_CREATE_SCRIPT}"
grep -Fq 'dcode --version' "${DEEPAGENTS_VERIFY_SCRIPT}"
grep -Fq 'NEMOCLAW_DEEPAGENTS_CONFIG_OK' "${DEEPAGENTS_VERIFY_SCRIPT}"
grep -Fq 'dcode -n' "${DEEPAGENTS_VERIFY_SCRIPT}"
grep -Fq 'dcode -n' "${DEEPAGENTS_RUN_SCRIPT}"
if grep -Fq -- '--remove-endpoint integrate.api.nvidia.com' "${DEEPAGENTS_CREATE_SCRIPT}"; then
  echo "FAIL: deepagents policy never grants integrate.api.nvidia.com; there is nothing to remove" >&2
  exit 1
fi
if grep -Fq 'integrate.api.nvidia.com' "${DEEPAGENTS_RUN_SCRIPT}"; then
  echo "FAIL: deepagents native Kubernetes path configures a cloud inference endpoint" >&2
  exit 1
fi

helm() {
  printf '%s\n' '{"inference":{"auth":{"existingSecret":"operator-inference-api.gpu-platform.production.cluster.example.internal","key":"true"}}}'
}
SECRET_CONTRACT="$(
  hpa_common_inference_secret_contract \
    test-namespace test-release test-release-metrics-proxy-inference-api
)"
if [[ "${SECRET_CONTRACT}" != $'operator-inference-api.gpu-platform.production.cluster.example.internal\ttrue' ]]; then
  echo "FAIL: scripts do not resolve the operator-managed inference Secret contract" >&2
  exit 1
fi

echo "OK: experimental NemoClaw Kubernetes path (OpenClaw, Hermes, Deep Agents Code) uses authenticated on-prem inference"
