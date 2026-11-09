#!/usr/bin/env python3
import sys
import re

has_error = False
for line in sys.stdin:
    clean = line.rstrip()
    print(clean)
    m = re.match(r'\s*(error|warning)\s*•\s*(.*?)\s*•\s*(.*?):(\d+):(\d+)', clean)
    if m:
        level, msg, file, lno, col = m.groups()
        print(f"::{level} file={file},line={lno},col={col}::{msg}", flush=True)
        if level == "error":
            has_error = True

if has_error:
    sys.exit(1)
