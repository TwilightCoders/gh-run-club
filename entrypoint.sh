#!/usr/bin/env bash
# gh-run-club: run N repo-scoped GitHub Actions runner agents in ONE container.
# Each repo in $REPOS gets its own agent (own dir + _work), registered from a
# single PAT. Deregisters all on SIGTERM.
set -uo pipefail

: "${ORG:?set ORG (e.g. TwilightCoders)}"
: "${REPOS:?set REPOS (space-separated repo names under ORG)}"
: "${ACCESS_TOKEN:?set ACCESS_TOKEN (PAT with repo Administration: read+write)}"
LABELS="${LABELS:-self-hosted,linux,x64}"
NAME_PREFIX="${RUNNER_NAME_PREFIX:-$(hostname)}"
RUNNER_DIST="${RUNNER_DIST:-/opt/actions-runner}"
AGENTS_DIR="${AGENTS_DIR:-$HOME/agents}"
API="${GITHUB_API_URL:-https://api.github.com}"

api_token() { # $1=repo  $2=registration|remove  -> prints token
  curl -fsSL -X POST \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${API}/repos/${ORG}/$1/actions/runners/$2-token" | jq -r .token
}

declare -a STARTED=()
shutdown() {
  echo "[gh-run-club] deregistering agents…"
  for repo in "${STARTED[@]:-}"; do
    [ -n "${repo:-}" ] || continue
    tok="$(api_token "$repo" remove 2>/dev/null || true)"
    [ -n "$tok" ] && ( cd "${AGENTS_DIR}/${repo}" && ./config.sh remove --token "$tok" >/dev/null 2>&1 || true )
  done
  exit 0
}
trap shutdown SIGTERM SIGINT

for repo in $REPOS; do
  dir="${AGENTS_DIR}/${repo}"
  echo "[gh-run-club] configuring agent for ${ORG}/${repo}"
  mkdir -p "$dir"; cp -RT "$RUNNER_DIST" "$dir"
  tok="$(api_token "$repo" registration)"
  if [ -z "$tok" ] || [ "$tok" = "null" ]; then
    echo "[gh-run-club] FATAL: could not mint a registration token for ${ORG}/${repo} (PAT lacks Administration:RW on it?)" >&2
    exit 1
  fi
  ( cd "$dir" && ./config.sh --unattended --replace \
      --url "https://github.com/${ORG}/${repo}" --token "$tok" \
      --name "${NAME_PREFIX}-${repo}" --labels "$LABELS" --work "_work" )
  ( cd "$dir" && exec ./run.sh ) &
  STARTED+=("$repo")
  echo "[gh-run-club] agent up for ${ORG}/${repo} (pid $!)"
done

echo "[gh-run-club] ${#STARTED[@]} agent(s) listening: ${STARTED[*]}"
wait -n
echo "[gh-run-club] an agent exited — tearing down so the orchestrator restarts us"
shutdown
