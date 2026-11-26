#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# create-17s-branch.sh -- generate the rootless SKYNET "17S" branch from the
# current tree, keeping every non-root Android 17 / uname / freezer /
# rtmutex / capability fix while removing BakaSU (KernelSU) and SUSFS v2.4.0
# without touching the rooted working branch.

set -euo pipefail

readonly BASE_COMMIT="289e2aabba3fc2a1a16eff9130f72ddfd3a0fb68"
readonly ROOT_INTRO_COMMIT="39536d2ff6cf71baa8303cbbfc5de11a3a271414"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANCH_NAME="17S"
PUSH_REMOTE=""
IN_PLACE=0

usage() {
    cat <<'USAGE'
Usage: scripts/create-17s-branch.sh [options]

Creates or updates the rootless `17S` branch from HEAD while leaving the
current rooted branch untouched (uses a temporary git worktree unless
--in-place is passed).

  --branch NAME     Target branch name (default: 17S).
  --push [REMOTE]   Push the generated branch to REMOTE (default: origin).
  --in-place        Transform the current checkout in place and commit on the
                    checked-out HEAD (for disposable CI checkouts only).
  -h, --help        Show this help.
USAGE
}

log() { printf '[17S] %s\n' "$*"; }
die() { printf '[17S] ERROR: %s\n' "$*" >&2; exit 1; }

while (($#)); do
    case "$1" in
        --branch)
            BRANCH_NAME="${2:?--branch needs a value}"
            shift 2
            ;;
        --push)
            if [[ $# -ge 2 && "$2" != -* ]]; then
                PUSH_REMOTE="$2"
                shift 2
            else
                PUSH_REMOTE="origin"
                shift
            fi
            ;;
        --in-place)
            IN_PLACE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1 (try --help)"
            ;;
    esac
done

git -C "$REPO_ROOT" cat-file -e "${BASE_COMMIT}^{commit}" \
    || die "missing base commit ${BASE_COMMIT}; fetch full history (git fetch --unshallow)"
git -C "$REPO_ROOT" cat-file -e "${ROOT_INTRO_COMMIT}^{commit}" \
    || die "missing commit ${ROOT_INTRO_COMMIT}; fetch full history (git fetch --unshallow)"

strip_root_in_dir() {
    local dir="$1"
    local non_root_patch

    log "preserving non-root fixes in fs/proc/base.c and kernel/sys.c"
    non_root_patch="$(git -C "$dir" diff "${ROOT_INTRO_COMMIT}..HEAD" -- fs/proc/base.c kernel/sys.c)"

    log "restoring root-only modified kernel files to pre-KSU/SUSFS state"
    git -C "$dir" checkout "$BASE_COMMIT" -- \
        block/ioprio.c \
        drivers/Kconfig \
        drivers/Makefile \
        drivers/input/input.c \
        fs/Kconfig \
        fs/Makefile \
        fs/exec.c \
        fs/internal.h \
        fs/namei.c \
        fs/namespace.c \
        fs/notify/fdinfo.c \
        fs/open.c \
        fs/proc/base.c \
        fs/proc/cmdline.c \
        fs/proc/fd.c \
        fs/proc/task_mmu.c \
        fs/proc_namespace.c \
        fs/read_write.c \
        fs/readdir.c \
        fs/stat.c \
        fs/statfs.c \
        fs/super.c \
        kernel/kallsyms.c \
        kernel/reboot.c \
        kernel/sys.c \
        mm/memory.c \
        security/selinux/avc.c \
        security/selinux/hooks.c \
        security/selinux/selinuxfs.c \
        security/selinux/ss/services.c

    if [[ -n "$non_root_patch" ]]; then
        printf '%s\n' "$non_root_patch" | git -C "$dir" apply --index -
    fi

    log "removing BakaSU submodule, drivers/kernelsu symlink, and SUSFS v2.4.0 files"
    git -C "$dir" rm -rf --ignore-unmatch \
        .gitmodules \
        KernelSU \
        drivers/kernelsu \
        fs/susfs.c \
        include/linux/susfs.h \
        include/linux/susfs_def.h
    rm -rf "$dir/KernelSU" "$dir/.gitmodules" "$dir/drivers/kernelsu"

    log "removing CONFIG_KSU* symbols from miatoll_defconfig (keeping Android 17 options)"
    sed -i '/^CONFIG_KSU/d' "$dir/arch/arm64/configs/vendor/xiaomi/miatoll_defconfig"
    git -C "$dir" add arch/arm64/configs/vendor/xiaomi/miatoll_defconfig

    log "setting rootless 17S uname string in init/version.c"
    python3 - "$dir/init/version.c" <<'PY'
import sys
p = sys.argv[1]
with open(p, "r", encoding="utf-8") as f:
    s = f.read()
old = """#ifdef CONFIG_KSU
#define SKYNET_UTS_RELEASE "5.10.357-Skynet-17R-Openela"
#else
#define SKYNET_UTS_RELEASE "5.10.357-Skynet-17S-Openela"
#endif"""
new = '#define SKYNET_UTS_RELEASE "5.10.357-Skynet-17S-Openela"'
if old in s:
    s = s.replace(old, new, 1)
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)
PY
    git -C "$dir" add init/version.c

    log "updating AnyKernel3 banner for rootless 17S"
    sed -i \
        -e 's/SKYNET Kernel 17 — Xiaomi Miatoll (SM6250), Android 17 + BakaSU & SUSFS v2.4.0./SKYNET Kernel 17S — Xiaomi Miatoll (SM6250), Android 17 (rootless)./' \
        -e 's/BakaSU (KernelSU) and SUSFS v2.4.0 are built directly into the kernel image./Rootless 17S build with no KernelSU or SUSFS hooks./' \
        -e 's/kernel.string=SKYNET Kernel 17 for miatoll by Saamitk/kernel.string=SKYNET Kernel 17S for miatoll by Saamitk/' \
        -e 's/# No ramdisk edits or module injection needed (BakaSU + SUSFS are built-in)./# No ramdisk edits or module injection needed (rootless 17S kernel)./' \
        "$dir/anykernel3/anykernel.sh"
    git -C "$dir" add anykernel3/anykernel.sh

    log "checking that zero KSU/SUSFS references remain in kernel source"
    if git -C "$dir" grep -nE 'CONFIG_KSU|susfs_' -- \
        arch/ block/ drivers/ fs/ include/ init/ kernel/ mm/ security/ Makefile Kconfig; then
        die "unexpected KSU/SUSFS references remained in kernel tree"
    fi

    log "running offline source & link verification on 17S tree"
    "$dir/scripts/verify-source.sh"
    python3 "$dir/scripts/check-links.py"
}

