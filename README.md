# Rime IDS Search C++ 原生开发工程套件 (idsc++)

本目录是 **Rime 汉字部件模糊检字 (IDS Search) C++ 原生版本** 的完整源码、数据、预编译产物与持续集成开发套件，汇集了从插件源码、二进制索引数据、Rime 挂接方案到云端自动化构建的全部资产，便于后续二次开发与维护。

---

## 一、目录结构总览

```text
idsc++/
├── README.md                          # 本工程核心说明文档
├── backup/                            # 历史架构快照备份
│   └── ids2_release_20261024/         # IDS2 架构无损回滚归档 (源码/数据/旧版 rime.dll)
├── src/                               # C++ 插件完整源码 (librime-ids-search, commit 18b5cdc)
│   ├── CMakeLists.txt                 # librime 外部插件 CMake 配置文件
│   ├── README.md                      # 原作者插件设计说明
│   └── src/
│       ├── ids_search_module.cc       # 模块注册入口 (RIME_REGISTER_MODULE)
│       ├── ids_search_translator.cc   # 检字翻译器核心实现 (类 ids_search_translator)
│       ├── ids_search_translator.h    # 检字翻译器头文件
│       ├── ids_store.cc               # IDS3 单文件 mmap 映射、稠密 id 与位图求交
│       └── ids_store.h                # 数据存储、Token 与 HOT 直索引头文件
├── data/                              # 核心数据文件与生成链
│   ├── ids_data.bin                   # IDS3 紧凑单文件数据表 (24.35 MB)
│   ├── generate_data_v2.py            # 数据生成工具链脚本
│   ├── ids_custom.txt                 # 用户自定义读音、别名与分区过滤规则
│   ├── IDS_raw.TXT                    # 原始 BabelStone IDS 数据库
│   ├── ids_zitools.txt                # 原始 zi.tools Level 2 归一部件表
│   ├── ids_lv1.txt                    # 原始 zi.tools Level 1 权威表
│   ├── EquivalentUnifiedIdeograph.txt # 偏旁等价映射
│   ├── ids_index.txt                  # 倒排索引明文表
│   └── ids_meta.txt                   # 字符元数据明文表
├── schema/                            # Rime 方案与挂接配置文件
│   ├── ids_search.schema.yaml         # 独立部件检字输入方案 (免前缀直打)
│   ├── wanxiang_pro.custom.yaml       # 万象拼音挂接范本 (大写 I 检字 + 大写 J 日文)
│   └── default.custom.yaml            # 方案选单快捷键注册范本
├── dist/                              # 已编译就绪的 Windows x64 二进制与 SDK (最新构建)
│   ├── bin/
│   │   ├── rime.dll                   # 核心动态库 (已集成 librime-ids-search 18b5cdc + librime-lua)
│   │   ├── rime_deployer.exe          # 命令行部署工具
│   │   ├── rime_dict_manager.exe      # 词典管理工具
│   │   └── rime_patch.exe             # 补丁合并工具
│   ├── lib/
│   │   ├── rime.dll                   # 动态库链接副本
│   │   ├── rime.lib                   # MSVC 导入库
│   │   └── rime.pdb                   # 调试符号文件 (54.6 MB)
│   ├── include/                       # librime C/C++ API 开发头文件
│   └── version-info.txt               # 本次构建集成的 commit hash 与插件清单
└── ci/                                # 自动化构建配置
    └── release-ci.yml                 # GitHub Actions 云端多架构自动编译脚本
```

---

## 二、核心架构与技术原理

C++ 原生版本彻底替代传统 Lua 方案在海量汉字检索场景下的性能瓶颈：

1. **单文件与 `mmap` 惰性虚拟内存映射**：
   - 采用单文件 **`ids_data.bin`（约 24.3 MB）** 取代旧版双文件；操作系统按需换页映射，零启动大内存分配冲击。
2. **稠密字 ID（Dense ID）与 HOT 热记录直索引**：
   - 10.3 万+ 汉字映射至连续 `0..N-1` 空间，12 字节 HOT 记录直索引 `{freq, depth, block, char_token, flags}`，寻址零间接跳转。
3. **整数部件 Token 化与位图求交（Bitmap AND）**：
   - 1.4 万+ 部件编号为 `u16` Token，大 key 倒排采用位图存储，多项部件组合求交直接走 64 位整数按位与运算，彻底不构建哈希表，单次按键响应延迟达到 **< 0.05ms**。
4. **双拼智能切分**：
   - 内部支持小鹤双拼（`flypy`）、自然码（`zrm`）和全拼自动切分与贪心回退，无需手动空格分隔。

---

## 三、后续开发与构建流程

### 方式 1：利用 GitHub Actions 云端一键构建（推荐，无需本地配置环境）
您已经在您的 GitHub 账号建立了专属 Fork：**`suiginko/librime`**。

1. **修改源码**：
   在 `src/src/` 中修改 C++ 源码（如改进部件排序算法、扩充支持更多双拼等），或者在自己的 `librime-ids-search` 仓库中推送提交。
