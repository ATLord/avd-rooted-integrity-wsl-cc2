#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$root" <<'PY'
from pathlib import Path
import subprocess
import sys
import tempfile

checker = Path(sys.argv[1]) / 'kernel-build/scripts/check-boot-hooks.py'
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    sources = {
        'fs/read_write.c': 'ksu_handle_sys_read(fd);',
        'fs/stat.c': 'ksu_handle_vfs_fstat(fd, &stat->size);',
        'fs/exec.c': 'ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);',
        'KernelSU-Next/kernel/runtime/ksud_integration.c':
            'void ksu_handle_sys_read(unsigned int fd, char __user **buf_ptr, size_t *count_ptr) {}',
    }
    for name, source in sources.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source)
    def run():
        return subprocess.run([sys.executable, str(checker), str(root)], capture_output=True)
    assert run().returncode == 0
    assert run().returncode == 0, 'not idempotent'
    assert 'void ksu_handle_sys_read(unsigned int fd)' in (root / 'KernelSU-Next/kernel/runtime/ksud_integration.c').read_text()
    for name in ('fs/read_write.c', 'fs/stat.c', 'fs/exec.c'):
        (root / name).write_text('/* missing hook */')
        assert run().returncode != 0, f'accepted missing call in {name}'
        (root / name).write_text(sources[name])
print('Kernel lifecycle audit rejects missing calls and is idempotent.')
PY
