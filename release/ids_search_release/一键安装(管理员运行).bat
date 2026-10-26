@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul
title Rime IDS C++ 原生部件检字套件 - 一键安装程序

:: 1. 管理员权限检查与自动提权
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [提示] 正在请求管理员权限以替换小狼毫核心动态库...
    powershell -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo ==============================================================================
echo   Rime IDS Search C++ 原生增强检字套件 (v3.0 IDS3 极速单文件版)
echo   全自动极速安装与部署程序
echo ==============================================================================
echo.

:: 2. 探寻 Weasel 安装目录
set "WEASEL_DIR="
for /f "tokens=2* " %%a in ('reg query "HKLM\SOFTWARE\Rime\Weasel" /v "WeaselRoot" 2^>nul') do set "WEASEL_DIR=%%b"
if not defined WEASEL_DIR (
    for /f "tokens=2* " %%a in ('reg query "HKCU\Software\Rime\Weasel" /v "WeaselRoot" 2^>nul') do set "WEASEL_DIR=%%b"
)
if not defined WEASEL_DIR (
    for /d %%D in ("C:\Program Files\Rime\weasel-*") do (
        if exist "%%D\WeaselServer.exe" set "WEASEL_DIR=%%D"
    )
)
if not defined WEASEL_DIR (
    if exist "C:\Program Files\Rime\weasel" set "WEASEL_DIR=C:\Program Files\Rime\weasel"
)

if not defined WEASEL_DIR (
    echo [错误] 未能定位到小狼毫程序目录，请确认已安装 64 位小狼毫。
    pause
    exit /b 1
)

set "RIME_USER_DIR=%APPDATA%\Rime"
echo [OK] 程序目录: "!WEASEL_DIR!"
echo [OK] 用户目录: "!RIME_USER_DIR!"
echo.

:: 3. 停止运行中服务
echo [1/4] 正在安全停止小狼毫服务进程...
taskkill /F /IM WeaselServer.exe >nul 2>&1
taskkill /F /IM WeaselDeployer.exe >nul 2>&1
timeout /t 1 /nobreak >nul

:: 4. 替换 rime.dll
echo [2/4] 正在部署 C++ 原生增强核心 (rime.dll)...
if not exist "!WEASEL_DIR!\rime.dll.bak" (
    if exist "!WEASEL_DIR!\rime.dll" (
        copy /Y "!WEASEL_DIR!\rime.dll" "!WEASEL_DIR!\rime.dll.bak" >nul
        echo       已自动备份原版至 rime.dll.bak
    )
)
copy /Y "1.【小狼毫程序目录】\rime.dll" "!WEASEL_DIR!\rime.dll" >nul
if %errorlevel% neq 0 (
    echo [错误] 替换 rime.dll 失败！请检查是否有安全软件拦截。
    pause
    exit /b 1
)
echo       核心动态库替换成功！

:: 5. 复制用户目录数据与独立方案配置
echo [3/4] 正在部署 10.4万字 紧凑单文件数据 (ids_data.bin) 与独立方案配置...
if not exist "!RIME_USER_DIR!\build" mkdir "!RIME_USER_DIR!\build"

:: 清理旧版双文件
if exist "!RIME_USER_DIR!\build\ids_index.bin" del /F /Q "!RIME_USER_DIR!\build\ids_index.bin" >nul 2>&1
if exist "!RIME_USER_DIR!\build\ids_meta.bin" del /F /Q "!RIME_USER_DIR!\build\ids_meta.bin" >nul 2>&1
if exist "!RIME_USER_DIR!\ids_index.bin" del /F /Q "!RIME_USER_DIR!\ids_index.bin" >nul 2>&1
if exist "!RIME_USER_DIR!\ids_meta.bin" del /F /Q "!RIME_USER_DIR!\ids_meta.bin" >nul 2>&1

:: 部署 IDS3 单文件
copy /Y "2.【用户配置目录】\ids_data.bin" "!RIME_USER_DIR!\build\ids_data.bin" >nul
copy /Y "2.【用户配置目录】\ids_data.bin" "!RIME_USER_DIR!\ids_data.bin" >nul
copy /Y "2.【用户配置目录】\ids_search.schema.yaml" "!RIME_USER_DIR!\ids_search.schema.yaml" >nul

if not exist "!RIME_USER_DIR!\ids_custom.txt" (
    copy /Y "2.【用户配置目录】\ids_custom.txt" "!RIME_USER_DIR!\ids_custom.txt" >nul
)

if not exist "!RIME_USER_DIR!\default.custom.yaml" (
    copy /Y "2.【用户配置目录】\default.custom.yaml" "!RIME_USER_DIR!\default.custom.yaml" >nul
)
echo       独立方案与索引数据部署成功！

:: 6. 重新部署与启动
echo [4/4] 正在执行重新部署并重启服务...
set "DEPLOYER=!WEASEL_DIR!\WeaselDeployer.exe"
if exist "!DEPLOYER!" (
    "!DEPLOYER!" /deploy
)
start "" "!WEASEL_DIR!\WeaselServer.exe"
timeout /t 1 /nobreak >nul

echo.
echo ==============================================================================
echo   🎉 恭喜！Rime IDS C++ 原生部件检字方案已安装就绪！
echo   快捷键: Ctrl+Shift+Space 或 Ctrl+` 即可直接切换开启部件模糊检字！
echo   若使用万象拼音，请参考【可选：万象拼音挂接补丁】文件夹按需合入。
echo ==============================================================================
echo.
pause
