#!/usr/bin/env python3
"""Kept for old instructions: installs the Android + iOS templates. See install_export_templates.py."""
import os, sys

script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "install_export_templates.py")
extra = ["--version", sys.argv[1]] if len(sys.argv) > 1 else []
os.execv(sys.executable, [sys.executable, script, "android", "ios", *extra])
