#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Deep Agents Code (dcode) is a terminal-oriented coding harness, not a long-running
# gateway agent (agents/langchain-deepagents-code/manifest.yaml: runtime.kind: terminal).
# There is no equivalent to ../openclaw/run-sandbox.sh or ../hermes/run-sandbox.sh here —
# instead, run one headless prompt at a time via `dcode -n` (manifest
# runtime.headless_command) and exit. For an interactive session use
# `openshell sandbox exec -n <name> -- dcode` from a terminal that supports a TTY.

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

SANDBOX_NAME="${DEEPAGENTS_SANDBOX_NAME:-deepagents-onprem}"
openshell sandbox get "${SANDBOX_NAME}" >/dev/null 2>&1 \
  || fail "sandbox ${SANDBOX_NAME} does not exist; run ./agents/langchain-deepagents-code/create-sandbox.sh first"

PROMPT="${1:-}"
[[ -n "${PROMPT}" ]] || fail "usage: $0 \"<prompt text>\""

exec openshell sandbox exec -n "${SANDBOX_NAME}" --no-tty -- \
  dcode -n "${PROMPT}"
