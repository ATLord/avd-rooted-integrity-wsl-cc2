#!/usr/bin/env python3
"""Fail a build if the Wild/SUSFS integration lost a lifecycle call site."""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
# A declaration is not evidence of a connected hook. Require call statements.
required = {
    'fs/read_write.c': r'^\s*ksu_handle_sys_read\(fd\);',
    'fs/stat.c': r'^\s*ksu_handle_vfs_fstat\(fd, &stat->size\);',
    'fs/exec.c': r'^\s*ksu_handle_execveat\(&fd, &filename, &argv, &envp, &flags\);',
}
for filename, pattern in required.items():
    if not re.search(pattern, (root / filename).read_text(), re.M):
        sys.exit(f'Missing KernelSU boot hook in {filename}; inspect SUSFS patch rejects. Refusing build.')

# The pinned SUSFS caller passes only fd. Wild retains two unused parameters;
# make the definition agree with the caller instead of relying on ABI luck.
path = root / 'KernelSU-Next/kernel/runtime/ksud_integration.c'
source = path.read_text()
old = 'void ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr, size_t *count_ptr)'
new = 'void ksu_handle_sys_read(unsigned int fd)'
if old in source:
    source = source.replace(old, new)
    path.write_text(source)
elif new not in source:
    sys.exit('Unknown KernelSU read-hook signature; refusing build.')
print('KernelSU read/stat/exec lifecycle call sites verified.')
