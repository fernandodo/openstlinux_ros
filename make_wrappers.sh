#!/usr/bin/env bash
set -e
ROOT=/home/felux/Projects/st/openstlinux
GEN="$ROOT/layers/meta-ros/meta-ros2-jazzy/generated-recipes/fuse"
MY="$ROOT/meta-myprod/recipes-support/fuse"

mkdir -p "$MY"

for f in "$GEN"/*.bb; do
  base=$(basename "$f")
  cat > "$MY/$base" <<EOF
# Local wrapper to align with generated-recipes version
require ../../../layers/meta-ros/meta-ros2-jazzy/generated-recipes/fuse/$base
EOF
  echo "Created wrapper: $MY/$base"
done
