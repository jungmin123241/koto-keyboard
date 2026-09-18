"""Select only an available iPhone whose runtime supports our iOS 18 target."""
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    runtimes = json.load(source)["devices"]
for runtime, devices in sorted(runtimes.items(), reverse=True):
    match = re.search(r"iOS-(\d+)-", runtime)
    if not match or int(match.group(1)) < 18:
        continue
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            print("SIMULATOR=platform=iOS Simulator,id=" + device["udid"])
            sys.exit(0)
raise SystemExit("Install an iOS 18 or newer iPhone simulator runtime first.")
