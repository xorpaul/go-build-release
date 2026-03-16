#!/usr/bin/env bash
# Script to monitor and deploy a new Go binary on a dev server.
# Usage: ./watch-and-deploy.sh <binary-name> [service-name]
#   binary-name  — mandatory, name of the Go binary in $HOME (e.g. goahead or pkgproxy)
#   service-name — optional systemd service to restart (defaults to binary-name)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

if [[ -z "${1:-}" ]]; then
	echo -e "${RED}Usage: $0 <binary-name> [service-name]${NC}" >&2
	exit 1
fi

BINARY_NAME="$1"
SERVICE_NAME="${2:-$BINARY_NAME}"
BINARY_PATH="$HOME/$BINARY_NAME"
INSTALL_PATH="/usr/local/bin/$BINARY_NAME"
CHECK_INTERVAL=1 # seconds between checks

echo -e "${CYAN}${BOLD}Watching for new binary at ${BINARY_PATH}...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"

while true; do
	# Check if binary exists
	if [[ ! -f "$BINARY_PATH" ]]; then
		sleep "$CHECK_INTERVAL"
		continue
	fi

	# Get binary modification time (epoch seconds)
	BINARY_MTIME=$(stat -c %Y "$BINARY_PATH")

	# Get service start time (epoch seconds)
	SERVICE_START=$(systemctl show "$SERVICE_NAME" --property=ActiveEnterTimestamp --value 2>/dev/null || echo "")
	if [[ -z "$SERVICE_START" || "$SERVICE_START" == "n/a" ]]; then
		# Service might not be running, use epoch 0
		SERVICE_START_EPOCH=0
	else
		SERVICE_START_EPOCH=$(date -d "$SERVICE_START" +%s 2>/dev/null || echo "0")
	fi

	# Check if binary is newer than service start time
	if [[ "$BINARY_MTIME" -gt "$SERVICE_START_EPOCH" ]]; then
		echo -e "${GREEN}${BOLD}$(date '+%Y-%m-%d %H:%M:%S') - New binary detected${NC} ${BLUE}(mtime: $(date -d @$BINARY_MTIME '+%H:%M:%S'))${NC}"

		# Wait for file size to stabilize (scp in progress check)
		PREV_SIZE=0
		CURR_SIZE=$(stat -c %s "$BINARY_PATH")

		while [[ "$CURR_SIZE" -ne "$PREV_SIZE" ]]; do
			echo -e "  ${YELLOW}⏳ Waiting for transfer to complete...${NC} (current size: ${CYAN}$CURR_SIZE${NC} bytes)"
			PREV_SIZE=$CURR_SIZE
			sleep 1
			CURR_SIZE=$(stat -c %s "$BINARY_PATH")
		done

		echo -e "  ${GREEN}✓ Binary size stable at ${CYAN}$CURR_SIZE${NC} bytes"

		# Verify binary is complete and executable by running --version
		echo -e "  ${YELLOW}🔍 Verifying binary integrity...${NC}"
		if ! VERSION_OUTPUT=$("$BINARY_PATH" --version 2>&1); then
			echo -e "  ${RED}✗ Binary verification failed (incomplete transfer?)${NC}"
			echo -e "  ${RED}  Output: $VERSION_OUTPUT${NC}"
			sleep "$CHECK_INTERVAL"
			continue
		fi
		echo -e "  ${GREEN}✓ Binary verified: ${CYAN}$VERSION_OUTPUT${NC}"

		echo -e "  ${BLUE}${BOLD}🚀 Deploying new binary...${NC}"

		# Stop service, copy binary, start service
		echo -e "  ${YELLOW}⏹ Stopping ${SERVICE_NAME}...${NC}"
		sudo systemctl stop "$SERVICE_NAME"

		echo -e "  ${BLUE}📦 Copying binary to ${INSTALL_PATH}...${NC}"
		sudo cp "$BINARY_PATH" "$INSTALL_PATH"

		echo -e "  ${GREEN}▶ Starting ${SERVICE_NAME}...${NC}"
		sudo systemctl start "$SERVICE_NAME"

		echo -e "  ${GREEN}${BOLD}✅ Deployment complete!${NC}"
		echo -e "${CYAN}-------------------------------------------${NC}"

	fi

	sleep "$CHECK_INTERVAL"
done
