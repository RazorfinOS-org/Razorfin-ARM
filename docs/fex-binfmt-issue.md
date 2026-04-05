# FEX-Emu / binfmt_dispatcher Exec Failure on Fedora 43 aarch64

## Problem

On Razorfin-ARM (Fedora COSMIC Atomic 43, aarch64, FEX-Emu 2603, erofs rootfs), FEXBash can execute bash builtins but fails when x86 bash tries to exec() any external binary or script:

```
FEXBash -c 'echo hello'                    # WORKS (builtin)
FEXBash -c 'true'                          # WORKS (builtin)
FEXBash -c 'uname -m'                      # FAILS
FEXBash -c '/path/to/steam.sh'             # FAILS
```

Error:
```
[binfmt_dispatcher] Using FEX
/run/user/1000/.FEXMount.../usr/bin/bash: /run/user/1000/.FEXMount.../usr/bin/bash: cannot execute binary file
```

Environment: FEX 2603, muvm 0.5.1, binfmt-dispatcher 0.1.2, erofs rootfs via erofsfuse, binfmt flags POCF, 4K page kernel, running in UTM VM on Apple Silicon.

---

## Root Cause Analysis

Two upstream bugs are the most likely causes, possibly compounding each other:

### 1. binfmt-dispatcher argv mangling (PRIMARY)

**Issue:** [AsahiLinux/binfmt-dispatcher#6](https://github.com/AsahiLinux/binfmt-dispatcher/issues/6) (OPEN)

binfmt-dispatcher has a confirmed bug in argument handling with POCF flags. When binfmt_misc is configured with the P (preserve-argv0) and O (open-binary) flags, the kernel passes the binary path via both argv AND fd3. binfmt-dispatcher reads both, causing **duplicate/mangled arguments** to reach FEX:

- User `es-fabricemarie`: "On Fedora 40, the package is configured to register itself to binfmt-misc with 'POCF' flags. So binfmt-dispatcher receives the calling args several times."
- User `GnomedDev`: args become `["/path/to/binary", "./binary", "./binary", "foo", "bar"]`
- User `davidvfx07`: "this makes binfmt-dispatcher unusable"
- User `tomeuv`: "From what I can see, binfmt-dispatcher in Fedora is completely broken"

**Proposed fix:** [PR #7](https://github.com/AsahiLinux/binfmt-dispatcher/pull/7) exists but introduces new issues and has NOT been merged. Maintainer (davide125) acknowledged the bug but hasn't shipped a fix.

**Fedora status:** binfmt-dispatcher 0.1.2 ships in Fedora 42/43/44 — the broken version.

**Why builtins work but exec fails:** Bash builtins never trigger exec(). When x86 bash tries to exec() an external x86 binary (like `uname`), the kernel's binfmt_misc intercepts it and invokes binfmt-dispatcher AGAIN for the child process, where the argv mangling causes the failure.

### 2. erofsfuse noexec mount (CONTRIBUTING)

FUSE user-mounts may inherit `noexec` via `user` mount option semantics. If FEXServer's erofsfuse invocation doesn't explicitly pass `-o exec`, the mount may have `noexec` set, causing the kernel to reject exec() calls with EACCES before binfmt_misc even runs.

**Diagnostic:** Run `cat /proc/mounts | grep erofs` while a FEXBash session is active and check for `noexec` in mount options.

---

## Confirmed Workaround

Rob Clark (robclark) confirmed on the [Fedora Discussion forum](https://discussion.fedoraproject.org/t/issues-and-comments-with-fex-on-fedora-42/154860) (September 2025):

> "the secret seems to be `sudo dnf rm binfmt-dispatcher`"

On 4K-page kernels, binfmt-dispatcher is unnecessary — FEX can register its own binfmt_misc handler directly. binfmt-dispatcher exists primarily for 16K-page systems (Apple Silicon native) where muvm routing is needed.

---

## Workarounds (ordered by preference)

### Option A: Remove binfmt-dispatcher (recommended for 4K-page systems)

```bash
# In the container build (01-gaming.sh):
dnf5 remove -y binfmt-dispatcher
# FEX's own binfmt registration (/usr/lib/binfmt.d/FEX-x86*.conf) will be used directly
```

This bypasses the broken argv handling entirely. FEX registers with systemd-binfmt directly via its own .conf files.

**Risk:** Breaks 16K-page kernel support (no muvm routing). Acceptable for Razorfin-ARM since we require 4K pages.

### Option B: Disable muvm in binfmt-dispatcher config

```bash
# Edit /usr/lib/binfmt-dispatcher.d/00-default.toml
# Comment out the use_muvm line
```

Keeps binfmt-dispatcher but removes the muvm routing that may contribute to the issue.

### Option C: Use FEXInterpreter directly

```bash
# In razorfin-steam wrapper:
exec FEXInterpreter /path/to/x86/bash -- -c "${STEAM_DIR}/steam.sh $*"
```

Bypasses binfmt_misc entirely for the initial invocation. Internal exec() calls from x86 bash would still go through binfmt_misc, so this may not fully solve the problem.

### Option D: Extract the erofs rootfs

```bash
# During image build, extract erofs to a directory instead of using erofsfuse
mkdir -p /usr/share/fex-emu/RootFS/default
mount -t erofs /usr/share/fex-emu/RootFS/default.erofs /mnt
cp -a /mnt/* /usr/share/fex-emu/RootFS/default/
umount /mnt
```

Eliminates the FUSE mount entirely. Costs ~2GB disk space but removes the noexec/FUSE interaction issue.

---

## Related Upstream Issues

| Issue | Status | Relevance |
|-------|--------|-----------|
| [AsahiLinux/binfmt-dispatcher#6](https://github.com/AsahiLinux/binfmt-dispatcher/issues/6) | OPEN | PRIMARY — argv mangling with POCF flags |
| [AsahiLinux/binfmt-dispatcher#7](https://github.com/AsahiLinux/binfmt-dispatcher/pull/7) | OPEN (PR) | Proposed fix, introduces new issues |
| [FEX-Emu/FEX#5234](https://github.com/FEX-Emu/FEX/issues/5234) | CLOSED | binfmt_misc + MFD_CLOEXEC bug (fixed in 2603) |
| [FEX-Emu/FEX#1647](https://github.com/FEX-Emu/FEX/issues/1647) | OPEN | Shebang resolution inconsistency in rootfs |
| [Fedora Discussion: FEX on F42](https://discussion.fedoraproject.org/t/issues-and-comments-with-fex-on-fedora-42/154860) | Active | Rob Clark's workaround: remove binfmt-dispatcher |
| [Ubuntu LP#1948684](https://bugs.launchpad.net/ubuntu/+source/qemu/+bug/1948684) | FIXED | QEMU had identical POCF argv bug |

---

## Recommended Next Step

**Try Option A** (remove binfmt-dispatcher) in a test build. Add to `01-gaming.sh`:

```bash
# Remove binfmt-dispatcher — its argv handling is broken with POCF flags
# (AsahiLinux/binfmt-dispatcher#6). On 4K-page kernels, FEX registers
# directly via /usr/lib/binfmt.d/FEX-x86*.conf.
dnf5 remove -y binfmt-dispatcher
```

If this resolves the issue, ship it. When binfmt-dispatcher eventually gets a fix upstream, re-evaluate.
