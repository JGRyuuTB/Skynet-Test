#!/system/bin/sh
# Usage (root): sh skynet-uname.sh [list | off | <n|name> | custom <rel> | version <str>]
N=/proc/skynet_uname
[ -e "$N" ] || { echo "Kernel without SKYNET uname spoof"; exit 1; }
case "$1" in
  ""|list) cat "$N";;
  *) echo "$*" > "$N" && echo "uname -r: $(uname -r)";;
esac
