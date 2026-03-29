# Release Runbook

## 1. Overview

Razorfin ARM uses a three-tier release channel system. Images are built once and promoted by re-tagging rather than rebuilding, ensuring that each channel ships the exact same image digest that was validated in the tier below it.

## 2. Release Channels

| Channel | Update Frequency | Source | Target Audience |
|---------|-----------------|--------|-----------------|
| `testing` | Every push to `main` + daily (04:40 UTC) if upstream changed | Fresh build | Developers and testers |
| `latest` | Daily (10:05 UTC) | Previous day's `testing` | General users |
| `stable` | Weekly (Tuesday 10:05 UTC) | Previous week's `latest` | Users requiring stability |

Each promotion also produces a date-stamped tag for rollback purposes (e.g., `testing.20260208`, `latest.20260208`, `stable.20260208`).

## 3. CI/CD Workflows

| Workflow | File | Purpose |
|----------|------|---------|
| **Build** | `build.yml` | Checks for upstream Fedora COSMIC Atomic changes, builds both variants, and pushes to the `testing` tag |
| **Promote** | `promote.yml` | Handles daily and weekly promotion via `skopeo copy` with Cosign signing |

## 4. Standard Promotion Flow

```
push to main ──┐
               ├──> build.yml: check → build + push to :testing, :testing.YYYYMMDD, :YYYYMMDD
schedule ──────┘    (skips build if no upstream Fedora COSMIC Atomic change)
    |
    v  (daily 10:05 UTC, promote.yml)
:testing  -->  :latest, :latest.YYYYMMDD
    |
    v  (Tuesday 10:05 UTC, promote.yml)
:latest  -->  :stable, :stable.YYYYMMDD
```

The build workflow runs a **check** job before building. For scheduled runs (daily at 04:40 UTC), it compares the upstream Fedora COSMIC Atomic `:43` digest against the `org.opencontainers.image.base.digest` label on the current `:testing` image. If the base image is unchanged, the build is skipped. Push, pull request, and manual dispatch events always build.

On Tuesdays, the stable promotion runs **before** the daily promotion. This ensures that `stable` receives the week-old `latest` image rather than the image just promoted from `testing`.

## 5. Image Variants

All promotions apply to every variant in the build matrix:

- `razorfin-arm` (base — COSMIC + FEX-Emu gaming)
- `razorfin-arm-dx` (developer experience — adds build tools, debuggers, container utilities)

## 6. Build Infrastructure

- **Runner**: `ubuntu-24.04-arm` (native aarch64 GitHub Actions runner)
- **Base image**: `quay.io/fedora-ostree-desktops/cosmic-atomic:43`
- **No rechunk**: v1 skips the `ublue-os/legacy-rechunk` step (no aarch64 rechunk image available). Images are pushed directly via buildah/skopeo.
- **Signing**: All images are signed with Cosign using the `COSIGN_PRIVATE_KEY` repository secret.

## 7. Emergency Hotfix Procedure

Use this procedure when a critical fix must reach `latest` or `stable` immediately, bypassing the scheduled promotion cadence.

1. Merge the fix to `main`. This triggers a standard `testing` build.
2. Navigate to **Actions > Build container image > Run workflow**.
3. Set **Target channel** to `latest` or `stable`.
4. Click **Run workflow**.

The workflow:

- Builds the image and pushes it to `testing` as normal.
- Copies the image to `latest` (and `latest.YYYYMMDD`) via `skopeo copy`.
- If `stable` was selected, the promotion cascades to both `latest` and `stable`.
- Each promoted tag reference is signed with Cosign.

## 8. Rollback Procedures

### 8.1 Rollback via the Promote Workflow (Recommended)

1. Navigate to **Actions > Promote container image > Run workflow**.
2. Set **Source tag** to a known-good date-stamped tag (e.g., `stable.20260201`).
3. Set **Target tag** to the channel to restore (e.g., `stable`).
4. Click **Run workflow**.

### 8.2 Rollback on a Single Machine

```bash
sudo bootc switch ghcr.io/razorfinos-org/razorfin-arm:stable.20260201
systemctl reboot
```

### 8.3 Rollback to Previous Boot Entry

```bash
sudo bootc status
sudo bootc rollback
systemctl reboot
```

## 9. Seeding Initial Tags

When the channel system is first deployed, only `testing` tags will exist. To seed the remaining channels:

1. Run the **Promote container image** workflow manually with `source_tag: testing` and `target_tag: latest`.
2. Run it again with `source_tag: latest` and `target_tag: stable`.

After the initial seeding, the daily and weekly schedules will maintain all channels automatically.

## 10. Verifying a Release

### 10.1 Listing Tags on GHCR

```bash
skopeo list-tags docker://ghcr.io/razorfinos-org/razorfin-arm
skopeo inspect --format '{{.Digest}}' docker://ghcr.io/razorfinos-org/razorfin-arm:stable
```

### 10.2 Verifying the Cosign Signature

```bash
cosign verify --key cosign.pub ghcr.io/razorfinos-org/razorfin-arm:stable
```

### 10.3 Confirming Two Tags Point to the Same Image

```bash
TESTING=$(skopeo inspect --format '{{.Digest}}' docker://ghcr.io/razorfinos-org/razorfin-arm:testing)
LATEST=$(skopeo inspect --format '{{.Digest}}' docker://ghcr.io/razorfinos-org/razorfin-arm:latest)
echo "testing: ${TESTING}"
echo "latest:  ${LATEST}"
[[ "${TESTING}" == "${LATEST}" ]] && echo "MATCH" || echo "MISMATCH"
```

### 10.4 Checking What a Running System Is Tracking

```bash
bootc status
```

## 11. Troubleshooting

### 11.1 Promotion Skipped: Source Tag Not Found

The promote workflow will skip gracefully if the source tag does not exist. This is expected during initial seeding or if a preceding build failed. Review the build workflow logs.

### 11.2 Tuesday Stable Promotion Received Today's Testing Image

This should not occur because the stable promotion step is ordered before the daily testing-to-latest step. If it does, use a manual rollback to the `stable.YYYYMMDD` tag from the previous week.

### 11.3 Emergency Promote Failed

The emergency promote steps execute after the standard push step. If the build itself failed, the promote steps are skipped. Resolve the build failure first, then re-dispatch.

### 11.4 Scheduled Build Skipped: No Upstream Changes

The build workflow's `check` job compares the upstream Fedora COSMIC Atomic base image digest against the `org.opencontainers.image.base.digest` label on the current `:testing` images. If digests match, the build is skipped. To force a rebuild, use **Actions > Build container image > Run workflow** (manual dispatch always builds).

### 11.5 FEX-Emu Not Working

FEX-Emu requires a 4K page-size kernel. Verify with:

```bash
getconf PAGE_SIZE  # Should output: 4096
```

If the page size is not 4096 (e.g., 16K or 64K on some ARM platforms), FEX will attempt to use muvm (a lightweight micro-VM) as a workaround, but performance may be degraded.

Test FEX functionality:

```bash
FEXBash uname -m  # Should output: x86_64
```

### 11.6 Steam Fails to Launch

Steam runs through FEX-Emu. Common issues:

1. Verify FEX works: `FEXBash uname -m`
2. Check Steam installation in FEX rootfs
3. Try launching manually: `FEXBash -c "steam"`
4. Check for conflicting libraries in `~/.local/share/Steam/`
