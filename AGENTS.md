# AGENTS.md — Rime IDS C++ 插件工程 AI 协同开发指南

本文件专为 AI 编码助手（Antigravity、Cursor、Claude Code、Copilot 等）制定。在协助用户维护或开发本项目时，**必须严格遵循本指南中的架构共识、避坑红线与操作标准流程**。

---

## 1. 项目核心背景与技术定位

- **项目名称**：Rime IDS Search C++ 原生增强套件 (`idsc++`)
- **核心组件**：`librime-ids-search`（注册组件名：`ids_search_translator`）
- **核心目标**：实现全量 Unicode 汉字（10.4万+）在 Rime 输入法中的毫秒级部件检索（如输入 `Imumu` 检索 `林`、`Ikouhao` 检索 `𫩠`）。
- **性能标杆**：单字检索 `< 0.1ms`，多项哈希求交 `< 1ms`（老旧 Lua 方案因逐字磁盘 IO 和正则扫表存在 ~180ms 顿挫，已被废弃）。

---

## 2. 绝对红线与避坑法则（CRITICAL）

### ❌ 严禁行为
1. **严禁退回或引入 Lua 检字方案**：
   - 不要在 `lua/` 目录下重新创建 `ids_search.lua`。
   - 不要将 schema/custom 中的 translator 改写为 `lua_translator@*ids_search`。
   - 现行输入法架构已全面切换为原生 C++ 类 `ids_search_translator`。
2. **严禁在 WeaselServer 运行中直接覆盖 DLL**：
   - Windows 会将运行中的 DLL 加锁，直接复制会报 `Access Denied`。
   - 覆盖前**必须先结束进程**：`Stop-Process -Name WeaselServer -Force`。
3. **严禁破坏用户的个性化输入习惯**：
   - 保护分号快符：`recognizer/patterns/quick_symbol: "^;.*$"`
   - 保护分号次选：`{ when: has_menu, accept: semicolon, send: 2 }`
   - 保护逗号句号翻页：`comma -> Page_Up`, `period -> Page_Down`
4. **严禁误导用户在无编译环境的本地电脑上执行 C++ 编译**：
   - 本机未安装大型 Visual Studio MSVC 与 Boost/OpenCC 依赖环境。
   - 编译必须使用用户的 GitHub Fork 仓库通过 **GitHub Actions 云端 8 分钟自动构建**。

---

## 3. 云端自动编译与取件流水线（GitHub Actions）

用户拥有专用编译仓库：**`suiginko/librime`**

### 工作流位置
- 配置文件：`ci/release-ci.yml`（对应云端 `.github/workflows/release-ci.yml`）
- Windows 编译插件定义：
  ```yaml
  windows:
    uses: ./.github/workflows/windows-build.yml
    with:
      rime_plugins: hchunhui/librime-lua lotem/librime-octagram rime/librime-predict Carlson24/librime-ids-search
  ```

### 触发与取件标准流程（AI 可直接运行）
```powershell
# 1. 设置认证环境（利用本地 Git 凭据获取 Token）
$inputStr = "protocol=https`nhost=github.com`n`n"
$p = Start-Process git.exe -ArgumentList "credential fill" -NoNewWindow -PassThru -RedirectStandardInput ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($inputStr))) -RedirectStandardOutput ([System.IO.MemoryStream]::new())
# (获取 $token 后注入环境变量)
$env:GH_TOKEN = $token

# 2. 触发云端编译
gh workflow run release-ci.yml -R suiginko/librime

# 3. 监控最新运行状态
gh run list -R suiginko/librime --limit 1

# 4. 编译完成后下载产物
gh run download <RUN_ID> -R suiginko/librime -n artifact-Windows-msvc-x64 --dir "C:\temp\build_out"

# 5. 解压产物得到 rime.dll
# 7z 解压 rime-*-Windows-msvc-x64.7z 提取 dist/bin/rime.dll
```

---

## 4. 部署与热替换规范

### 4.1 桌面端（小狼毫 Weasel）部署规范
- **安装目录**：`C:\Program Files\Rime\weasel-0.17.4\`
- **核心文件**：`rime.dll`（64位 MSVC 编译版，Commit 18b5cdc）
- **数据目录**：`%APPDATA%\Rime\build\`
  - `ids_data.bin`（IDS3 紧凑单文件数据表，24.35 MB）
- **历史回滚备份**：`c:\Users\Hg\Documents\antigravity\idsc++\backup\ids2_release_20261024\`

#### 部署标准步骤
```powershell
# 1. 停止运行中服务
Stop-Process -Name WeaselServer -Force -ErrorAction SilentlyContinue

