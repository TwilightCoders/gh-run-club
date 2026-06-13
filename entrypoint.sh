#!/usr/bin/env bash
# gh-run-club: run N repo-scoped GitHub Actions runner agents in ONE container.
# Each repo in $REPOS gets its own agent (own dir + _work).
#
# Two auth modes, pick whichever fits:
#   • Token-only (lowest standing privilege): set REG_TOKEN_<REPO> per repo to a
#     short-lived registration token. Agents register ONCE; credentials persist
#     in $AGENTS_DIR (mount it as a volume) and are reused on every restart —
#     no token needed again unless you wipe the volume.
#   • PAT (recreate-resilient): set ACCESS_TOKEN to a fine-grained PAT with
#     repo Administration:read+write. The container mints a registration token
#     per repo on every boot and deregisters on shutdown.
# REG_TOKEN_<REPO> wins when both are present. <REPO> is the repo name uppercased
# with every non-alphanumeric char turned into '_' (vscode-alterminal ->
# REG_TOKEN_VSCODE_ALTERMINAL).
set -uo pipefail

: "${ORG:?set ORG (e.g. TwilightCoders)}"
: "${REPOS:?set REPOS (space-separated repo names under ORG)}"
LABELS="${LABELS:-self-hosted,linux,x64}"
NAME_PREFIX="${RUNNER_NAME_PREFIX:-$(hostname)}"
RUNNER_DIST="${RUNNER_DIST:-/opt/actions-runner}"
AGENTS_DIR="${AGENTS_DIR:-$HOME/agents}"
API="${GITHUB_API_URL:-https://api.github.com}"

api_token() { # $1=repo  $2=registration|remove  -> prints token (PAT mode only)
  curl -fsSL -X POST \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${API}/repos/${ORG}/$1/actions/runners/$2-token" | jq -r .token
}

reg_token_for() { # $1=repo -> prints a registration token, or nothing
  local key="REG_TOKEN_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -c '[:alnum:]' '_')"
  local val="${!key:-}"
  if [ -n "$val" ]; then printf '%s' "$val"; return 0; fi
  if [ -n "${ACCESS_TOKEN:-}" ]; then api_token "$1" registration; return 0; fi
  return 1
}

declare -a STARTED=()
shutdown() {
  if [ -n "${ACCESS_TOKEN:-}" ]; then
    echo "[gh-run-club] deregistering agents (PAT mode)…"
    for repo in "${STARTED[@]:-}"; do
      [ -n "${repo:-}" ] || continue
      tok="$(api_token "$repo" remove 2>/dev/null || true)"
      [ -n "$tok" ] && [ "$tok" != null ] && \
        ( cd "${AGENTS_DIR}/${repo}" && ./config.sh remove --token "$tok" >/dev/null 2>&1 || true )
    done
  else
    echo "[gh-run-club] token-only mode — leaving runners registered (credentials persist for next start)"
  fi
  exit 0
}
trap shutdown SIGTERM SIGINT

for repo in $REPOS; do
  dir="${AGENTS_DIR}/${repo}"
  if [ -f "$dir/.runner" ] && [ -f "$dir/.credentials" ]; then
    echo "[gh-run-club] ${ORG}/${repo}: reusing persisted registration"
  else
    echo "[gh-run-club] ${ORG}/${repo}: registering"
    mkdir -p "$dir"; cp -RT "$RUNNER_DIST" "$dir"
    tok="$(reg_token_for "$repo" || true)"
    if [ -z "$tok" ] || [ "$tok" = "null" ]; then
      echo "[gh-run-club] FATAL: no registration token for ${ORG}/${repo} — set REG_TOKEN_<REPO> or ACCESS_TOKEN" >&2
      exit 1
    fi
    ( cd "$dir" && ./config.sh --unattended --replace \
        --url "https://github.com/${ORG}/${repo}" --token "$tok" \
        --name "${NAME_PREFIX}-${repo}" --labels "$LABELS" --work "_work" )
  fi
  ( cd "$dir" && exec ./run.sh ) &
  STARTED+=("$repo")
  echo "[gh-run-club] agent up for ${ORG}/${repo} (pid $!)"
done

echo "[gh-run-club] ${#STARTED[@]} agent(s) listening: ${STARTED[*]}"
wait -n
echo "[gh-run-club] an agent exited — tearing down so the orchestrator restarts us"
shutdown
