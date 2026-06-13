#!/usr/bin/env bats
# Black-box tests for entrypoint.sh. We run the real script with the runner's
# config.sh/run.sh (and curl) replaced by recording shims, a temp RUNNER_DIST
# and AGENTS_DIR, and assert on what got called. No network, no real runner.

setup() {
  ENTRY="$BATS_TEST_DIRNAME/../entrypoint.sh"
  SHIMS="$BATS_TEST_DIRNAME/shims"

  # entrypoint.sh uses `wait -n` (bash >= 4.3). CI's bash is 5.x; macOS ships
  # 3.2, so pick a capable bash for local runs.
  BASH_BIN="$(command -v bash)"
  if ! "$BASH_BIN" -c '((BASH_VERSINFO[0]>4 || (BASH_VERSINFO[0]==4 && BASH_VERSINFO[1]>=3)))' 2>/dev/null; then
    for c in /opt/homebrew/bin/bash /usr/local/bin/bash; do
      if [ -x "$c" ] && "$c" -c '((BASH_VERSINFO[0]>=5))' 2>/dev/null; then BASH_BIN="$c"; break; fi
    done
  fi

  export SHIM_LOG="$BATS_TEST_TMPDIR/shim.log"
  : > "$SHIM_LOG"

  # A fake runner "dist" the entrypoint copies into each agent dir.
  export RUNNER_DIST="$BATS_TEST_TMPDIR/dist"
  export AGENTS_DIR="$BATS_TEST_TMPDIR/agents"
  mkdir -p "$RUNNER_DIST"
  cp "$SHIMS/config.sh" "$SHIMS/run.sh" "$RUNNER_DIST/"
  chmod +x "$RUNNER_DIST/config.sh" "$RUNNER_DIST/run.sh"

  # curl shim on PATH (used only in PAT mode).
  chmod +x "$SHIMS/curl"
  export PATH="$SHIMS:$PATH"

  export ORG=TestOrg
  export RUNNER_NAME_PREFIX=testhost
  unset ACCESS_TOKEN
}

@test "token-only: registers each repo with its REG_TOKEN_<REPO>" {
  export REPOS="repo-alpha"
  export REG_TOKEN_REPO_ALPHA="REGTOK_ALPHA"

  run "$BASH_BIN" "$ENTRY"
  [ "$status" -eq 0 ]

  grep -q -- "--token REGTOK_ALPHA" "$SHIM_LOG"
  grep -q -- "--url https://github.com/TestOrg/repo-alpha" "$SHIM_LOG"
  grep -q -- "--name testhost-repo-alpha" "$SHIM_LOG"
  grep -q "^run.sh" "$SHIM_LOG"
  # token-only mode never hits the API
  ! grep -q "registration-token" "$SHIM_LOG"
}

@test "name sanitization: dots and hyphens map to REG_TOKEN_<UPPER_UNDERSCORE>" {
  export REPOS="weird.repo-name"
  export REG_TOKEN_WEIRD_REPO_NAME="REGTOK_WEIRD"

  run "$BASH_BIN" "$ENTRY"
  [ "$status" -eq 0 ]
  grep -q -- "--token REGTOK_WEIRD" "$SHIM_LOG"
}

@test "precedence: REG_TOKEN_<REPO> wins over ACCESS_TOKEN (no API mint)" {
  export REPOS="repo-beta"
  export REG_TOKEN_REPO_BETA="REGTOK_BETA"
  export ACCESS_TOKEN="PAT_SHOULD_BE_IGNORED"

  run "$BASH_BIN" "$ENTRY"
  [ "$status" -eq 0 ]
  grep -q -- "--token REGTOK_BETA" "$SHIM_LOG"
  # registration must not have minted a token from the PAT
  ! grep -q "registration-token" "$SHIM_LOG"
}

@test "PAT mode: mints a registration token via the API when no REG_TOKEN" {
  export REPOS="repo-gamma"
  export ACCESS_TOKEN="PATVALUE"

  run "$BASH_BIN" "$ENTRY"
  [ "$status" -eq 0 ]
  grep -q "registration-token" "$SHIM_LOG"
  grep -q -- "--token PAT_MINTED_TOKEN" "$SHIM_LOG"
}

@test "skip registration when credentials already persist" {
  export REPOS="repo-delta"
  export REG_TOKEN_REPO_DELTA="REGTOK_DELTA"

  # Simulate a persisted agent dir: full dist + credentials present.
  mkdir -p "$AGENTS_DIR/repo-delta"
  cp "$RUNNER_DIST/config.sh" "$RUNNER_DIST/run.sh" "$AGENTS_DIR/repo-delta/"
  chmod +x "$AGENTS_DIR/repo-delta/config.sh" "$AGENTS_DIR/repo-delta/run.sh"
  touch "$AGENTS_DIR/repo-delta/.runner" "$AGENTS_DIR/repo-delta/.credentials"

  run "$BASH_BIN" "$ENTRY"
  [ "$status" -eq 0 ]
  # no (re-)registration call…
  ! grep -q -- "--token" "$SHIM_LOG"
  # …but the agent is still launched from the persisted dir
  grep -q "^run.sh" "$SHIM_LOG"
}

@test "fatal when a repo has no token source" {
  export REPOS="repo-epsilon"
  # neither REG_TOKEN_REPO_EPSILON nor ACCESS_TOKEN

  run "$BASH_BIN" "$ENTRY"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no registration token"* ]]
}
