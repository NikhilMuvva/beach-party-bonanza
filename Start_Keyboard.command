#!/bin/bash
cd "$(dirname "$0")" || exit 1
python3 launch.py --keyboard "$@"
result=$?
if [ "$result" -ne 0 ]; then
  echo ""
  read -r -p "Press Enter to close..."
fi
exit "$result"
