#!/usr/bin/env python3
"""Apply the x86 compatibility changes after the upstream Wild patch."""
from pathlib import Path
import sys

root = Path(sys.argv[1]) / 'KernelSU-Next/kernel'

def replace(relative, before, after, count=1):
    path = root / relative
    text = path.read_text()
    if text.count(after) == count:
        return
    if text.count(before) != count:
        raise SystemExit(f'Expected {count} matching insertion point(s): {relative}')
    path.write_text(text.replace(before, after))

replace('runtime/ksud.h', '#include <asm/syscall.h>',
        '#include <linux/compat.h>\n#include <asm/syscall.h>')
replace('extras.c', '#include <linux/security.h>',
        '#include <linux/mm.h>\n#include <linux/security.h>')
replace('feature/sucompat.c', 'strncpy_from_user(path, *filename_user, sizeof(path));',
        'if (strncpy_from_user(path, *filename_user, sizeof(path)) < 0)\n\t\treturn 0;', count=2)
replace('policy/app_profile.c', 'if (likely(test_thread_flag(TIF_SECCOMP)))',
        '#ifdef CONFIG_GENERIC_ENTRY\n\tif (likely(test_syscall_work(SECCOMP)))\n#else\n\tif (likely(test_thread_flag(TIF_SECCOMP)))\n#endif')
replace('feature/selinux_hide.c', '#include <linux/cred.h>',
        '#include <linux/kallsyms.h>\n#include <linux/cred.h>')
for name in ('security_dump_masked_av', 'context_struct_compute_av'):
    replace('feature/selinux_hide.c', name + '_fn = kallsyms_lookup_name(',
            name + '_fn = (typeof(' + name + '_fn))kallsyms_lookup_name(')
