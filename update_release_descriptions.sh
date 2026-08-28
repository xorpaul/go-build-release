#!/usr/bin/env bash
# update_release_descriptions.sh — backfill Gitea release bodies from CHANGELOG.md
#
# Finds every Gitea release whose body is the one-line placeholder
# "Release vX.Y.Z" (written by build_release.sh when no CHANGELOG section
# existed yet) and replaces it with the matching section from CHANGELOG.md.
#
# Credentials come from ~/.gitea_env (same as build_release.sh):
#   GIT_TOKEN   — personal access token with repo write scope
#   GIT_URL     — base URL, e.g. https://git.ionos.org  (optional; auto-detected)
#
# Usage:
#   cd <repo-root>
#   ./go-build-release/update_release_descriptions.sh [--dry-run]

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
	DRY_RUN=true
	echo "[dry-run] No changes will be written to Gitea."
fi

if [ ! -f ~/.gitea_env ]; then
	echo "Error: ~/.gitea_env not found. Export GIT_TOKEN and optionally GIT_URL there." >&2
	exit 1
fi
source ~/.gitea_env

if [ ! -f CHANGELOG.md ]; then
	echo "Error: CHANGELOG.md not found in repo root." >&2
	exit 1
fi

# Auto-detect repo owner/name/URL from git remote (same logic as build_release.sh)
REMOTE_URL=$(git remote get-url origin)
if [[ "$REMOTE_URL" =~ (.*)@([^:]+):(.+)\.git$ ]]; then
	GIT_HOST="${BASH_REMATCH[2]}"
	REPO_PATH="${BASH_REMATCH[3]}"
	GIT_URL="${GIT_URL:-https://${GIT_HOST}}"
elif [[ "$REMOTE_URL" =~ (https?://[^/]+)/(.+)\.git$ ]]; then
	GIT_URL="${GIT_URL:-${BASH_REMATCH[1]}}"
	REPO_PATH="${BASH_REMATCH[2]}"
else
	echo "Error: Could not parse git remote URL: ${REMOTE_URL}" >&2
	exit 1
fi
GIT_REPO_OWNER=$(dirname "$REPO_PATH")
GIT_REPO_NAME=$(basename "$REPO_PATH")

API="${GIT_URL}/api/v1/repos/${GIT_REPO_OWNER}/${GIT_REPO_NAME}"
AUTH="Authorization: token ${GIT_TOKEN}"

echo "Repo : ${GIT_REPO_OWNER}/${GIT_REPO_NAME} @ ${GIT_URL}"
echo ""

# Fetch all releases (up to 50; enough for this project)
RELEASES=$(curl -sf -H "$AUTH" "${API}/releases?limit=50&page=1")

UPDATED=0
SKIPPED=0
MISSING=0

while IFS= read -r release; do
	ID=$(echo "$release"    | jq -r '.id')
	TAG=$(echo "$release"   | jq -r '.tag_name')
	BODY=$(echo "$release"  | jq -r '.body')

	# Only touch releases whose body is exactly the one-line placeholder
	PLACEHOLDER="Release ${TAG}"
	if [ "$BODY" != "$PLACEHOLDER" ]; then
		echo "  skip ${TAG}  (body is not a placeholder)"
		SKIPPED=$((SKIPPED + 1))
		continue
	fi

	# Extract the matching section from CHANGELOG.md
	# Matches headings like:  ## v1.1.0 (2026-08-26)
	VERSION_NO_V="${TAG#v}"
	CHANGELOG_SECTION=$(awk -v tag="${TAG}" -v ver="${VERSION_NO_V}" '
		$0 ~ "^## (\\[" tag "\\]|" tag "[[:space:](])" \
		|| $0 ~ "^## (\\[" ver  "\\]|" ver  "[[:space:](])" { found=1; next }
		found && /^## / { exit }
		found { print }
	' CHANGELOG.md | sed '/^[[:space:]]*$/{ N; /^\n[[:space:]]*$/d }')

	if [ -z "$CHANGELOG_SECTION" ]; then
		echo "  MISSING ${TAG}  (no section in CHANGELOG.md)"
		MISSING=$((MISSING + 1))
		continue
	fi

	echo "  update ${TAG}  (release id ${ID})"
	if [ "$DRY_RUN" = true ]; then
		echo "    [dry-run] would PATCH body:"
		echo "$CHANGELOG_SECTION" | head -5 | sed 's/^/      /'
		echo "    ..."
		UPDATED=$((UPDATED + 1))
		continue
	fi

	PAYLOAD=$(jq -n --arg body "$CHANGELOG_SECTION" '{body: $body}')
	RESPONSE=$(curl -sf -X PATCH \
		-H "$AUTH" \
		-H "Content-Type: application/json" \
		-d "$PAYLOAD" \
		"${API}/releases/${ID}")
	NEW_BODY=$(echo "$RESPONSE" | jq -r '.body')
	if [ "$NEW_BODY" = "$CHANGELOG_SECTION" ]; then
		echo "    OK"
	else
		echo "    WARNING: response body differs from what we sent — check manually"
	fi
	UPDATED=$((UPDATED + 1))

done < <(echo "$RELEASES" | jq -c '.[]')

echo ""
echo "Done. Updated: ${UPDATED}  Skipped (already set): ${SKIPPED}  Missing in CHANGELOG: ${MISSING}"
