# 安卓端（Android - 灵韵输入法 LyraIME）部件检字部署指南

---

## 一、 核心客户端推荐：灵韵输入法 (LyraIME)

- **项目地址**：`https://github.com/Carlson24/LyraIME`
- **原生优势**：底层由原作者原生静态编译内置了 `librime-ids-search`（注册类 `ids_search_translator`），天然支持 IDS3 极速部件检字，性能优异。
- **存储目录**：`内部存储设备/Documents/LyraIME/<方案包名>/`（例如 `wanxiang/` 或 `kagiroi/`）

---

## 二、 移动端部署三铁律（CRITICAL，必读）

### 1. 严禁在手机上直接触发超大词典编译！
- 万象拼音或 Kagiroi 矩阵词典（上百兆词库）如果在手机端直接触发“部署/编译”，极易因连续大内存分配失败抛出 `operator new`，导致 Android 进程直接 `abort()` 闪退。
- **正确做法**：**必须先在 PC 电脑端** 完成小狼毫的部署，生成 `build/` 目录下的 `.table.bin`、`.prism.bin`、`.reverse.bin` 等全套预编译二进制文件，然后直接整包同步复制到手机对应方案的 `build/` 目录！

### 2. 数据双向冗余部署
- 将 `ids_data.bin` 同时放入：
  1. 方案根目录：`内部存储设备/Documents/LyraIME/<方案包名>/ids_data.bin`
  2. 方案编译目录：`内部存储设备/Documents/LyraIME/<方案包名>/build/ids_data.bin`

### 3. MTP 传输防管道丢包
- 通过 USB 数据线将大文件推送到手机时，Windows MTP 传输大文件是异步管道机制。请按大文件逐个拷贝，等待进度条完全结束落盘，切勿在文件未写完时直接拔线。

---

## 三、 万象方案手机端挂接配置

在手机端的 `wanxiang_pro.custom.yaml` 中，贴入以下片段：

```yaml
patch:
  # 1. 依赖声明
  schema/dependencies/+:
    - ids_search

  # 2. 挂接识别正则（大写 I 引导）
  recognizer/patterns/ids_search: '^I[^0-9,.;=\[\]\s-]*$'

  # 3. 挂接分词器（提示方案名）
  engine/segmentors/@before 3: affix_segmentor@ids_search
  ids_search:
    tag: ids_search
    prefix: "I"
    tips: "〔ids检字〕"

  # 4. 挂接翻译器
  engine/translators/+:
    - ids_search_translator@ids_trans

  # 5. 检字参数
  ids_trans:
    data_file: build/ids_data.bin
    tag: ids_search
    prefix: ""
    tips: "〔ids检字〕"
    max_results: 60
    shuangpin_scheme: flypy
    show_pinyin: true
    show_ids: true
    show_unicode: true
    show_block: true
    ids_format: unicode
```

---

## 四、 快速生效

在手机上打开灵韵输入法（LyraIME），点击 **【重新部署】**（或下拉刷新），即可在万象拼音下直接敲击大写 **`I`** 呼出部件检字！
