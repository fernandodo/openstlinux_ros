#!/usr/bin/env bash

# 禁用屏保/DPMS
xset s off
xset s noblank
xset -dpms

# 定义清理函数：恢复默认
cleanup() {
  echo "Restoring X settings..."
  xset s on
  xset +dpms
}
trap cleanup EXIT

# 启动 systemd-inhibit，保持唤醒直到 Ctrl+C
systemd-inhibit --what=idle:sleep:handle-lid-switch --why="Yocto build" \
  bash -c 'echo "Keep awake: running, press Ctrl+C to stop."; sleep infinity'
