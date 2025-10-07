#!/usr/bin/env bash
set -euo pipefail
rm build/* || true

echo "Starting tests..."
go test -v ./...

export CGO_ENABLED=0
if [ $# -eq 0 ]; then
	echo "Error: version parameter is required (e.g., 1.0.0)" >&2
	exit 1
fi

if [[ "$1" == v* ]]; then
	V="$1"
else
	V="v$1"
fi

# use current directory name as project name
PROJECTNAME=$(basename "$(pwd)")
UPX=$(which upx)
UPX_COMPRESSION_LEVEL=5
BUILDTIME=$(date -u '+%Y-%m-%d_%H:%M:%S')
GOPARAMS="-s -w -X main.buildtime=$BUILDTIME -X main.buildversion=${V}"

# Read build configuration from .build.cfg if it exists
# Default to all platforms if no config file exists
BUILD_LINUX=true
BUILD_MACOS_AMD64=true
BUILD_MACOS_ARM64=true
BUILD_WINDOWS=true

if [ -f ".build.cfg" ]; then
	echo "Found .build.cfg, reading build configuration..."
	# Reset defaults to false when config file exists
	BUILD_LINUX=false
	BUILD_MACOS_AMD64=false
	BUILD_MACOS_ARM64=false
	BUILD_WINDOWS=false

	# Source the config file
	source .build.cfg

	echo "Build configuration:"
	echo "  Linux AMD64: $BUILD_LINUX"
	echo "  macOS AMD64: $BUILD_MACOS_AMD64"
	echo "  macOS ARM64: $BUILD_MACOS_ARM64"
	echo "  Windows AMD64: $BUILD_WINDOWS"
else
	echo "No .build.cfg found, building for all platforms"
fi

# Build for Linux AMD64
if [ "$BUILD_LINUX" = true ]; then
	echo "Building for Linux AMD64..."
	env GOOS=linux GOARCH=amd64 go build -ldflags "${GOPARAMS}" -o build/${PROJECTNAME}_${V}_linux-amd64
	if [ ${#UPX} -gt 0 ]; then
		${UPX} -${UPX_COMPRESSION_LEVEL} build/${PROJECTNAME}_${V}_linux-amd64
	fi
fi

# Build for macOS AMD64
if [ "$BUILD_MACOS_AMD64" = true ]; then
	echo "Building for macOS AMD64..."
	env GOOS=darwin GOARCH=amd64 go build -ldflags "${GOPARAMS}" -o build/${PROJECTNAME}_${V}_macos-amd64
fi

# Build for macOS ARM64
if [ "$BUILD_MACOS_ARM64" = true ]; then
	echo "Building for macOS ARM64..."
	env GOOS=darwin GOARCH=arm64 go build -ldflags "${GOPARAMS}" -o build/${PROJECTNAME}_${V}_macos-arm64
fi

# Build for Windows AMD64
if [ "$BUILD_WINDOWS" = true ]; then
	echo "Building for Windows AMD64..."
	env GOOS=windows GOARCH=amd64 go build -ldflags "${GOPARAMS}" -o build/${PROJECTNAME}_${V}_windows-amd64.exe
	if [ ${#UPX} -gt 0 ]; then
		${UPX} -${UPX_COMPRESSION_LEVEL} build/${PROJECTNAME}_${V}_windows-amd64.exe
	fi
fi

# Function definitions
create_github_release() {
	if gh auth status >/dev/null 2>&1; then
		echo "GitHub CLI is authenticated."
	else
		echo "Error: GitHub CLI is not authenticated. Please run 'gh auth login'." >&2
		exit 1
	fi
	echo "creating github release ${V}"
	gh release create --fail-on-no-commits --verify-tag --repo ${GIT_REPO_OWNER}/${GIT_REPO_NAME} --title "${V}" --notes "Automated release of ${V}" ${V} "./build/${GIT_REPO_NAME}*"
}

create_gitea_release() {
	# create and upload to gitea
	if [ -f ~/.gitea_env ]; then
		echo "Creating release on Gitea..."
		source ~/.gitea_env

		# Get the commit SHA for the tag
		TAG_COMMIT=$(git rev-parse "${V}")
		echo "Tag ${V} points to commit: ${TAG_COMMIT}"

		# Check if release already exists
		EXISTING_RELEASE=$(curl -s -H "Authorization: token ${GIT_TOKEN}" \
			"${GIT_URL}/api/v1/repos/${GIT_REPO_OWNER}/${GIT_REPO_NAME}/releases/tags/${V}")

		if echo "$EXISTING_RELEASE" | jq -e '.id' >/dev/null 2>&1; then
			echo "Release for tag ${V} already exists, getting existing release ID..."
			RELEASE_ID=$(echo "$EXISTING_RELEASE" | jq -r '.id')
			echo "Using existing release ID: $RELEASE_ID"
		else
			echo "Creating new release for tag ${V}..."
			# create a new release
			RELEASE_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -H "Authorization: token ${GIT_TOKEN}" \
				-d "{\"tag_name\":\"${V}\",\"target_commitish\":\"${TAG_COMMIT}\",\"name\":\"${V}\",\"body\":\"Release ${V}\",\"draft\":false,\"prerelease\":false}" \
				"${GIT_URL}/api/v1/repos/${GIT_REPO_OWNER}/${GIT_REPO_NAME}/releases")

			echo "$RELEASE_RESPONSE" | jq .

			# Extract release ID from response
			RELEASE_ID=$(echo "$RELEASE_RESPONSE" | jq -r '.id')

			if [ "$RELEASE_ID" = "null" ] || [ -z "$RELEASE_ID" ]; then
				echo "Error: Failed to create release or extract release ID"
				exit 1
			fi

			echo "Release created with ID: $RELEASE_ID"
		fi

		# upload the binaries
		for FILE in build/*; do
			echo "Uploading ${FILE} to Gitea..."
			FILENAME=$(basename "${FILE}")
			curl -s -X POST -H "Authorization: token ${GIT_TOKEN}" \
				-F "attachment=@${FILE}" \
				"${GIT_URL}/api/v1/repos/${GIT_REPO_OWNER}/${GIT_REPO_NAME}/releases/${RELEASE_ID}/assets?name=${FILENAME}" | jq .
		done
	else
		echo "Skipping Gitea release creation, .gitea_env file not found."
	fi
}

# Auto-detect repo owner, name, and URL from git remote
REMOTE_URL=$(git remote get-url origin)
echo "Git remote URL: ${REMOTE_URL}"

# Extract repo path and base URL from remote (handles both HTTPS and SSH formats)
if [[ "$REMOTE_URL" =~ (.*)@([^:]+):(.+)\.git$ ]]; then
	GIT_HOST="${BASH_REMATCH[2]}"
	REPO_PATH="${BASH_REMATCH[3]}"
	GIT_URL="https://${GIT_HOST}"
elif [[ "$REMOTE_URL" =~ (https?://[^/]+)/(.+)\.git$ ]]; then
	GIT_URL="${BASH_REMATCH[1]}"
	REPO_PATH="${BASH_REMATCH[2]}"
else
	echo "Error: Could not parse git remote URL: ${REMOTE_URL}"
	exit 1
fi

GIT_REPO_OWNER=$(dirname "$REPO_PATH")
GIT_REPO_NAME=$(basename "$REPO_PATH")

# Auto-detect current branch
CURRENT_BRANCH=$(git branch --show-current)

echo "Detected Git URL: ${GIT_URL}"
echo "Detected repo: ${GIT_REPO_OWNER}/${GIT_REPO_NAME}"
echo "Current branch: ${CURRENT_BRANCH}"

# Create git tag if it doesn't exist
if ! git rev-parse "${V}" >/dev/null 2>&1; then
	echo "Creating git tag: ${V}"
	git tag -a "${V}" -m "Release ${V}"
	git push origin "${V}"
else
	echo "Git tag ${V} already exists"
fi

# Skip Gitea release creation if this is a GitHub repository
if [[ "$REMOTE_URL" =~ "github.com" ]]; then
	echo "Detected GitHub repository. Skipping Gitea release creation."
	echo "Using GitHub's release functionality instead."
	create_github_release
else
	create_gitea_release
fi
