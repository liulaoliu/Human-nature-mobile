@echo off
REM ============================================================
REM build_release.bat - 构建 release APK（只打 arm64，带进度报告）
REM
REM 用法：
REM   scripts\build_release.bat            构建（默认 arm64，发版给自己手机）
REM   scripts\build_release.bat --no-watch 不显示进度（纯构建）
REM   scripts\build_release.bat -PtargetAbi=x64   给 x86_64 模拟器打（冒烟用）
REM
REM 打包规格见 docs\BUILD.md。要点：
REM   * 只打 arm64-v8a（abiFilters + disable-abi-filtering，缺一不可）
REM   * --obfuscate --split-debug-info，符号表在 build\symbols\，别删
REM   * 构建前后把 assets\data\ 的 34.8MB 开发样本挪走 / 挪回
REM
REM 产物：build\app\outputs\flutter-apk\app-release.apk
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
set "STAMP=%TEMP%\dlaoshi_build.stamp"
del "%LOG%" 2>nul

REM 起始时间戳：用来判断 APK 是不是这一轮产出的。
REM   旧写法只看 `if exist "%APK%"`，上一轮的包还在时会立刻误报 DONE，
REM   还会报一个中间态字节数（2026-11-15 报过 56,901,632 而实际 144,790,699）。
REM   存 ISO 字符串：存 Ticks 数字的话 `[DateTime]::Parse(...)` 认不出，
REM   会抛「该字符串未被识别为有效的 DateTime」，于是永远判 N。
powershell -NoProfile -Command "Set-Content -Path '%STAMP%' -Value ([DateTime]::Now.ToString('o'))"
REM 完成判定在子 powershell 里读这两个环境变量（见下面 :loop）
set "APK_FULL=%CD%\%APK%"

echo ==^> 构建 release APK（日志：%LOG%）
echo ==^> 产物：%APK%
echo.

REM 后台启动构建，PID 存下来
powershell -NoProfile -Command "$p = Start-Process -NoNewWindow -FilePath 'cmd.exe' -ArgumentList '/d','/c','flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/symbols -PtargetAbi=arm64 2>&1' -RedirectStandardOutput '%LOG%' -PassThru; Set-Content -Path '%LOG%.pid' -Value $p.Id"
set /p CPID=<"%LOG%.pid"

set /a TICKS=0
:loop
ping -n 16 127.0.0.1 >nul 2>nul
set /a TICKS+=1

REM 完成判定：APK 存在，且 mtime 晚于本轮开始时间。
REM   Gradle 输出被 flutter 吞掉，只能靠产物判断。
REM   注意别在 powershell 里手写引号拼路径 —— 用环境变量 $env:APK_FULL / $env:STAMP
REM   （手写 ''%APK%'' 这种嵌套引号 PowerShell 会解析成空串，永远判出 N，
REM    2026-11-15 就因此误报过 FAILED）。
set "FRESH=N"
if exist "%APK%" (
    for /f %%t in ('powershell -NoProfile -Command "if ((Get-Item $env:APK_FULL).LastWriteTime -gt [DateTime]::Parse((Get-Content $env:STAMP -Raw).Trim())) { 'Y' } else { 'N' }"') do set "FRESH=%%t"
)
if "%FRESH%"=="Y" (
    echo.
    echo ==== DONE ====
    for %%f in ("%APK%") do echo APK: %%~ff  ^(%%~zf bytes^)
    goto finished
)

REM 进程没了但 APK 没更新 = 失败，打日志尾巴
tasklist /fi "PID eq %CPID%" 2>nul | findstr /c:"%CPID%" >nul 2>nul
if errorlevel 1 (
    echo.
    echo ==== FAILED（进程已退出，但没有新产物）====
    echo ---- 日志尾部 ----
    powershell -NoProfile -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; Get-Content -Tail 40 -Encoding UTF8 '%LOG%' | Where-Object { $_ -ne '' }" 2>nul
    del "%LOG%.pid" 2>nul
    del "%STAMP%" 2>nul
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
del "%STAMP%" 2>nul
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
