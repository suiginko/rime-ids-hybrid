# 1. 管理员提权检查
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[提示] 正在请求管理员权限以替换小狼毫核心 DLL..." -ForegroundColor Cyan
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$CurrentDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $CurrentDir

Write-Host "==============================================================================" -ForegroundColor Green
Write-Host "  Rime IDS Search C++ 原生增强检字套件 (v3.0 IDS3 极速单文件版) - 部署程序" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Green

# 2. 定位 Weasel 目录
$WeaselDir = $null
$regPaths = @("HKLM:\SOFTWARE\Rime\Weasel", "HKCU:\Software\Rime\Weasel")
foreach ($r in $regPaths) {
    if (Test-Path $r) {
        $val = (Get-ItemProperty -Path $r -ErrorAction SilentlyContinue).WeaselRoot
        if ($val -and (Test-Path "$val\WeaselServer.exe")) {
            $WeaselDir = $val
            break
        }
    }
}

if (-not $WeaselDir) {
    $matches = Get-ChildItem "C:\Program Files\Rime\weasel-*" -Directory -ErrorAction SilentlyContinue
    foreach ($m in $matches) {
        if (Test-Path "$($m.FullName)\WeaselServer.exe") {
            $WeaselDir = $m.FullName
            break
        }
    }
}

if (-not $WeaselDir -and (Test-Path "C:\Program Files\Rime\weasel\WeaselServer.exe")) {
    $WeaselDir = "C:\Program Files\Rime\weasel"
}

if (-not $WeaselDir) {
    Write-Error "[错误] 未能定位到小狼毫程序目录，请确认已安装 64 位小狼毫输入法。"
    Pause
    exit 1
}

$RimeUserDir = "$env:APPDATA\Rime"
Write-Host "[OK] 程序目录: $WeaselDir" -ForegroundColor Gray
Write-Host "[OK] 用户目录: $RimeUserDir" -ForegroundColor Gray

# 3. 停止服务
Write-Host "[1/4] 正在停止小狼毫服务..." -ForegroundColor Cyan
Stop-Process -Name WeaselServer -Force -ErrorAction SilentlyContinue
Stop-Process -Name WeaselDeployer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# 4. 替换 rime.dll
Write-Host "[2/4] 正在部署 C++ 原生增强核心 (rime.dll)..." -ForegroundColor Cyan
if (-not (Test-Path "$WeaselDir\rime.dll.bak") -and (Test-Path "$WeaselDir\rime.dll")) {
    Copy-Item "$WeaselDir\rime.dll" "$WeaselDir\rime.dll.bak" -Force
    Write-Host "      已自动备份原版至 rime.dll.bak" -ForegroundColor Gray
}
Copy-Item "1.【小狼毫程序目录】\rime.dll" "$WeaselDir\rime.dll" -Force

# 5. 复制用户目录独立方案与数据
Write-Host "[3/4] 正在部署 10.4万字 紧凑单文件数据 (ids_data.bin) 与独立方案配置..." -ForegroundColor Cyan
$BuildDir = "$RimeUserDir\build"
if (-not (Test-Path $BuildDir)) { New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null }

# 清理旧版双文件
Remove-Item "$BuildDir\ids_index.bin" -Force -ErrorAction SilentlyContinue
Remove-Item "$BuildDir\ids_meta.bin" -Force -ErrorAction SilentlyContinue
Remove-Item "$RimeUserDir\ids_index.bin" -Force -ErrorAction SilentlyContinue
Remove-Item "$RimeUserDir\ids_meta.bin" -Force -ErrorAction SilentlyContinue

# 部署 IDS3 单文件
Copy-Item "2.【用户配置目录】\ids_data.bin" "$BuildDir\ids_data.bin" -Force
Copy-Item "2.【用户配置目录】\ids_data.bin" "$RimeUserDir\ids_data.bin" -Force
Copy-Item "2.【用户配置目录】\ids_search.schema.yaml" "$RimeUserDir\ids_search.schema.yaml" -Force

if (-not (Test-Path "$RimeUserDir\ids_custom.txt")) {
    Copy-Item "2.【用户配置目录】\ids_custom.txt" "$RimeUserDir\ids_custom.txt" -Force
}

if (-not (Test-Path "$RimeUserDir\default.custom.yaml")) {
    Copy-Item "2.【用户配置目录】\default.custom.yaml" "$RimeUserDir\default.custom.yaml" -Force
}

# 6. 部署并重启
Write-Host "[4/4] 正在执行小狼毫重新部署并拉起服务..." -ForegroundColor Cyan
$Deployer = "$WeaselDir\WeaselDeployer.exe"
if (Test-Path $Deployer) {
    & $Deployer /deploy
}
Start-Process "$WeaselDir\WeaselServer.exe"
Start-Sleep -Seconds 1

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host "  🎉 安装部署成功！按 Ctrl+Shift+Space 即可直接切换开启部件模糊检字！" -ForegroundColor Green
Write-Host "  💡 万象用户提示：若需在万象拼音下按大写 I 挂接检字，请参考" -ForegroundColor Yellow
Write-Host "     【可选：万象拼音挂接补丁(仅供参考)】文件夹按需合入，绝不冲掉您的原配置。" -ForegroundColor Yellow
Write-Host "==============================================================================" -ForegroundColor Green
Write-Host ""
