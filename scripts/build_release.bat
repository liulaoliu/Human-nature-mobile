@echo off
REM ============================================================
REM build_release.bat - 打 release APK（只出 arm64-v8a）
REM
REM 为什么只锁 arm64：本 App 是自用工具，不做分渠道分发；单 ABI 体积最小、
REM 启动最快，也免掉 split-apk 的安装选择。需要在 x86 模拟器上跑请用
REM `flutter build apk --debug`（模拟器调试不需要 release 包）。
REM
REM --obfuscate + --split-debug-info：release 包剥符号，崩溃栈靠 build/symbols
REM 还原（保留该目录，别删）。
REM
REM 用法：scripts\build_release.bat [额外参数]
REM ============================================================
setlocal

set "OUT=build\app\outputs\flutter-apk\app-release.apk"

call flutter build apk --release ^
  --target-platform android-arm64 ^
  --obfuscate ^
  --split-debug-info=build\symbols %*

if errorlevel 1 (
  echo.
  echo [build] 失败，见上面的 Flutter 输出
  exit /b 1
)

echo.
echo [build] 完成: %OUT%
echo [build] 符号表: build\symbols（崩溃栈还原要用，别删）
