#!/bin/sh
# watch_build.sh - 盯 APK 构建的真实进度
#
# 用法：
#   sh scripts/watch_build.sh            # 每 15 秒报一次
#   sh scripts/watch_build.sh 30         # 每 30 秒
#
# 为什么需要它：
#   flutter build 会把 Gradle 的 stdout 全缓存到结束才打印，日志长时间不动
#   不代表卡死。真正的进度信号有三个，本脚本一起看：
#
#   1. .tmp 里下载中的文件还在长  -> 在拉依赖（KB/s 就是真实速度）
#   2. build/ 目录出现新文件       -> 进入编译阶段了
#   3. APK 出现                    -> 真的完成了
#
# 注意：modules-2 目录大小不是好信号 —— 下载完成的包才会从 .tmp 移进去，
# 下载中途它一直不变，容易被误判成「卡死」。

set -u
INTERVAL=${1:-15}
APK="build/app/outputs/flutter-apk/app-release.apk"
TMP="/i/.cache/gradle/.tmp"

cd "$(dirname "$0")/.." || exit 1

prev_dl=0
prev_build=0
tick=0

echo "盯构建进度（每 ${INTERVAL}s）：APK / 下载中 / 编译产物"
echo ""

while :; do
  tick=$((tick + 1))
  now=$(date +%H:%M:%S)

  if [ -f "$APK" ]; then
    size=$(stat -c %s "$APK" 2>/dev/null || echo 0)
    echo ""
    echo "==== DONE $now ===="
    echo "APK: $APK  ($((size / 1024 / 1024)) MB)"
    exit 0
  fi

  # 正在下载的文件大小（取 .tmp 里最大的 gradle_download*）
  dl=$(ls -l "$TMP"/gradle_download* 2>/dev/null | awk '{if ($5>m) m=$5} END{print m+0}')
  dl_mb=$((dl / 1024 / 1024))
  dl_kb=$((dl / 1024))

  # build/ 目录里的文件数（进入编译阶段后才会涨）
  bcount=$(find build -type f 2>/dev/null | wc -l | tr -d ' ')

  if [ "$tick" -gt 1 ]; then
    ddl=$((dl - prev_dl))
    db=$((bcount - prev_build))
    rate=$((ddl / INTERVAL / 1024))

    if [ "$ddl" -gt 0 ]; then
      echo "[$now] 下载中 ${dl_mb}MB (+$((ddl / 1024))KB) 约 ${rate}KB/s | build 产物 ${bcount} (+${db})"
    elif [ "$db" -gt 0 ]; then
      echo "[$now] 编译中 | build 产物 ${bcount} (+${db}) | 下载 ${dl_mb}MB 已停"
    else
      echo "[$now] 没动静 | 下载 ${dl_mb}MB 未变 | build 产物 ${bcount} 未变"
      echo "          ⚠ 连续两轮不动才可能是真卡住"
    fi
  fi

  prev_dl=$dl
  prev_build=$bcount
  sleep "$INTERVAL"
done
