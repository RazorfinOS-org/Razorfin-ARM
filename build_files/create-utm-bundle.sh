#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_DIR="$REPO_DIR/utm_template"
OUTPUT_DIR="$REPO_DIR/output/qcow2"
QCOW2_FILE="$OUTPUT_DIR/disk.qcow2"
UTM_BUNDLE="$OUTPUT_DIR/Razorfin-ARM.utm"

# Defaults
RAM="${RAM:-8192}"
CPUS="${CPUS:-4}"
DISK_SIZE="${DISK_SIZE:-64}"

usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Generate a UTM-compatible .utm bundle from a built QCOW2 image.

Options:
    -r, --ram SIZE      RAM in MB (default: 8192)
    -c, --cpus COUNT    CPU cores (default: 4)
    -d, --disk SIZE     Disk size in GB (default: 64)
    -o, --output PATH   Output directory for .utm bundle (default: output/qcow2/)
    -h, --help          Show this help message

Environment variables:
    RAM                 Override default RAM size (MB)
    CPUS                Override default CPU count
    DISK_SIZE           Override default disk size (GB)

Prerequisites:
    - Run 'just build-qcow2' first to generate the QCOW2 image
    - UTM must be installed on macOS to open the resulting .utm bundle
    - The generated UTM bundle defaults to Shared networking with an Intel E1000 NIC
EOF
	exit 0
}

while [[ $# -gt 0 ]]; do
	case $1 in
	-r | --ram)
		RAM="$2"
		shift 2
		;;
	-c | --cpus)
		CPUS="$2"
		shift 2
		;;
	-d | --disk)
		DISK_SIZE="$2"
		shift 2
		;;
	-o | --output)
		OUTPUT_DIR="$2"
		shift 2
		;;
	-h | --help) usage ;;
	*)
		echo "Unknown option: $1"
		exit 1
		;;
	esac
done

# Validate prerequisites
if [[ ! -f "$QCOW2_FILE" ]]; then
	echo "ERROR: QCOW2 image not found at $QCOW2_FILE"
	echo "Run 'just build-qcow2' first."
	exit 1
fi

if [[ ! -d "$TEMPLATE_DIR" ]]; then
	echo "ERROR: UTM template directory not found at $TEMPLATE_DIR"
	exit 1
fi

echo "Building UTM bundle..."
echo "  RAM: ${RAM}MB"
echo "  CPUs: ${CPUS}"
echo "  Disk: ${DISK_SIZE}GB"
echo "  Source: $QCOW2_FILE"

# Clean previous bundle
rm -rf "$UTM_BUNDLE"

# Create UTM bundle structure (UTM 4.x uses Data/ not Images/)
mkdir -p "$UTM_BUNDLE/Data"

# Copy disk image
cp "$QCOW2_FILE" "$UTM_BUNDLE/Data/disk.qcow2"

# Generate config.plist from template
CONFIG_PLIST="$UTM_BUNDLE/config.plist"
cp "$TEMPLATE_DIR/config.plist" "$CONFIG_PLIST"

# Update RAM, CPU count, UUIDs, and MAC address in config.plist using Python plistlib
python3 - "$CONFIG_PLIST" "$RAM" "$CPUS" <<'PYEOF'
import sys
import plistlib
import uuid

config_path = sys.argv[1]
ram = int(sys.argv[2])
cpus = int(sys.argv[3])

with open(config_path, 'rb') as f:
    config = plistlib.load(f)

config['System']['MemorySize'] = ram
config['System']['CPUCount'] = cpus
config['Information']['UUID'] = str(uuid.uuid4()).upper()
config['Drive'][0]['Identifier'] = str(uuid.uuid4()).upper()
config['Network'][0]['MacAddress'] = '02:00:00:' + ':'.join(f'{b:02x}' for b in uuid.uuid4().bytes[:3])

with open(config_path, 'wb') as f:
    plistlib.dump(config, f)
PYEOF

echo ""
echo "UTM bundle created at: $UTM_BUNDLE"
echo ""
echo "To use:"
echo "  1. Double-click $UTM_BUNDLE to open in UTM"
echo "  2. Or run: open \"$UTM_BUNDLE\""
echo ""
echo "Default login: razorfin / razorfin"
