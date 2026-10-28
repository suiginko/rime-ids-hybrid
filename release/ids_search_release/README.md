# Rime 全功能汉字部件检字套件 (发布包)

全量 10.4 万 Unicode 汉字（基本区 + 扩展 A~J）毫秒级部件检索，支持汉字、全拼与双拼混合检字。

---

## 快速使用方法

### 1. 混合检字（大写 `O` 引导，最推荐）
敲大写 **`O`** 引导，支持**汉字部件**与**拼音/双拼**混合检索：
- **汉字输入**：输入拼音后按空格选汉字部件，多个部件自动求交（如 `O木木` $\to$ 首选 `林`，`O沐木` $\to$ 首选 `淋`）；
- **部件加减法**：
  - **减法（扣除部件）**：按 `-` 减号输入需要去掉的部件（如 `O佩-亻` $\to$ 首选 `𫥞`，`O春-日` $\to$ 首选 `𡗗`，`O森-木` $\to$ 首选 `林`）；
  - **加法（减后继续组合）**：按 `+`（或免按 Shift 的 `=` 键）继续添加部件组合检索（如 `O佩-亻+木` $\to$ 首选 `𣑲`，`O泰-氺+日` $\to$ 首选 `春`，`O森-木+氵` $\to$ 首选 `淋`）；
- **字母直出**：输入拼音或双拼后按回车，直接将字母编码作为部件检字（如 `Omu` 按回车 $\to$ 直接作为部件）；
- **双拼支持**：完美支持小鹤双拼、自然码等（如打 `kz` 自动识别为口，`ho` 自动识别为火）。

### 2. 纯字母检字（大写 `I` 引导）
敲大写 **`I`** 引导，连续键入各部件全拼或双拼：
- `Imumu` $\to$ 检索出 `林`、`森` 等
- `Ikouhao` $\to$ 检索出 `𫩠`、`号` 等

### 3. 一键上屏 IDS 拆解结构
候选框展示时，想直接输入该字的部件结构（如把 `鼯` 打成 `⿰鼠吾`）：
- **当前选中的字**：按 **`Ctrl + Enter`**（或 `Alt + Enter`）；
- **指定序号的字**：按 **`Ctrl + 1` ~ `5`**（例如按 `Ctrl + 3` 直接上屏第 3 个候选的 IDS 结构）。

### 4. 翻页与选字
- **选字**：数字键 `1` ~ `5` 或空格；
- **次选**：分号 `;` 快速选择第 2 候选；
- **翻页**：逗号 `,` 上一页，句号 `.` 下一页。

---

## 安装方法（电脑端小狼毫）

### 方式一：一键自动安装（推荐）
鼠标右键点击 **`一键安装(管理员运行).bat`**，选择【以管理员身份运行】即可自动完成独立方案的安装与部署。

### 方式二：手动覆盖安装
1. **退出小狼毫**：右键任务栏托盘图标 $\to$ 点击【退出】；
2. **复制核心文件**：打开 `1.【小狼毫程序目录】`，将 `rime.dll` 复制覆盖到小狼毫安装目录（通常为 `C:\Program Files\Rime\weasel-0.17.4\`）；
3. **复制配置文件**：打开 `2.【用户配置目录】`，将里面所有文件（包括 `ids_data.bin` 与 `lua/` 文件夹）复制到小狼毫用户目录（`%APPDATA%\Rime\`）；
4. **重新部署**：右键托盘图标 $\to$ 点击【重新部署】完成。

### 方式三：挂接到现有常用方案（如万象拼音/白霜/雾凇等，推荐）
若您已有调好的常用拼音输入方案，推荐通过 patch 挂接，**既能随时呼出检字，又绝不冲掉您原有的词库、双拼、辅助码与快符习惯**：
1. 运行方式一的一键安装，或手动将 `rime.dll`、`ids_data.bin` 及 `lua/` 文件夹复制就位；
2. 打开您的 `<方案名>.custom.yaml`（例如 `%APPDATA%\Rime\wanxiang_pro.custom.yaml`），在 `patch:` 节点下追加以下配置：

```yaml
patch:
  # 1. 挂接交互处理器与分段器
  engine/processors/@before 0: lua_processor@*ids_hybrid_composer*editor
  engine/segmentors/@before 0: lua_segmentor@*ids_hybrid_composer*segmentor
  engine/segmentors/@before 3: affix_segmentor@ids_search

  # 2. 挂接翻译器 (I 模式原生 C++ + O 模式混合部件检字)
  engine/translators/+:
    - ids_search_translator@ids_trans
    - lua_translator@*ids_hybrid_composer*translator

  # 3. 挂接过滤器 (部件单字保护与候选去重)
  engine/filters/@before 0: lua_filter@*ids_hybrid_composer*filter
  engine/filters/+:
    - lua_filter@*ids_hybrid_composer*cleaner

  # 4. 触发正则匹配 (大写 I 引导纯拼音 / 大写 O 引导混合部件)
  recognizer/patterns/ids_search: '^I[^0-9,.;=\[\]\s-]*$'
  recognizer/patterns/ids_search_hybrid: '^O.*$'

  # 5. 检字组件参数
  ids_search:
    tag: ids_search
    prefix: "I"
    tips: "〔部件检字〕"

  ids_trans:
    data_file: build/ids_data.bin
    tag: ids_search
    prefix: ""
    tips: "〔部件检字〕"
    max_results: 60
    show_pinyin: true
    show_ids: true
    show_unicode: true
    show_block: true
    ids_format: unicode
    custom_file: ids_custom.txt

  ids_hybrid:
    data_file: build/ids_data.bin
    tag: ids_search_hybrid
    prefix: "O"
    tips: "〔汉字部件检字〕"
    max_results: 60
    show_pinyin: true
    show_ids: true
    show_unicode: true
    show_block: true
    ids_format: unicode
    custom_file: ids_custom.txt
```
3. 右键小狼毫托盘图标 $\to$ 点击【重新部署】即可在您常用方案中直接打 `O` 或 `I` 检字。

---

## 致谢 (Acknowledgments)

- **[@Carlson24](https://github.com/Carlson24)**：[librime-ids-search](https://github.com/Carlson24/librime-ids-search)（C++ 原生部件检字插件与 IDS3 架构）
- **[@ksqsf](https://github.com/ksqsf)**：[rimeinn/hanzi-search](https://github.com/rimeinn/hanzi-search)（Rime 部件检字挂接方案）

