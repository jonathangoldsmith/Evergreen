#!/bin/sh
# Sends a mock push to the booted simulator, the way the harness would once it
# has a push backend. Usage: app/MockPushes/send.sh comeback-booked
# (or drag any .apns file in this folder onto the simulator window).
set -e
dir=$(cd "$(dirname "$0")" && pwd)
name=${1:-comeback-booked}
if [ ! -f "$dir/$name.apns" ]; then
  echo "No $name.apns. Choose one of:"; ls "$dir"/*.apns | xargs -n1 basename | sed 's/\.apns$//'
  exit 1
fi
xcrun simctl push booted com.trackerplusplus.app "$dir/$name.apns"
