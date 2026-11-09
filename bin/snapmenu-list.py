#!/usr/bin/python3
"""List screenshots as JSON lines, escaping all filename control characters.

A newline-delimited `find -printf %p` lets a filename containing a newline
forge a second history row. JSON encoding keeps each filesystem entry one
record, including names with tabs, newlines and quotes.
"""

import json
import os
import sys


def main():
    if len(sys.argv) != 2:
        return 2
    directory = os.path.abspath(sys.argv[1])
    try:
        with os.scandir(directory) as entries:
            for entry in entries:
                if not entry.name.endswith(".png"):
                    continue
                try:
                    if not entry.is_file(follow_symlinks=False):
                        continue
                    stat = entry.stat(follow_symlinks=False)
                except OSError:
                    continue
                print(json.dumps({
                    "path": entry.path,
                    "size": stat.st_size,
                    "mtime": stat.st_mtime,
                }))
    except OSError:
        # An export folder that no longer exists is simply an empty history.
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
