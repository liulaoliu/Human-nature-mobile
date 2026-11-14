@echo off
REM ============================================================
REM build_release.bat - 构建 arm64-only release APK（带进度报告）
REM
REM 用法：
REM   scripts\build_release.bat            构建
REM   scripts\build_release.bat --no-watch 不显示进度（纯构建）
REM
REM 为什么需要这个脚本：
REM   1. flutter build 会把 Gradle 的输出全部缓存到结束才打印，
REM      终端看起来像卡死。这里改成边跑边报进度。
REM   2. 官方 services.gradle.org 下载 gradle 发行版在本机会卡住，
REM      已在 gradle-wrapper.properties 换成华为云镜像。
REM   3. integration_test 的动态版本依赖会撞上 storage.flutter-io.cn 的 403，
REM      已在 android/build.gradle.kts 加了 download.flutter.io 的 content 过滤。
REM
REM 产物：build\app\outputs\flutter-apk\app-release.apk
REM 符号：build\symbols\（--obfuscate 产生的映射，崩溃栈还原要用，别删）
REM ============================================================
setlocal enabledelayedexpansion
chcp 65001 >nul
cd /d "%~dp0\.."

REM ------------------------------------------------------------
REM 开发样本不进 release 包。
REM   pubspec 里的 assets/ 是全局的，assets/data/ 下那份 34.8MB 的
REM   完整备份 JSON 会被原样打进 APK。它只给「备份 → 导入内置样本」
REM   这个开发入口用，release 用不上，所以构建前先挪走、结束再挪回。
REM ------------------------------------------------------------
set "DEVDATA=assets\data\economist-backup-2026-11-10.json"
set "DEVDATA_TMP=%TEMP%\dlaoshi_devdata.json"
if exist "%DEVDATA%" (
    move /y "%DEVDATA%" "%DEVDATA_TMP%" >nul
    echo ==^> 已把开发样本挪出 assets（release 包不带它）
)

set "LOG=%TEMP%\dlaoshi_build.log"
set "APK=build\app\outputs\flutter-apk\app-release.apk"
del "%LOG%" 2>nul
del "%APK%" 2>nul

echo ==^> 构建 arm64 release APK（日志：%LOG%）
echo ==^> 产物：%APK%
echo.

REM 后台启动构建，PID 存下来
powershell -NoProfile -Command "$p = Start-Process -NoNewWindow -FilePath 'cmd.exe' -ArgumentList '/d','/c','flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/symbols 2>&1' -RedirectStandardOutput '%LOG%' -PassThru; Set-Content -Path '%LOG%.pid' -Value $p.Id"
set /p CPID=<"%LOG%.pid"

set /a TICKS=0
:loop
ping -n 16 127.0.0.1 >nul 2>nul
set /a TICKS+=1

REM APK 出现就是真的完成了（Gradle 输出被 flutter 吞掉，只能看产物）
if exist "%APK%" (
    echo.
    echo ==== DONE ====
    for %%f in ("%APK%") do echo APK: %%~ff  ^(%%~zf bytes^)
    goto finished
)

REM 进程没了但 APK 没出现 = 失败，打日志尾巴
tasklist /fi "PID eq %CPID%" 2>nul | findstr /c:"%CPID%" >nul 2>nul
if errorlevel 1 (
    echo.
    echo ==== FAILED（进程已退出，但没有产物）====
    echo ---- 日志尾部 ----
    powershell -NoProfile -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; Get-Content -Tail 40 -Encoding UTF8 '%LOG%' | Where-Object { $_ -ne '' }" 2>nul
    del "%LOG%.pid" 2>nul
    if exist "%DEVDATA_TMP%" (
        move /y "%DEVDATA_TMP%" "%DEVDATA%" >nul
        if errorlevel 1 echo !! 开发样本没能挪回 assets，手动从 %DEVDATA_TMP% 挪回
    )
    endlocal
    exit /b 1
)

REM 还没完：报一行进度（跑了多久 + 日志最后一行）
for /f "tokens=1-4 delims=:." %%a in ("%time%") do set "NOW=%%a:%%b"
echo [%NOW%] 仍在构建... 第 %TICKS% 次检查
goto loop

:finished
del "%LOG%.pid" 2>nul
echo.
echo ---- 日志尾部 ----
powershell -NoProfile -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; Get-Content -Tail 12 -Encoding UTF8 '%LOG%' | Where-Object { $_ -ne '' }" 2>nul
if exist "%DEVDATA_TMP%" (
    move /y "%DEVDATA_TMP%" "%DEVDATA%"
    if errorlevel 1 (
        echo !! 开发样本没能挪回 assets，手动从 %DEVDATA_TMP% 挪回
    ) else (
        echo ==^> 已把开发样本挪回 assets
    )
)
endlocal
exit /b 0