SOURCE_SHA="$(git -C "$REPO_ROOT" rev-parse --short=10 HEAD)"

COMMIT_MSG="$(cat <<EOF
SKYNET 17S: strip BakaSU and SUSFS v2.4.0 for rootless line (from ${SOURCE_SHA})

Keep all non-root SKYNET 17 fixes:
- Android 17 compatibility updates (CONFIG_TRACE_GPU_MEM=y,
  CONFIG_TMPFS_XATTR=y, LLVM/Clang Makefile defaults)
- Energy-aware CASS scheduler, schedutil, Adreno 618, workqueue, and SLUB/VM
  optimizations for battery backup and Circle to Search / Google Lens fluidity
- 5.10.357-Skynet-17S-Openela uname / /proc/version spoofing
- Android 17 zygote_next / Chrome CAP_CHECKPOINT_RESTORE (40),
  cgroup v2 freezer race fixes, and rtmutex proxy-lock waiter fixes

Remove all root components (BakaSU KernelSU submodule, drivers/kernelsu,
Non-GKI SUSFS v2.4.0 core and inline VFS/proc/SELinux hooks, CONFIG_KSU*).
EOF
)"

ensure_git_identity() {
    local dir="$1"
    if ! git -C "$dir" config user.name >/dev/null 2>&1; then
        git -C "$dir" config user.name "$(git -C "$dir" log -1 --format='%an')"
    fi
    if ! git -C "$dir" config user.email >/dev/null 2>&1; then
        git -C "$dir" config user.email "$(git -C "$dir" log -1 --format='%ae')"
    fi
}

if ((IN_PLACE)); then
    ensure_git_identity "$REPO_ROOT"
    strip_root_in_dir "$REPO_ROOT"
    if git -C "$REPO_ROOT" diff --cached --quiet; then
        log "tree is already rootless; nothing to commit"
    else
        git -C "$REPO_ROOT" commit -s -m "$COMMIT_MSG"
    fi
    if [[ -n "$PUSH_REMOTE" ]]; then
        log "pushing HEAD to ${PUSH_REMOTE}/refs/heads/${BRANCH_NAME}"
        git -C "$REPO_ROOT" push --force "$PUSH_REMOTE" "HEAD:refs/heads/${BRANCH_NAME}"
    fi
    log "in-place 17S preparation complete ($(git -C "$REPO_ROOT" rev-parse --short=10 HEAD))"
    exit 0
fi

WT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/skynet-17s.XXXXXX")"
cleanup() {
    git -C "$REPO_ROOT" worktree remove --force "$WT_DIR" >/dev/null 2>&1 || rm -rf "$WT_DIR"
}
trap cleanup EXIT

log "creating temporary worktree at $WT_DIR from HEAD (${SOURCE_SHA})"
git -C "$REPO_ROOT" worktree add --detach "$WT_DIR" HEAD >/dev/null

ensure_git_identity "$WT_DIR"
strip_root_in_dir "$WT_DIR"
git -C "$WT_DIR" commit -s -m "$COMMIT_MSG"
NEW_SHA="$(git -C "$WT_DIR" rev-parse HEAD)"

git -C "$REPO_ROOT" update-ref "refs/heads/${BRANCH_NAME}" "$NEW_SHA"
log "updated local branch '${BRANCH_NAME}' -> ${NEW_SHA:0:10} (current branch untouched)"

if [[ -n "$PUSH_REMOTE" ]]; then
    log "pushing '${BRANCH_NAME}' to '${PUSH_REMOTE}'"
    git -C "$REPO_ROOT" push -u --force "$PUSH_REMOTE" "refs/heads/${BRANCH_NAME}:refs/heads/${BRANCH_NAME}"
fi
