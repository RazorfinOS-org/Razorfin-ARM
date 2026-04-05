export image_name := env("IMAGE_NAME", "razorfin-arm")
export default_tag := env("DEFAULT_TAG", "latest")
export bib_image := env("BIB_IMAGE", "quay.io/centos-bootc/bootc-image-builder:latest")
export default_base_image := env("BASE_IMAGE", "quay.io/fedora-ostree-desktops/cosmic-atomic:43")
export default_board_target := env("BOARD_TARGET", "generic")

alias build-vm := build-qcow2
alias rebuild-vm := rebuild-qcow2
alias run-vm := run-vm-qcow2

[private]
default:
    @just --list

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	just --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    just --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/env bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env
    rm -f output/

# Clean only UTM bundles
[group('Utility')]
clean-utm:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf output/qcow2/Razorfin-ARM.utm
    echo "UTM bundles cleaned."

# Sudo Clean Repo
[group('Utility')]
[private]
sudo-clean:
    just sudoif just clean

# sudoif bash function
[group('Utility')]
[private]
sudoif command *args:
    #!/usr/bin/env bash
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            /usr/bin/sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            /usr/bin/sudo "$@" || exit 1
        else
            exit 1
        fi
    }
    sudoif {{ command }} {{ args }}

# Build the base image (generic aarch64)
#
# Arguments:
#   $target_image - The tag for the output image (default: $image_name)
#   $tag - The tag for the image (default: $default_tag)
#   $base_image - The base image to use (default: $default_base_image)
#   $board_target - The board target (default: $default_board_target)
#

# Example: just build razorfin-arm latest
build $target_image=image_name $tag=default_tag $base_image=default_base_image $board_target=default_board_target:
    #!/usr/bin/env bash

    BUILD_ARGS=()
    BUILD_ARGS+=("--build-arg" "BASE_IMAGE=${base_image}")
    BUILD_ARGS+=("--build-arg" "BOARD_TARGET=${board_target}")
    BUILD_ARGS+=("--build-arg" "DX_VARIANT=false")
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi

    podman build \
        "${BUILD_ARGS[@]}" \
        --pull=newer \
        --tag "${target_image}:${tag}" \
        .

# Build DX variant (developer tools)
[group('Build Variants')]
build-dx $target_image=("localhost/" + image_name + "-dx") $tag=default_tag $board_target=default_board_target:
    #!/usr/bin/env bash
    BUILD_ARGS=()
    BUILD_ARGS+=("--build-arg" "BASE_IMAGE=${BASE_IMAGE:-quay.io/fedora-ostree-desktops/cosmic-atomic:43}")
    BUILD_ARGS+=("--build-arg" "BOARD_TARGET=${board_target}")
    BUILD_ARGS+=("--build-arg" "DX_VARIANT=true")
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi
    podman build \
        "${BUILD_ARGS[@]}" \
        --pull=newer \
        --tag "${target_image}:${tag}" \
        .

# Build for Raspberry Pi 5 (experimental)
[group('Build Variants')]
build-rpi5 $target_image=("localhost/" + image_name + "-rpi5") $tag=default_tag:
    #!/usr/bin/env bash
    BUILD_ARGS=()
    BUILD_ARGS+=("--build-arg" "BASE_IMAGE=${BASE_IMAGE:-quay.io/fedora-ostree-desktops/cosmic-atomic:43}")
    BUILD_ARGS+=("--build-arg" "BOARD_TARGET=rpi5")
    BUILD_ARGS+=("--build-arg" "DX_VARIANT=false")
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi
    podman build \
        "${BUILD_ARGS[@]}" \
        --pull=newer \
        --tag "${target_image}:${tag}" \
        .

# Build for Rockchip (experimental)
[group('Build Variants')]
build-rockchip $target_image=("localhost/" + image_name + "-rockchip") $tag=default_tag:
    #!/usr/bin/env bash
    BUILD_ARGS=()
    BUILD_ARGS+=("--build-arg" "BASE_IMAGE=${BASE_IMAGE:-quay.io/fedora-ostree-desktops/cosmic-atomic:43}")
    BUILD_ARGS+=("--build-arg" "BOARD_TARGET=rockchip")
    BUILD_ARGS+=("--build-arg" "DX_VARIANT=false")
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi
    podman build \
        "${BUILD_ARGS[@]}" \
        --pull=newer \
        --tag "${target_image}:${tag}" \
        .