# 2. 写入或替换 rime.dll（需要管理员权限，可通过提权批处理或 RunAs 执行）
Copy-Item "dist\bin\rime.dll" "C:\Program Files\Rime\weasel-0.17.4\rime.dll" -Force

# 3. 确保数据文件就位
Copy-Item "data\ids_data.bin" "$env:APPDATA\Rime\build\ids_data.bin" -Force
Copy-Item "data\ids_data.bin" "$env:APPDATA\Rime\ids_data.bin" -Force

# 4. 执行重新部署
& "C:\Program Files\Rime\weasel-0.17.4\WeaselDeployer.exe" /deploy

# 5. 重新拉起小狼毫服务
Start-Process "C:\Program Files\Rime\weasel-0.17.4\WeaselServer.exe"
```

### 4.2 移动端（Android - LyraIME 灵韵输入法）协同规范
- **核心客户端推荐**：**`Carlson24/LyraIME`（灵韵输入法）**
  - 底层原生静态内置 `librime-ids-search`（注册类 `ids_search_translator`），天然支持部件检索。
- **存储目录约定**：`内部存储设备/Documents/LyraIME/<方案包名>/`（如 `wanxiang/`、`kagiroi/`）
- **移动端部署三铁律**：
  1. **严禁在手机上直接触发超大词典编译（CRITICAL）**：
     - Kagiroi 矩阵词典（100MB）或大规模外挂词库在手机端编译会因连续大内存分配失败抛出 `operator new`，导致 Android 进程 `abort()` 闪退。
     - **必须**在 PC 端生成 `.table.bin`、`.prism.bin`、`.reverse.bin` 后直接同步至手机方案的 `build/` 目录。
  2. **数据双向冗余部署**：
     - `ids_data.bin` 必须同时推送到方案根目录及 `build/` 目录。
  3. **MTP 传输落盘防积压**：
     - Windows MTP COM 组件异步处理大文件时，需按文件逐个复制并轮询检测存在（等待 1~3 秒），防止传输管道丢包或积压未落盘。

---

## 5. 数据格式与协议规范（IDS3 单文件）

### A. `ids_data.bin` (IDS3 架构)
- **Header (32 字节)**：
  - `magic` [4B]: ASCII `"IDS3"`
  - `version` [2B uint16]: 1
  - `flags` [2B uint16]
  - `max_cp` [4B uint32]: 最大 Codepoint
  - `num_chars` [4B uint32]: 索引汉字总数 (103,375+)
  - `num_keys` [4B uint32]: 索引项总数 (16,274+)
  - `num_sections` [4B uint32]: 区间总数 (15 个 sections)
- **Sections 结构 (节表定长、小端、8 字节对齐)**：
  - `CP2ID` / `ID2CP`：稠密连续整数 ID 映射
  - `HOT`：12 字节定长热记录 `{freq, depth, block, char_token, flags}`，寻址零间接跳转
  - `ALTS` / `COMPSET` / `COLD`：变体序列与拼音/IDS 紧凑存储
  - `POST_HEAD` / `POST_SMALL` / `POST_BITSET`：热头有序数组、小 key 升序数组、大 key 64位无符号字位图 (Bitmap)
- **多项求交**：大 key 位图与运算（Bitmap AND）+ 双指针归并，零动态哈希表分配，延迟 < 0.05ms。

### B. `ids_custom.txt` 自定义规则
- 格式规范：
  - 追加读音：`灬  biao`
  - 删除读音：`阝  -er`
  - 禁用分区：`-block 扩B 扩C 扩D 扩E 扩F 扩G 扩H 扩I 扩J`
  - 覆盖重设：`阝  =fu yi`

---

## 6. 验证与门禁检查清单

在宣布任何开发或修改完成前，AI 必须通过日志与进程执行以下验证：

1. **DLL 符号门禁**：
   使用二进制读取确认 `rime.dll` 包含 `ids_search_translator`、`ids_search`、`lua_translator`。
2. **底层加载日志门禁**：
   读取 `C:\windows\TEMP\rime.weasel\*.INFO*`，确认包含：
   ```text
   prescription='ids_search_translator' class='ids_search_translator' ... success=1
   ```
   且 `*.ERROR*` 日志中**严禁出现** `error creating translator: 'ids_search_translator'`。
3. **功能门禁**：
   输入大写 `I` 能正常弹出 `〔部件检字〕` 提示并输出带有读音、IDS 结构、Unicode 码与分区的候选。