2. **触发构建**：
   进入 GitHub `suiginko/librime` 仓库的 **Actions** 页面，找到 **Release CI**，点击 **Run workflow**。
3. **下载产物**：
   构建脚本会全自动调用微软云端 Windows 机器编译 MSVC x64，约 8 分钟后在页面下方的 **Artifacts** 中下载 `artifact-Windows-msvc-x64`，解压出来的 `rime.dll` 即为最新编译产物。

### 方式 2：本地 CMake + MSVC 编译
如果您本地未来安装了 Visual Studio 2022（需勾选 C++ 桌面开发）：
```powershell
# 1. 克隆 librime
git clone --recursive https://github.com/rime/librime.git
cd librime

# 2. 将 src 源码放入 plugins 目录
New-Item -ItemType Directory -Path plugins/ids-search -Force
Copy-Item -Recurse <当前路径>/src/* plugins/ids-search/

# 3. 执行编译
.\build.bat deps
.\build.bat
# 编译产出位于 dist/bin/rime.dll
```

---

## 四、桌面端（小狼毫 Weasel）部署路径参考

如需在日常使用的小狼毫中更新或重新部署：
1. **替换 DLL**：
   退出小狼毫进程（`Stop-Process -Name WeaselServer -Force`），将 `dist/bin/rime.dll` 复制覆盖到：
   ```text
   C:\Program Files\Rime\weasel-0.17.4\rime.dll
   ```
2. **部署数据文件**：
   将 `data/ids_data.bin` 放到用户数据目录下的 `build/` 目录：
   ```text
   %APPDATA%\Rime\build\
   ```
3. **方案挂接**：
   将 `schema/ids_search.schema.yaml` 复制到 `%APPDATA%\Rime\`，并在宿主方案（如 `wanxiang_pro.custom.yaml`）中通过 `ids_search_translator` 挂接大写 `I` 前缀。
4. **重新部署**：
   右键小狼毫选择“重新部署”即可生效。

---

## 五、移动端（Android）部署指引（推荐使用 LyraIME 灵韵输入法）

### 1. 为什么强烈推荐 LyraIME（灵韵输入法）？
- **原生内置 C++ 检字引擎**：
  LyraIME（最新 Nightly / Release）底层 `librime_jni.so` 原生静态集成了 `librime-ids-search` 原生组件，天然支持 `ids_search_translator`，完全摆脱传统老旧 Lua 方案在手机上的卡顿、丢键与高耗电。
- **现代化架构与隔离方案包管理**：
  采用多方案包分目录隔离架构（`Documents/LyraIME/<方案包名>/`），各方案的词典、脚本与配置互不干扰，支持一键切换。
- **极致的检字响应**：
  配合单文件 `ids_data.bin`（IDS3 架构），在 Android 设备上实现 `< 1ms` 汉字全量 10.4 万+ 部件快速求交。

> **客户端项目主页**：[Carlson24/LyraIME (GitHub)](https://github.com/Carlson24/LyraIME)

---

### 2. 手机端存储目录结构

Android 设备中 LyraIME 的用户数据根目录位于外部存储的 Documents 目录：
```text
内部存储设备/Documents/LyraIME/
├── <方案包名>/                   # 方案包目录（如 wanxiang、ids_search 等）
│   ├── <方案名>.schema.yaml      # 主方案配置
│   ├── <方案名>.custom.yaml      # 用户自定义补丁
│   ├── ids_data.bin              # IDS3 紧凑单文件数据表（核心数据）
│   ├── ids_custom.txt            # 自定义读音与别名过滤
│   ├── build/                    # 预编译二进制目录（防 OOM 核心）
│   │   ├── ids_data.bin          # 供 translator 直接读取
│   │   ├── *.table.bin           # 预编译词库二进制
│   │   └── *.prism.bin
│   ├── opencc/                   # 字符转换数据
│   └── lua/                      # 方案附加 Lua 脚本
├── themes/                       # 键盘皮肤主题目录
│   ├── build/                    # 主题编译缓存 (.json)
│   └── *.lua / *.yaml            # 主题源文件
└── shared/                       # 跨方案共享资源目录
```

---

### 3. 手机端安装与部署标准流程

#### 步骤 1：安装灵韵输入法 APK
从 [Carlson24/LyraIME Releases](https://github.com/Carlson24/LyraIME/releases) 下载最新 APK，安装至手机并根据系统引导开启输入法权限与存储访问权限。

#### 步骤 2：连接电脑并传输核心数据
使用 USB 数据线将手机连接电脑，选择 **“传输文件 (MTP)”** 模式：
1. 打开 `此电脑\<手机设备名>\内部存储设备\Documents\LyraIME\`。
2. 进入您日常使用的方案目录（例如 `wanxiang/`）。
3. 将本项目 `data/` 目录中的以下文件同步至手机对应目录：
   - `ids_data.bin` -> 复制到 `wanxiang/` 以及 `wanxiang/build/`
   - `ids_custom.txt` -> 复制到 `wanxiang/` 以及 `wanxiang/build/`
   - `schema/ids_search.schema.yaml` -> 复制到 `wanxiang/` 以及 `wanxiang/build/`

#### 步骤 3：在宿主方案中挂接部件检字（以万象拼音 PRO 为例）
编辑手机端 `wanxiang/wanxiang_pro.custom.yaml`，加入以下补丁：
```yaml
patch:
  # 1. 声明依赖
  schema/dependencies/+:
    - ids_search

  # 2. 正则识别大写 I 引导
  recognizer/patterns/ids_search: '^I[^0-9,.;=\[\]\s-]*$'

  # 3. 挂接分段器与标签
  engine/segmentors/@before 3: affix_segmentor@ids_search
  ids_search:
    tag: ids_search
    prefix: "I"
    tips: "〔ids检字〕"

  # 4. 挂接 C++ 原生检字翻译器
  engine/translators/+:
    - ids_search_translator

  # 5. 原生翻译器参数配置 (IDS3 单文件)
  ids_search: &ids_search_conf
    data_file: build/ids_data.bin
    tag: ids_search
    prefix: ""
    tips: "〔ids检字〕"
    max_results: 60
    shuangpin_scheme: flypy      # 双拼切分支持：flypy(小鹤) / zrm(自然码) / quanpin(全拼)
    show_pinyin: true           # 候选显示拼音与声调
    show_ids: true              # 候选显示 IDS 拆分结构
    show_unicode: true          # 候选显示 Unicode 码点
    show_block: true            # 候选显示字符集分区 (Ext-A~J)
    custom_file: ids_custom.txt # 用户自定义读音与过滤配置

  ids_search_translator: *ids_search_conf
