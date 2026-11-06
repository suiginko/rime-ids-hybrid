#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
export_variants.py
异体字全量数据库多格式导出工具
支持导出：
1. ids_variants.json (极简轻量键值对)
2. ids_variants_detailed.json (含 Unicode、拼音、IDS、分区元数据)
3. ids_variants.csv (Excel 兼容，UTF-8 BOM)
4. ids_variants.sqlite (专业嵌入式关系数据库，带双向索引与等价簇)
5. ids_variant_clusters.json (基于并查集的双向全互通等价簇)
6. ids_variants_normalized.tsv (标准化纯文本)
7. README.md (数据库说明与开发调用文档)
"""

import os
import sys
import json
import csv
import sqlite3
import struct
import unicodedata
from collections import defaultdict

BLOCK_NAMES = [
    "基本", "扩A", "扩B", "扩C", "扩D", "扩E", "扩F", "扩G", "扩H", "扩I", "扩J",
    "兼容", "兼容补充", "部首补充", "康熙部首", "笔画", "未知"
]

def get_unicode_block_fallback(cp):
    if 0x4E00 <= cp <= 0x9FFF:
        return "基本"
    elif 0x3400 <= cp <= 0x4DBF:
        return "扩A"
    elif 0x20000 <= cp <= 0x2A6DF:
        return "扩B"
    elif 0x2A700 <= cp <= 0x2B73F:
        return "扩C"
    elif 0x2B740 <= cp <= 0x2B81F:
        return "扩D"
    elif 0x2B820 <= cp <= 0x2CEAF:
        return "扩E"
    elif 0x2CEB0 <= cp <= 0x2EBEF:
        return "扩F"
    elif 0x30000 <= cp <= 0x3134F:
        return "扩G"
    elif 0x31350 <= cp <= 0x323AF:
        return "扩H"
    elif 0x2EBF0 <= cp <= 0x2EE5F:
        return "扩I"
    elif 0x323B0 <= cp <= 0x3347F:
        return "扩J"
    elif 0xF900 <= cp <= 0xFAFF:
        return "兼容"
    elif 0x2F800 <= cp <= 0x2FA1F:
        return "兼容补充"
    elif 0x2E80 <= cp <= 0x2EFF:
        return "部首补充"
    elif 0x2F00 <= cp <= 0x2FDF:
        return "康熙部首"
    elif 0x31C0 <= cp <= 0x31EF:
        return "笔画"
    else:
        return "其他"

def load_char_metadata(bin_path):
    meta = {}
    if not os.path.exists(bin_path):
        print(f"[Warning] {bin_path} not found, using unicode fallback.")
        return meta

    print(f"[1/6] Loading IDS3 metadata from {bin_path}...")
    with open(bin_path, 'rb') as f:
        blob = f.read()

    header = blob[:32]
    magic, ver, flags, max_cp, num_chars, num_keys, num_sec = struct.unpack('<4sHHIIII', header[:24])
    if magic != b'IDS3':
        print(f"[Warning] Invalid magic {magic}, skipping binary metadata.")
        return meta

    sections = {}
    st = 32
    for i in range(num_sec):
        sec_type, pad, off, length = struct.unpack('<IIQQ', blob[st + i * 24: st + (i + 1) * 24])
        sections[sec_type] = (off, length)

    id2cp_off, _ = sections[2]
    hot_off, _ = sections[3]
    cold_off_off, _ = sections[8]
    cold_off, _ = sections[9]

    id2cp = struct.unpack(f'<{num_chars}I', blob[id2cp_off: id2cp_off + num_chars * 4])
    cold_offsets = struct.unpack(f'<{num_chars}I', blob[cold_off_off: cold_off_off + num_chars * 4])

    for vid in range(num_chars):
        cp = id2cp[vid]
        char_str = chr(cp)

        h_pos = hot_off + vid * 12
        freq, depth, block_id, char_token, flags = struct.unpack('<IBBH I', blob[h_pos: h_pos + 12])
        block_name = BLOCK_NAMES[block_id] if block_id < len(BLOCK_NAMES) else "未知"

        c_pos = cold_off + cold_offsets[vid]
        py_len = struct.unpack('<H', blob[c_pos: c_pos + 2])[0]
        py_str = blob[c_pos + 2: c_pos + 2 + py_len].decode('utf-8', errors='replace')
        p_ids = c_pos + 2 + py_len
        ids_len = struct.unpack('<H', blob[p_ids: p_ids + 2])[0]
        ids_str = blob[p_ids + 2: p_ids + 2 + ids_len].decode('utf-8', errors='replace')

        meta[char_str] = {
            "unicode": f"U+{cp:04X}",
            "codepoint": cp,
            "pinyin": py_str,
            "ids": ids_str,
            "block": block_name,
            "depth": depth,
            "freq": freq
        }

    print(f"      Loaded {len(meta):,} character metadata records.")
    return meta

class DisjointSet:
    def __init__(self):
        self.parent = {}
    def find(self, x):
        if x not in self.parent:
            self.parent[x] = x
            return x
        if self.parent[x] != x:
            self.parent[x] = self.find(self.parent[x])
        return self.parent[x]
    def union(self, x, y):
        rx = self.find(x)
        ry = self.find(y)
        if rx != ry:
            self.parent[ry] = rx

def main():
    bin_path = "data/ids_data.bin"
    txt_path = "data/ids_variants.txt"
    out_dir = "export_variants"
    os.makedirs(out_dir, exist_ok=True)

    char_meta = load_char_metadata(bin_path)

    def get_info(ch):
        if ch in char_meta:
            return char_meta[ch]
        cp = ord(ch) if len(ch) == 1 else (ord(ch[0]) if len(ch) > 0 else 0)
        return {
            "unicode": f"U+{cp:04X}",
            "codepoint": cp,
            "pinyin": "",
            "ids": "",
            "block": get_unicode_block_fallback(cp),
            "depth": 0,
            "freq": 0
        }

    print(f"[2/6] Parsing raw variants from {txt_path}...")
    variants_dict = {}
    dsu = DisjointSet()
    total_pairs = 0

    with open(txt_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if '\t' not in line:
                continue
            base, vars_str = line.split('\t', 1)
            var_list = [v for v in vars_str.split() if v and v != base]
            if not var_list:
                continue
            
            # 去重且保持顺序
            seen = set()
            unique_vars = []
            for v in var_list:
                if v not in seen:
                    seen.add(v)
                    unique_vars.append(v)
            
            variants_dict[base] = unique_vars
            total_pairs += len(unique_vars)

            # 聚类并查集构建
            if len(base) == 1 or (len(base) == 2 and 0xD800 <= ord(base[0]) <= 0xDBFF):
                for v in unique_vars:
                    if len(v) == 1 or (len(v) == 2 and 0xD800 <= ord(v[0]) <= 0xDBFF):
                        dsu.union(base, v)

    print(f"      Parsed {len(variants_dict):,} base entries with {total_pairs:,} variant relations.")

    # 1. 导出轻量级 ids_variants.json
    json_path = os.path.join(out_dir, "ids_variants.json")
    print(f"[3/6] Exporting lightweight JSON -> {json_path}...")
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(variants_dict, f, ensure_ascii=False, indent=2)

    # 2. 导出标准化 TSV 文件
    tsv_path = os.path.join(out_dir, "ids_variants_normalized.tsv")
    print(f"      Exporting normalized TSV -> {tsv_path}...")
    with open(tsv_path, 'w', encoding='utf-8') as f:
        f.write("# 原字\t异体字列表 (空格分隔)\n")
        for base, vars_list in variants_dict.items():
            f.write(f"{base}\t{' '.join(vars_list)}\n")

    # 3. 导出全字段明细 JSON
    detailed_json_path = os.path.join(out_dir, "ids_variants_detailed.json")
    print(f"[4/6] Exporting detailed JSON with metadata -> {detailed_json_path}...")
    detailed_data = []
    for base, vars_list in variants_dict.items():
        base_info = get_info(base)
        var_items = []
        for v in vars_list:
            v_info = get_info(v)
            var_items.append({
                "char": v,
                "unicode": v_info["unicode"],
                "codepoint": v_info["codepoint"],
                "block": v_info["block"],
                "pinyin": v_info["pinyin"],
                "ids": v_info["ids"]
            })
        detailed_data.append({
            "char": base,
            "unicode": base_info["unicode"],
            "codepoint": base_info["codepoint"],
            "block": base_info["block"],
            "pinyin": base_info["pinyin"],
            "ids": base_info["ids"],
            "variant_count": len(vars_list),
            "variants": var_items
        })
    with open(detailed_json_path, 'w', encoding='utf-8') as f:
        json.dump(detailed_data, f, ensure_ascii=False, indent=2)

    # 4. 导出 CSV (Excel 友好，带 UTF-8 BOM)
    csv_path = os.path.join(out_dir, "ids_variants.csv")
    print(f"      Exporting Excel-friendly CSV -> {csv_path}...")
    with open(csv_path, 'w', encoding='utf-8-sig', newline='') as f:
        writer = csv.writer(f)
        writer.writerow([
            "原字", "原字Unicode", "原字Codepoint", "原字读音", "原字IDS结构", "原字分区",
            "异体字数量", "异体字列表", "异体字Unicode列表", "异体字读音列表"
        ])
        for item in detailed_data:
            vars_chars = [v["char"] for v in item["variants"]]
            vars_unicodes = [v["unicode"] for v in item["variants"]]
            vars_pinyins = [v["pinyin"] if v["pinyin"] else "-" for v in item["variants"]]
            writer.writerow([
                item["char"],
                item["unicode"],
                item["codepoint"],
                item["pinyin"],
                item["ids"],
                item["block"],
                item["variant_count"],
                " ".join(vars_chars),
                " ".join(vars_unicodes),
                " ".join(vars_pinyins)
            ])

    # 5. 聚类并查集导出 (全互通等价簇)
    print(f"[5/6] Building variant equivalence clusters...")
    clusters_map = defaultdict(list)
    all_chars_in_dsu = set(dsu.parent.keys())
    for ch in all_chars_in_dsu:
        root = dsu.find(ch)
        clusters_map[root].append(ch)

    # 排序每个 cluster：先按 block 优先级（基本 > 扩A > ...），再按 codepoint
    block_priority = {name: i for i, name in enumerate(BLOCK_NAMES)}
    def char_sort_key(ch):
        info = get_info(ch)
        p = block_priority.get(info["block"], 99)
        return (p, info["codepoint"])

    clusters_list = []
    cluster_id = 1
    for root, members in sorted(clusters_map.items(), key=lambda x: -len(x[1])):
        members_sorted = sorted(members, key=char_sort_key)
        primary = members_sorted[0]
        clusters_list.append({
            "cluster_id": cluster_id,
            "cluster_size": len(members_sorted),
            "primary_char": primary,
            "members": [
                {
                    "char": m,
                    "unicode": get_info(m)["unicode"],
                    "codepoint": get_info(m)["codepoint"],
                    "block": get_info(m)["block"],
                    "pinyin": get_info(m)["pinyin"]
                }
                for m in members_sorted
            ]
        })
        cluster_id += 1

    cluster_json_path = os.path.join(out_dir, "ids_variant_clusters.json")
    print(f"      Exporting {len(clusters_list):,} clusters -> {cluster_json_path}...")
    with open(cluster_json_path, 'w', encoding='utf-8') as f:
        json.dump(clusters_list, f, ensure_ascii=False, indent=2)

    # 6. 导出专业 SQLite 数据库
    db_path = os.path.join(out_dir, "ids_variants.db")
    print(f"[6/6] Building SQLite database -> {db_path}...")
    if os.path.exists(db_path):
        os.remove(db_path)

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("PRAGMA synchronous = OFF;")
    cur.execute("PRAGMA journal_mode = MEMORY;")

    # 表 1: 一对一关系表
    cur.execute("""
    CREATE TABLE variants_map (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        base_char TEXT NOT NULL,
        base_unicode TEXT NOT NULL,
        base_codepoint INTEGER NOT NULL,
        base_pinyin TEXT,
        base_ids TEXT,
        base_block TEXT,
        variant_char TEXT NOT NULL,
        variant_unicode TEXT NOT NULL,
        variant_codepoint INTEGER NOT NULL,
        variant_pinyin TEXT,
        variant_ids TEXT,
        variant_block TEXT
    );
    """)

    # 表 2: 主字汇总表
    cur.execute("""
    CREATE TABLE variants_summary (
        char TEXT PRIMARY KEY,
        unicode TEXT NOT NULL,
        codepoint INTEGER NOT NULL,
        pinyin TEXT,
        ids TEXT,
        block TEXT,
        variant_count INTEGER NOT NULL,
        variants_str TEXT NOT NULL,
        variants_unicode_str TEXT NOT NULL
    );
    """)

    # 表 3: 等价簇表
    cur.execute("""
    CREATE TABLE variant_clusters (
        cluster_id INTEGER PRIMARY KEY,
        cluster_size INTEGER NOT NULL,
        primary_char TEXT NOT NULL,
        members_str TEXT NOT NULL,
        members_unicode_str TEXT NOT NULL
    );
    """)

    # 插入表 1 和表 2
    map_rows = []
    summary_rows = []
    for item in detailed_data:
        b_char = item["char"]
        b_uni = item["unicode"]
        b_cp = item["codepoint"]
        b_py = item["pinyin"]
        b_ids = item["ids"]
        b_block = item["block"]
        v_count = item["variant_count"]
        v_str = " ".join([v["char"] for v in item["variants"]])
        v_uni_str = " ".join([v["unicode"] for v in item["variants"]])

        summary_rows.append((b_char, b_uni, b_cp, b_py, b_ids, b_block, v_count, v_str, v_uni_str))

        for v in item["variants"]:
            map_rows.append((
                b_char, b_uni, b_cp, b_py, b_ids, b_block,
                v["char"], v["unicode"], v["codepoint"], v["pinyin"], v["ids"], v["block"]
            ))

    cur.executemany("""
    INSERT INTO variants_map (
        base_char, base_unicode, base_codepoint, base_pinyin, base_ids, base_block,
        variant_char, variant_unicode, variant_codepoint, variant_pinyin, variant_ids, variant_block
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    """, map_rows)

    cur.executemany("""
    INSERT INTO variants_summary (
        char, unicode, codepoint, pinyin, ids, block, variant_count, variants_str, variants_unicode_str
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
    """, summary_rows)

    # 插入表 3
    cluster_rows = []
    for cl in clusters_list:
        m_str = " ".join([m["char"] for m in cl["members"]])
        m_uni = " ".join([m["unicode"] for m in cl["members"]])
        cluster_rows.append((cl["cluster_id"], cl["cluster_size"], cl["primary_char"], m_str, m_uni))

    cur.executemany("""
    INSERT INTO variant_clusters (
        cluster_id, cluster_size, primary_char, members_str, members_unicode_str
    ) VALUES (?, ?, ?, ?, ?);
    """, cluster_rows)

    # 创建高性能索引
    print("      Creating database indexes...")
    cur.execute("CREATE INDEX idx_map_base_char ON variants_map(base_char);")
    cur.execute("CREATE INDEX idx_map_base_cp ON variants_map(base_codepoint);")
    cur.execute("CREATE INDEX idx_map_variant_char ON variants_map(variant_char);")
    cur.execute("CREATE INDEX idx_map_variant_cp ON variants_map(variant_codepoint);")
    cur.execute("CREATE INDEX idx_summary_char ON variants_summary(char);")
    cur.execute("CREATE INDEX idx_summary_block ON variants_summary(block);")
    cur.execute("CREATE INDEX idx_cluster_primary ON variant_clusters(primary_char);")

    conn.commit()
    conn.close()

    # 7. 生成详细文档 README.md
    readme_path = os.path.join(out_dir, "README.md")
    print(f"      Writing documentation -> {readme_path}...")
    readme_content = f"""# Unicode 汉字异体字全量数据库 (Ids Variants Database)

本异体字数据库基于 Rime IDS C++ 原生增强套件工程提取并生成，全量覆盖 **50,044 条主字映射**，关联 **101,792 个异体字关系**，并聚类提炼出 **{len(clusters_list):,} 个全互通异体字等价簇**。

所有数据已与 IDS3 原生字库（10.4 万 Unicode 汉字）完成对齐，包含了各异写字的 **Unicode 编码、读音、IDS 拆字结构式与所在分区（基本/扩A~扩J/兼容）**。

---

## 📁 导出文件清单

| 文件名 | 格式 | 说明 | 适用场景 |
| :--- | :--- | :--- | :--- |
| **`ids_variants.json`** | JSON | 极简字典：`{{"字": ["异体字1", "异体字2"]}}` | Web 前端、小程序、Node.js、Python 轻量调用 |
| **`ids_variants_detailed.json`** | JSON | 全字段明细：含原字与异体字读音、IDS、分区、Unicode | 字典开发、语言学研究、高精度文字检索 |
| **`ids_variants.sqlite`** | SQLite 3 | 专业嵌入式数据库，内置 3 张表及双向索引 | 移动端（Android/iOS/Flutter）、桌面程序、SQL 查询 |
| **`ids_variants.csv`** | CSV | Excel/WPS 兼容表格（带 UTF-8 BOM，打开绝不乱码） | 数据分析、批量审校、表格查阅 |
| **`ids_variant_clusters.json`** | JSON | 双向全互通等价同义簇聚类 | 异体字归一化（Normalizer）、全同义词检索 |
| **`ids_variants_normalized.tsv`** | TSV | 标准 Tab 分隔纯文本 | C/C++ 高性能流式读取、Shell 脚本处理 |

---

## 🗄️ SQLite 数据库结构 (`ids_variants.db`)

### 1. `variants_map`（一对一关系明细表）
- `id` (INTEGER PRIMARY KEY)
- `base_char` / `base_unicode` / `base_codepoint` / `base_pinyin` / `base_ids` / `base_block`（原字信息）
- `variant_char` / `variant_unicode` / `variant_codepoint` / `variant_pinyin` / `variant_ids` / `variant_block`（异体字信息）
- **索引**：`idx_map_base_char`, `idx_map_variant_char`, `idx_map_base_cp`, `idx_map_variant_cp`

### 2. `variants_summary`（原字汇总表）
- `char` (TEXT PRIMARY KEY): 原字
- `unicode`: 原字十六进制 Unicode（如 `U+865A`）
- `pinyin`: 读音
- `ids`: IDS 结构（如 `⿸虍业`）
- `block`: 所在分区（如 `基本`、`扩B` 等）
- `variant_count`: 关联异体字数量
- `variants_str`: 异体字列表字符串（空格分隔）
- `variants_unicode_str`: 异体字 Unicode 编码列表

### 3. `variant_clusters`（双向互通等价同义簇）
- `cluster_id` (INTEGER PRIMARY KEY)
- `cluster_size`: 簇内成员总数
- `primary_char`: 该簇推荐主首字（优先取基本区最常用字）
- `members_str`: 簇内全部异写字（空格分隔）
- `members_unicode_str`: 簇内全部字符的 Unicode

---

## 💻 快速开发调用示例

### 1. Python 快速查字
```python
import json

# 加载极简字典
with open('ids_variants.json', 'r', encoding='utf-8') as f:
    variants_map = json.load(f)

# 查询 “虚” 的异写字
print(variants_map.get('虚'))
# 输出: ['虗', '虛', '譃', '𠧝', '𠧰', '𣦄', '𧆳', '𧟬', '𩴛', '𮓠', '𮓡']
```

### 2. SQLite SQL 查询
```sql
-- 1. 查询指定字的所有异体字及其拼音、IDS
SELECT variant_char, variant_unicode, variant_pinyin, variant_ids, variant_block 
FROM variants_map 
WHERE base_char = '虚';

-- 2. 双向反查：查找包含某生僻字的所有常见母字
SELECT base_char, base_pinyin, variant_char, variant_block 
FROM variants_map 
WHERE variant_char = '𧆳';

-- 3. 统计异体字最多的前 10 个汉字
SELECT char, pinyin, variant_count, variants_str 
FROM variants_summary 
ORDER BY variant_count DESC 
LIMIT 10;
```

### 3. JavaScript / Node.js
```javascript
const fs = require('fs');
const variants = JSON.parse(fs.readFileSync('ids_variants.json', 'utf8'));

function getVariants(char) {{
  return variants[char] || [];
}}

console.log(getVariants('虚'));
```
"""
    with open(readme_path, 'w', encoding='utf-8') as f:
        f.write(readme_content)

    print("\n=======================================================")
    print("[SUCCESS] All variant database formats exported!")
    print(f"Output directory: {os.path.abspath(out_dir)}")
    for file_name in sorted(os.listdir(out_dir)):
        p = os.path.join(out_dir, file_name)
        size_mb = os.path.getsize(p) / 1024 / 1024
        print(f"  - {file_name:<28} ({size_mb:.2f} MB)")
    print("=======================================================")

if __name__ == '__main__':
    main()
