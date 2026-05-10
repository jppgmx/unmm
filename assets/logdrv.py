"""
    logdrv.py
    =====================

    Driver para a lib/logging.sh na função exec_logged2.
"""

import shlex
import subprocess as sp
import sys

def main(args):
    if len(args) == 0:
        return 0

    try:
        with sp.Popen(
            args,
            stdout=sys.stdout,
            stderr=sys.stderr,
            stdin=sys.stdin
        ) as result:
            result.wait()
            return result.returncode
    except Exception as e:
        print(f"{type(e).__name__}: {e}", file=sys.stderr)
        return 255

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
