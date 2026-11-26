# Changelog

All notable changes to the SKYNET kernel project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); see
[`docs/BRANCHING.md`](docs/BRANCHING.md) for tags and releases.

## [Unreleased] — `17` line

### Changed

- Updated `init/version.c` `uname` / `/proc/version` release spoofing to distinguish rooted vs
  rootless builds directly in Android Settings ("About phone"): `5.10.357-Skynet-17R-Openela` when
  `CONFIG_KSU` is enabled (`17R`) and `5.10.357-Skynet-17S-Openela` when `CONFIG_KSU` is disabled
  (`17S`).
- Optimized SM6250 battery backup and foreground interactive responsiveness (including Android
  **Circle to Search / Google Lens** launch & Kawase blur smoothness) without lowering peak clocks:
  - **`kernel/sched/cass.c`**: fixed 64-bit unsigned subtraction wrap in `cass_cmp()`, inverted
    idle `exit_lat` comparison so shallow-idle CPUs wake first while deep-sleeping CPUs remain in
    power collapse, added `schedtune` margin/`prefer_idle` awareness + `WF_SYNC`/`SD_BALANCE_EXEC`
    Gold-core placement for `top-app` bursts, and kept unboosted light tasks packed on the
    efficient Kryo 465 Silver cluster unless load exceeds Silver capacity.
  - **`kernel/sched/cpufreq_schedutil.c`**: tuned default OSM rate limits to `500 us` up / `10 ms`
    down for fast interactive ramp-up without sub-frame clock sawtoothing.
  - **`drivers/devfreq/governor_msm_adreno_tz.c` & `sdmmagpie-gpu.dtsi`**: shortened Adreno 618
    GMU idle timeout from `64 ms` to `48 ms` for faster rail slumber after rendering stops, and
    added a 2-step ramp when low-power states hit `>=88%` shader saturation (e.g. full-screen
    Circle to Search Kawase blur + shimmer).
  - **`miatoll_defconfig`**: enabled `CONFIG_WQ_POWER_EFFICIENT_DEFAULT=y`,
    `CONFIG_PM_WAKELOCKS_GC=y`, and `CONFIG_SLUB_CPU_PARTIAL=y`, balanced page-cache protection
    (`CONFIG_CLEAN_LOW_KBYTES=196608`, `CONFIG_CLEAN_MIN_KBYTES=98304`) to reduce background app
    ZRAM swap-in thrashing on Google App wake-up, and disabled `SCHEDSTATS`, `MMC_PERF_PROFILING`,
    `SPMI_SIMULATOR`, `QCOM_DCC_V2`, and `ESOC_MDM_DBG_ENG` runtime overhead.
- Reverted `aw8624_haptic`, `drv2624_haptic`, and `cust-atoll-idp.dtsi` vibration tuning back to
  stock Miatoll values (`9bc0d34f4` reverted) after hardware testing showed the boosted LRA gains
  were too harsh.

### Added

- Added rootless **`17S`** branch/build tooling (`scripts/create-17s-branch.sh`,
  `.github/workflows/create-17s-branch.yml`, `scripts/build.sh --no-ksu`, and `no_ksu` input in
  `.github/workflows/build-kernel.yml`) to generate a pure non-root `17S` tree and flashable
  `skynet-17S` AnyKernel3 ZIPs with all Android 17, `uname`, and `zygote_next` /
  `CAP_CHECKPOINT_RESTORE` / cgroup freezer / `rtmutex` fixes while keeping BakaSU + SUSFS `v2.4.0`
  intact on the rooted `17` branch.
- Backported upstream `CAP_CHECKPOINT_RESTORE` (`40`) capability support (`CAP_LAST_CAP = 40`,
  `checkpoint_restore_ns_capable()`, SELinux `COMMON_CAP2_PERMS`, `pid_namespace`, `proc`
  `map_files`, `prctl_set_mm_map`, `tty_ioctl`), upstream cgroup v2 freezer race fixes
  (`cgroup_leave_frozen()` / `cgroup_exit()`), `rtmutex` proxy-lock waiter fixes, and SUSFS
  `zygote_next` `__lookup_mnt()` mount hiding — fixing Android 17 `zygote_next`
  (`com.android.chrome_zygote_native` / `NativeOnlySandboxedProcessService0`) panicking on
  `PR_CAPBSET_READ(40)` and stalling `ActivityManager`'s `ProcStart` queue when opening updated
  Google Chrome.
- Spoofed runtime kernel release (`init_uts_ns.name.release`, `/proc/version`, and
  `linux_banner` in `init/version.c`) to `5.10.357-Skynet-Openela` so Android Settings
  ("About phone") reports `5.10` / `5.10.357 Skynet Openela` while preserving `4.14.357-openela`
  (`LINUX_VERSION_CODE` and module `vermagic`) at compile time.
- Integrated [**BakaSU**](https://github.com/Baka-SU/BakaSU) (`KernelSU` git submodule,
  `drivers/kernelsu -> ../KernelSU/kernel`, `CONFIG_KSU=y`, `CONFIG_KSU_MULTI_MANAGER_SUPPORT=y`)
  with preinit runner UAPI header staging in `scripts/build.sh`.
- Integrated Non-GKI **SUSFS `v2.4.0`** (`CONFIG_KSU_SUSFS=y` and all `CONFIG_KSU_SUSFS_*=y`
  features, including `CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER=y`) and BakaSU `selinux_hide` direct
  SELinux hooks for Linux `4.14.357-openela`.
