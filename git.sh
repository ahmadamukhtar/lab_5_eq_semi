#!/usr/bin/env bash
# ==========================================
# GITHUB REPO INIT — paste-safe version
# ==========================================
set -euo pipefail

# ---- 1. Repo details ----
GITHUB_USER="ahmadamukhtar"
GITHUB_EMAIL="ahmadamukhtar860@gmail.com"
REPO_HOST="github.com"
REPO_PATH="ahmadamukhtar/lab_5_eq_semi.git"
REPO_URL="https://${REPO_HOST}/${REPO_PATH}"

# ---- 0. Ensure we're in a git repo (init if needed) ----
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ℹ not a git repo — running git init"
    git init -b main
fi

# ---- 2 & 3. identity + default branch ----
git config --local user.name        "$GITHUB_USER"
git config --local user.email       "$GITHUB_EMAIL"
git config --local init.defaultBranch main

# ---- 4. Credentials: reuse if valid, else prompt ----
CRED_FILE="$PWD/.git/credentials"

if [[ -s "$CRED_FILE" ]]; then
    echo "ℹ reusing existing $CRED_FILE"
else
    read -r -p "GitHub username [${GITHUB_USER}]: " _u
    GITHUB_USER="${_u:-$GITHUB_USER}"

    read -r -s -p "GitHub PAT for ${GITHUB_USER}: " _t < /dev/tty; echo

    # strip CR/LF
    _t="${_t//$'\r'/}"
    _t="${_t//$'\n'/}"

    # ---- PASTE-POLLUTION GUARD ----
    # A real GitHub PAT is: ghp_* / github_pat_* / gho_* / ghs_*
    # and contains only [A-Za-z0-9_]. Anything else = paste pollution.
    if [[ ! "$_t" =~ ^(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}$ && \
          ! "$_t" =~ ^github_pat_[A-Za-z0-9_]{20,}$ ]]; then
        echo >&2
        echo "ERROR: token does not look like a GitHub PAT." >&2
        echo "       (got ${#_t} chars; paste buffer may have polluted the prompt)" >&2
        echo "       Nothing was written. Re-run cleanly." >&2
        exit 1
    fi

    umask 077
    {
        printf 'https://%s:%s@%s\n'      "$GITHUB_USER" "$_t" "$REPO_HOST"
        printf 'https://%s:%s@%s/%s\n'   "$GITHUB_USER" "$_t" "$REPO_HOST" "$REPO_PATH"
    } > "$CRED_FILE"
    chmod 600 "$CRED_FILE"
    unset _t _u
    echo "✓ wrote $CRED_FILE"
fi

git config --local credential.helper "store --file=$CRED_FILE"
git config --local credential.useHttpPath true

# ---- 6. Remote (only touch if different) ----
CUR_URL="$(git remote get-url origin 2>/dev/null || true)"
if [[ "$CUR_URL" != "$REPO_URL" ]]; then
    git remote remove origin 2>/dev/null || true
    git remote add origin "$REPO_URL"
    echo "✓ origin → $REPO_URL"
fi

# ---- 7. Auth test (must NOT prompt) ----
if ! GIT_TERMINAL_PROMPT=0 \
      env -u GIT_ASKPASS -u SSH_ASKPASS \
          -u VSCODE_GIT_ASKPASS_NODE -u VSCODE_GIT_ASKPASS_MAIN \
          -u VSCODE_GIT_IPC_HANDLE \
      git ls-remote origin >/dev/null 2>&1; then
    echo "ERROR: auth to GitHub failed." >&2
    echo "       • Token scope must include 'repo'." >&2
    echo "       • Token may be expired/revoked." >&2
    rm -f "$CRED_FILE"
    exit 1
fi
echo "✓ auth OK"

# ---- 8. Fetch ----
git fetch origin --prune

# ---- 9. main branch tracking ----
if git show-ref --verify --quiet refs/heads/main; then
    git switch main
    git branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true
else
    git switch -c main --track origin/main
fi

echo
echo "=========================================="
echo " SETUP COMPLETE"
echo "   branch: $(git rev-parse --abbrev-ref HEAD)"
echo "   origin: $(git remote get-url origin)"
echo "=========================================="