```

#### 步骤 4：在灵韵输入法中重新部署
1. 打开手机上的 **LyraIME（灵韵输入法）** 应用。
2. 进入 **方案设置** -> 点击 **【重新部署】**。
3. 部署完成后在任意文本框呼出键盘，输入大写 `I`（如输入 `Imumu` 检索 `林`、`Ikouhao` 检索 `𫩠`），即可体验毫秒级秒出候选。

---

### 4. 移动端核心避坑指南（CRITICAL）

1. **避免手机端超大词典编译导致 OOM 闪退**：
   - 手机移动处理器的内存分配策略对单次连续大内存分配（Large Continuous Allocation）有限制。若方案包含超大词典（如 Kagiroi 日文 100MB 矩阵词库、超百万大词库），在手机上直接触发首次编译会抛出 `operator new` 内存溢出导致底层 `abort()` 闪退。
   - **正确做法**：在电脑端用小狼毫生成好预编译二进制（`.table.bin`、`.prism.bin`、`.reverse.bin`），直接通过 USB 复制到手机对应方案的 `build/` 目录下，跳过手机本地耗时且高风险的词库编译。
2. **键盘皮肤主题内存控制**：
   - 若使用自定义皮肤主题，避免单主题内嵌过多罕用键盘布局（超过数百个布局会导致序列化 JSON 体积膨胀引发 Java 堆内存溢出）。建议剔除冷门布局，并优先回退使用系统字体以获得最流畅的按键渲染性能。
3. **MTP 传输落盘缓冲**：
   - 通过 Windows 资源管理器往手机传输文件时，MTP 协议为异步队列处理。传输超大二进制表（如 `kagiroi_matrix.table.bin`、`ids_index.bin`）后，请等待数秒让手机端文件系统完全落盘再拔掉数据线或触发部署。

---

## 六、双模检字特性支持

本套件同时支持两种互补的部件检字模式，兼顾极致响应与直观交互：

| 特性维度 | 模式一：原生 C++ 直打检字 (`I` 模式) | 模式二：汉字拼音混合检字 (`O` 模式) |
| :--- | :--- | :--- |
| **引导按键** | 大写 `I` 引导（如 `Imumu`、`Ikouhao`） | 大写 `O` 引导（如 `O木口`、`O木kz`） |
| **底层实现** | C++ 原生插件 (`ids_search_translator`) | 高性能 Lua 管道 + 二进制倒排索引 |
| **输入方式** | 纯字母连续键入，自动贪心切分 | 支持汉字部件（空格选字）与拼音/双拼混合键入 |
| **双拼支持** | C++ 内部双拼切分 (小鹤/自然码/全拼) | 原生动态感知万象当前激活双拼方案并实时消歧 |
| **界面呈现** | 极速单行 preedit，原汁原味原生响应 | 采用零宽空格渲染，消除背景黑块，无感过渡 |
| **候选信息** | xiā、IDS 结构、Unicode 编码、字符集分区 | 与 I 模式完全对齐的完整元数据注释 |

---

## 七、致谢 (Acknowledgments)

感谢协助：

- **[@Carlson24](https://github.com/Carlson24)**：[librime-ids-search](https://github.com/Carlson24/librime-ids-search)（C++ 原生部件检字插件与 IDS3 架构）
- **[@ksqsf](https://github.com/ksqsf)**：[rimeinn/hanzi-search](https://github.com/rimeinn/hanzi-search)（Rime 部件检字挂接方案）
