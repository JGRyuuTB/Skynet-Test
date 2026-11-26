#!/usr/bin/env python3
"""Idempotently hook skynet_uname into kernel/sys.c and kernel/Makefile."""
import re, sys, pathlib

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
sys_c = root / "kernel/sys.c"
mk = root / "kernel/Makefile"

if not (root / "kernel/skynet_uname.c").exists():
    sys.exit("kernel/skynet_uname.c missing")

src = sys_c.read_text()
if "skynet_uname_spoof" not in src:
    m = re.search(r"SYSCALL_DEFINE1\(\s*newuname\b.*?\n\{.*?up_read\(&uts_sem\);\n", src, re.S)
    if not m:
        sys.exit("newuname() not found in kernel/sys.c")
    block = m.group(0)
    src = src.replace(block, block + "\tskynet_uname_spoof(&tmp);\n", 1)
    decl = "struct new_utsname;\nextern void skynet_uname_spoof(struct new_utsname *u);\n\n"
    idx = src.index("SYSCALL_DEFINE1(newuname")
    src = src[:idx] + decl + src[idx:]
    sys_c.write_text(src)
    print("patched kernel/sys.c")

m = mk.read_text()
if "skynet_uname.o" not in m:
    mk.write_text(m.rstrip("\n") + "\nobj-y += skynet_uname.o\n")
    print("patched kernel/Makefile")
print("uname spoof hooks OK")
