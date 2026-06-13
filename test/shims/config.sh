#!/usr/bin/env bash
# Test shim for the runner's config.sh — records its invocation (so tests can
# assert what token/url/name registration was called with) and never touches
# GitHub. Handles both `config.sh --token …` (register) and `config.sh remove`.
echo "config.sh $*" >> "${SHIM_LOG:?SHIM_LOG unset}"
exit 0
