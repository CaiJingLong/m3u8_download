#!/usr/bin/env python3

import os
import re


def read_version():
    with open("pubspec.yaml", "r") as f:
        lines = f.readlines()
        for line in lines:
            if "version" in line:
                return line.split(":")[1].strip()


version = read_version()

ver = "v" + version

regex = r"v\d+\.\d+\.\d+"

if not re.match(regex, ver):
    print('Invalid version format. Use "vX.X.X"')

cmd = f"gh release create {ver} --generate-notes "

print(f"Creating release {ver}...")
os.system(cmd)

print("Done!")
