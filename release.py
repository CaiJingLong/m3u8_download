#!/usr/bin/env python3

import re
import sys

if len(sys.argv) < 2:
    print("Usage: release.py <version>")
    sys.exit(1)

ver = sys.argv[1]

regex = r"v\d+\.\d+\.\d+"

if not re.match(regex, ver):
    print('Invalid version format. Use "vX.X.X"')

cmd = f"gh release create {ver} --generate-notes "
