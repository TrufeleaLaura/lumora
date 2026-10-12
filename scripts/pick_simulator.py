"""Reads `xcrun simctl list devices available -j` from stdin and prints the UDID of the best
iPhone simulator: newest iOS runtime, preferring a non-Max "Pro" model."""
import json
import re
import sys

data = json.load(sys.stdin)
best = None
for runtime, devices in data.get("devices", {}).items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in devices:
        name = device.get("name", "")
        if not device.get("isAvailable", False) or not name.startswith("iPhone"):
            continue
        score = (version, "Pro" in name and "Max" not in name, name)
        if best is None or score > best[0]:
            best = (score, device["udid"])

if best is None:
    sys.exit("No available iPhone simulator found")
print(best[1])