- Applied Android 17 compatibility updates (`158f74c6ae58f868bc14f54a91efa9d41d77e6b8`:
  LLVM/Clang `Makefile` defaults, `CONFIG_TRACE_GPU_MEM=y`, `CONFIG_TMPFS_XATTR=y`).
- Complete `4.14.357-openela` kernel source tree committed in this repository, **at the root**
  (72,779 files from pin `4afc6f0769f0f3b2b10d50d3fa02f0ba7c89a183`).
- `.github/workflows/flatten-source.yml`: one-shot, idempotent migration from the original
  `kernel/` subfolder to the root; re-imports the pin so the 57 dotfiles filtered by nested
  `.gitignore` rules are restored.
- `.github/workflows/build-kernel.yml`: Clang/LLD build → AnyKernel3 ZIP artifact → optional
  GitHub Release, with `kernel.release`, `.config` and toolchain provenance.
- `.github/workflows/publish-release.yml`: promote an existing build artifact into a
  checksum-verified, clearly marked UNTESTED pre-release without rebuilding the kernel.
- [`anykernel3/anykernel.sh`](anykernel3/anykernel.sh): device checks for `curtana`, `joyeuse`,
  `excalibur`, `gram` and `miatoll`; clean kernel, no ramdisk edits.
- `scripts/package-anykernel.sh` and `scripts/verify-source.sh`; `scripts/sync-source.sh` removed
  (the source is now in-tree).
- [`docs/RELEASING.md`](docs/RELEASING.md): ZIP contents, provenance and flashing checklist.
- Updated README, build/branching/upstream/license docs, CI, `.gitignore` (kernel rules plus
  SKYNET exceptions for `.github/`, `.elts/` and build outputs).

### Changed

- `CONFIG_LOCALVERSION` is now `-SKYNET` instead of the upstream pin's
  `-kinesis-omega-bpf`: `uname -r` reads `4.14.357-openela-SKYNET`. The defconfig is otherwise
  unchanged, and `CONFIG_LOCALVERSION_AUTO` stays disabled.
- Removed the two hardcoded `-kinesis-omega-bpf` strings upstream had in
  `scripts/setlocalversion` (which overrode `CONFIG_LOCALVERSION` entirely) and
  `init/version.c` (`init_uts_ns.name.release`, i.e. `uname -r`). Both now use the stock
  `CONFIG_LOCALVERSION` / `UTS_RELEASE` path. `build-kernel.yml` fails the build when
  `kernel.release` lacks `SKYNET`.
- `scripts/build.sh` auto-detects the source root (root or legacy `kernel/`) and defaults to
  `Image.gz-dtb`; `Validate` CI now lints only the SKYNET helper scripts.
- CI disables `CONFIG_LLVM_POLLY` by default (`--no-polly`): the pinned defconfig's Polly flags
  are rejected by prebuilt Clang toolchains without Polly.
- `docs/LICENSE-NOTICE.md`: with the GPL-2.0 tree in-tree, `COPYING` is the primary license for
  kernel code and GPL-3.0 `LICENSE` covers SKYNET-authored files.

### Notes

- The `17` line includes BakaSU (`KernelSU` submodule) + SUSFS `v2.4.0` built directly into the
  kernel image (no ramdisk patching required).
- No flashable ZIP is committed to the repository; builds are published via GitHub Actions.

### First CI build — `skynet-17-r1` (UNTESTED, **SUPERSEDED**)

- Actions run `41580476064`, source commit `4fbcf9e82`, proton-clang `master`, `--no-polly`.
- `skynet-17-20261103-2.zip` — SHA-256
  `31ae7b45cf993dfe4c7557c6368f02341d62fd6a0310926394fc414aabc9b778`.
- Contains `Image.gz-dtb` and `Image.gz` in an AnyKernel3 framework. **No boot test yet**.
- **Superseded by `skynet-17-r2`**: this ZIP still reports
  `4.14.357-openela-kinesis-omega-bpf` in `uname -r`. Do not flash it expecting SKYNET branding.

### Current build — `skynet-17-r2` (UNTESTED)

- Actions run `41601405560`, source commit `c5024cafb`, proton-clang `master`, `--no-polly`.
- CI verified `kernel.release = 4.14.357-openela-SKYNET` and
  `CONFIG_LOCALVERSION="-SKYNET"`; the build fails if that branding is missing.
- `skynet-17-20261103-4.zip` — SHA-256
  `ecfe2c0193ff426c866df1aae0f2d0e0f9e483ec3918eba71621b36ccd5db592`.
- Contains `Image.gz-dtb` and `Image.gz` in an AnyKernel3 framework. **No boot test yet**;
  back up stock `boot`/`dtbo` and verify device, block and slot settings before flashing.
- An intermediate build (`41598972597`, `skynet-17-20261103-3.zip`) was discarded without
  release: it still carried the Kinesis name and exposed the upstream hardcodes.

## [0.1.0] — scaffold

- Initial README, device matrix, build/sync tooling, docs, CI and issue/PR templates.

[Unreleased]: https://github.com/Saamitk/kernel_xiaomi_SM6250_SKYNET/commits/main
[0.1.0]: https://github.com/Saamitk/kernel_xiaomi_SM6250_SKYNET/pull/1