# Load image into rootful podman
_rootful_load_image $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -eoux pipefail

    if [[ -n "${SUDO_USER:-}" || "${UID}" -eq "0" ]]; then
        echo "Already root or running under sudo, no need to load image from user podman."
        exit 0
    fi

    set +e
    resolved_tag=$(podman inspect -t image "${target_image}:${tag}" | jq -r '.[].RepoTags.[0]')
    return_code=$?
    set -e

    USER_IMG_ID=$(podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")

    if [[ $return_code -eq 0 ]]; then
        ID=$(just sudoif podman images --filter reference="${target_image}:${tag}" --format "'{{ '{{.ID}}' }}'")
        if [[ "$ID" != "$USER_IMG_ID" ]]; then
            COPYTMP=$(mktemp -p "${PWD}" -d -t _build_podman_scp.XXXXXXXXXX)
            just sudoif TMPDIR=${COPYTMP} podman image scp ${UID}@localhost::"${target_image}:${tag}" root@localhost::"${target_image}:${tag}"
            rm -rf "${COPYTMP}"
        fi
    else
        just sudoif podman pull "${target_image}:${tag}"
    fi

# Build a bootc bootable image using Bootc Image Builder (BIB)
# On macOS (Podman Machine), output must be under a host-mounted path.

# On Linux, uses sudo for rootful podman access.
_build-bib $target_image $tag $type $config:
    #!/usr/bin/env bash
    set -euo pipefail

    args="--type ${type} "
    args+="--use-librepo=True "
    args+="--rootfs=btrfs"

    mkdir -p "$(pwd)/output"

    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS: Podman Machine handles rootful; output goes to ./output directly
        # Podman Machine mounts /Users, so ensure we're writing there or use a
        # staging dir under $HOME if the cwd isn't visible to the VM
        OUTPUT_DIR="$(pwd)/output"
        if ! podman machine ssh -- "test -d '$(pwd)'" 2>/dev/null; then
            OUTPUT_DIR="${HOME}/razorfin-arm-output"
            mkdir -p "${OUTPUT_DIR}"
            echo "NOTE: Working directory not mounted in Podman Machine VM."
            echo "Output will be staged at ${OUTPUT_DIR} and copied to ./output/"
        fi

        podman run \
          --rm \
          --privileged \
          --pull=newer \
          --security-opt label=type:unconfined_t \
          -v "${OUTPUT_DIR}":/output \
          -v /var/lib/containers/storage:/var/lib/containers/storage \
          "${bib_image}" \
          ${args} \
          "${target_image}:${tag}"

        # Copy from staging dir if needed
        if [[ "${OUTPUT_DIR}" != "$(pwd)/output" ]]; then
            cp -r "${OUTPUT_DIR}"/* "$(pwd)/output/"
            echo "Output copied to ./output/"
        fi
    else
        # Linux: use sudo for rootful podman access
        just _rootful_load_image "${target_image}" "${tag}"

        BUILDTMP=$(mktemp -p "${PWD}" -d -t _build-bib.XXXXXXXXXX)

        sudo podman run \
          --rm \
          -it \
          --privileged \
          --pull=newer \
          --net=host \
          --security-opt label=type:unconfined_t \
          -v "$(pwd)/${config}":/config.toml:ro \
          -v "${BUILDTMP}":/output \
          -v /var/lib/containers/storage:/var/lib/containers/storage \
          "${bib_image}" \
          ${args} \
          "${target_image}:${tag}"

        sudo mv -f "${BUILDTMP}"/* output/
        sudo rmdir "${BUILDTMP}"
        sudo chown -R "$USER:$USER" output/
    fi

_rebuild-bib $target_image $tag $type $config: (build target_image tag) && (_build-bib target_image tag type config)

# Build a QCOW2 virtual machine image
[group('Build Virtual Machine Image')]
build-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "qcow2" "disk_config/disk.toml")

# Build a RAW virtual machine image
[group('Build Virtual Machine Image')]
build-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "raw" "disk_config/disk.toml")

# Rebuild a QCOW2 virtual machine image
[group('Build Virtual Machine Image')]
rebuild-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "qcow2" "disk_config/disk.toml")

# Rebuild a RAW virtual machine image
[group('Build Virtual Machine Image')]
rebuild-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_rebuild-bib target_image tag "raw" "disk_config/disk.toml")

# Build a UTM bundle from the QCOW2 image
[group('Build Virtual Machine Image')]
build-utm ram="8192" cpus="4":
    #!/usr/bin/env bash
    set -euo pipefail
    RAM="{{ ram }}" CPUS="{{ cpus }}" bash build_files/create-utm-bundle.sh

# Rebuild container, QCOW2, and UTM bundle in one command
[group('Build Virtual Machine Image')]
rebuild-utm $target_image=("localhost/" + image_name) $tag=default_tag ram="8192" cpus="4": (build target_image tag) && (_build-bib target_image tag "qcow2" "disk_config/disk.toml") (build-utm ram cpus)

# Open the UTM bundle in UTM
[group('Run Virtual Machine')]
open-utm:
    #!/usr/bin/env bash
    set -euo pipefail
    UTM_BUNDLE="$(pwd)/output/qcow2/Razorfin-ARM.utm"
    if [[ ! -d "$UTM_BUNDLE" ]]; then
        echo "ERROR: UTM bundle not found at $UTM_BUNDLE"
        echo "Run 'just build-utm' or 'just rebuild-utm' first."
        exit 1
    fi
    open "$UTM_BUNDLE"

# Run a virtual machine with the specified image type and configuration
_run-vm $target_image $tag $type $config:
    #!/usr/bin/env bash
    set -eoux pipefail

    image_file="output/${type}/disk.${type}"

    if [[ ! -f "${image_file}" ]]; then
        just "build-${type}" "$target_image" "$tag"
    fi

    # Find an available port (Linux first, macOS fallback)
    port=8006
    while ss -tunalp 2>/dev/null | grep -q ":${port} " || lsof -iTCP:${port} -sTCP:LISTEN &>/dev/null; do
        port=$(( port + 1 ))
    done
    echo "Using Port: ${port}"
    echo "Connect to http://localhost:${port}"

    run_args=()
    run_args+=(--rm --privileged)
    run_args+=(--pull=newer)
    run_args+=(--publish "127.0.0.1:${port}:8006")
    run_args+=(--env "CPU_CORES=4")
    run_args+=(--env "RAM_SIZE=8G")
    run_args+=(--env "DISK_SIZE=64G")
    run_args+=(--env "TPM=Y")
    run_args+=(--env "GPU=Y")
    if [[ -e /dev/kvm ]]; then
        run_args+=(--device=/dev/kvm)
    fi
    run_args+=(--volume "${PWD}/${image_file}":"/boot.${type}")
    run_args+=(docker.io/qemux/qemu)

    # Open browser (Linux first, macOS fallback)
    OPEN_CMD="xdg-open"
    if ! command -v xdg-open &>/dev/null && command -v open &>/dev/null; then
        OPEN_CMD="open"
    fi
    (sleep 30 && ${OPEN_CMD} http://localhost:"$port") &
    podman run "${run_args[@]}"

# Run a virtual machine from a QCOW2 image
[group('Run Virtual Machine')]
run-vm-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "qcow2" "disk_config/disk.toml")

# Run a virtual machine from a RAW image
[group('Run Virtual Machine')]
run-vm-raw $target_image=("localhost/" + image_name) $tag=default_tag: && (_run-vm target_image tag "raw" "disk_config/disk.toml")

# Run a virtual machine using systemd-vmspawn
[group('Run Virtual Machine')]
spawn-vm rebuild="0" type="qcow2" ram="6G":
    #!/usr/bin/env bash

    set -euo pipefail

    [ "{{ rebuild }}" -eq 1 ] && echo "Rebuilding the ISO" && just build-vm {{ rebuild }} {{ type }}

    # Convert RAM size to bytes (cross-platform)
    RAM_BYTES=$(python3 -c "
    s='{{ ram }}'.upper()
    units={'K':1024,'M':1024**2,'G':1024**3,'T':1024**4}
    for u,v in units.items():
        if s.endswith(u): print(int(s[:-1])*v); break
    else: print(s)
    ")

    systemd-vmspawn \
      -M "bootc-image" \
      --console=gui \
      --cpus=2 \
      --ram=${RAM_BYTES} \
      --network-user-mode \
      --vsock=false --pass-ssh-key=false \
      -i ./output/**/*.{{ type }}

# Runs shell check on all Bash scripts
lint:
    #!/usr/bin/env bash
    set -eoux pipefail
    if ! command -v shellcheck &>/dev/null; then
        echo "shellcheck could not be found. Install with: brew install shellcheck"
        exit 1
    fi
    find . -iname "*.sh" -type f -exec shellcheck "{}" ';'

# Runs shfmt on all Bash scripts
format:
    #!/usr/bin/env bash
    set -eoux pipefail
    if ! command -v shfmt &>/dev/null; then
        echo "shfmt could not be found. Install with: brew install shfmt"
        exit 1
    fi
    find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'
