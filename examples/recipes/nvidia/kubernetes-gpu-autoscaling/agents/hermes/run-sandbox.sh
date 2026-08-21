#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# OpenShell v0.0.85 Kubernetes sandboxes intentionally boot with an idle supervisor
# command. Start the NemoClaw/Hermes image entrypoint as the sandbox identity and keep
# this foreground exec session alive for the duration of the experimental runtime.
# The Hermes image installs agents/hermes/start.sh as /usr/local/bin/nemoclaw-start,
# the same entrypoint path every NemoClaw agent image uses (mirrors ../openclaw/run-sandbox.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../../versions.env
source "${CHART_DIR}/versions.env"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

command -v openshell >/dev/null 2>&1 || fail "missing command: openshell"
ACTUAL_OPENSHELL_VERSION="$(openshell --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
[[ "${ACTUAL_OPENSHELL_VERSION}" == "${OPENSHELL_VERSION}" ]] \
  || fail "OpenShell CLI ${OPENSHELL_VERSION} is required; found ${ACTUAL_OPENSHELL_VERSION:-unknown}"

SANDBOX_NAME="${HERMES_SANDBOX_NAME:-hermes-onprem}"
openshell sandbox get "${SANDBOX_NAME}" >/dev/null 2>&1 \
  || fail "sandbox ${SANDBOX_NAME} does not exist; run ./agents/hermes/create-sandbox.sh first"

echo "Starting NemoClaw/Hermes in ${SANDBOX_NAME}. Keep this terminal open."
echo "OpenShell owns the pod sandbox; the Hermes entrypoint runs as the sandbox identity."
echo "The dashboard (18789) and OpenAI-compatible API (8642) are inside the sandbox only; port-forward via openshell sandbox exec if you need to reach them."
exec openshell sandbox exec -n "${SANDBOX_NAME}" --no-tty -- \
  /usr/local/bin/nemoclaw-start
