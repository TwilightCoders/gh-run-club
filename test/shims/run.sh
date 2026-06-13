#!/usr/bin/env bash
# Test shim for the runner's run.sh — records that the agent "started" then
# exits 0 so the entrypoint's `wait -n` returns and the script completes,
# instead of blocking the test on a real long-lived runner process.
echo "run.sh $*" >> "${SHIM_LOG:?SHIM_LOG unset}"
exit 0
