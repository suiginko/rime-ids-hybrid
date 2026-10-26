# -*- coding: utf-8 -*-
"""
pack_full_index.py - 全量打包 ids_index.bin 与同步 ids_index.txt
"""
import os
import struct
import collections

RADICAL_PREFERRED_ORDER = {
    'zhong': ['中', '重'],
    'zhe': [
        '乙', '乚', '乛', '𠃊', '𠃍', '𠃋', '𠃌',
        '㇕', '㇗', '㇄', '㇅', '㇆', '㇇', '㇈', '㇉', '㇊',
        '㇋', '㇌', '㇍', '㇎', '㇖', '㇘', '㇛', '㇜', '㇞',
        '㇟', '㇠', '㇡', '㇢', '㇂', '㇁', '亅', '㇃'
    ],
    'shui': ['氵', '水', '氺', '⺡', '冫'],
    'cao': ['艹', '艸', '⺾', '⻀'],
    'er': ['阝', '卩', '⻖', '⻗', '二', '儿', '耳'],
    'ren': ['亻', '人', '彳', '⺅', '𠆢'],
    'shou': ['扌', '手', '龵'],
    'huo': ['灬', '火', '⺣'],
    'xin': ['忄', '心', '⺖', '⺗'],
    'jin': ['钅', '金', '釒', '⻐'],
    'yan': ['讠', '言', '訁'],
    'si': ['纟', '糸', '糹', '⺰', '⺱'],
    'quan': ['犭', '犬', '⺲'],
    'zou': ['辶', '辵', '⻌', '⻍'],
    'wen': ['文', '攵', '夂', '夊', '亠', '⺙', '攴'],
    'dang': ['龸'],
    'xiao': ['小', '⺌'],
    'shan': ['山', '⺕'],
    'feng': ['丰', '龶'],
    'ge': ['鬲', '戈', '革'],
    'pan': ['爿', '丬'],
    'zhua': ['爪', '爫'],
    'chang': ['长', '長', '厂', '鬯', '⻑', '常', '镸'],
    'zhang': ['长', '長'],
    'ri': ['日', '曰', '冃'],
    'mao': ['毛', '冃', '冒', '矛', '卯'],
}

def main():
    print("Step 1: Reading @py mappings from data/ids_index.txt...")
    pinyin_to_comps = collections.defaultdict(list)
    with open('data/ids_index.txt', 'r', encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\r\n')
            if line.startswith('@py\t'):
                parts = line.split('\t')
                if len(parts) >= 3:
                    py = parts[1]
                    comps = parts[2].split()
                    pinyin_to_comps[py] = comps

    # Ensure preferred radical ordering
    for py, pref_list in RADICAL_PREFERRED_ORDER.items():
        existing = pinyin_to_comps.get(py, [])
        # Merge pref_list at front without duplicate
        new_list = list(pref_list)
        for c in existing:
            if c not in new_list:
                new_list.append(c)
        pinyin_to_comps[py] = new_list

    py_lines = []
    for py in sorted(pinyin_to_comps.keys()):
        comps = pinyin_to_comps[py]
        py_lines.append(f"@py\t{py}\t{' '.join(comps)}")

    print(f"Total @py lines: {len(py_lines)}")

    print("Step 2: Reading component postings from ../ids1.6/ids_index.txt...")
    comp_lines = []
    with open('../ids1.6/ids_index.txt', 'r', encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\r\n')
            if not line or line.startswith('@py'):
                continue
            parts = line.split('\t')
            if len(parts) >= 2:
                comp_lines.append((parts[0], parts[1]))

    print(f"Total component lines: {len(comp_lines)}")

    print("Step 3: Writing updated data/ids_index.txt...")
    with open('data/ids_index.txt', 'w', encoding='utf-8') as f:
        for pl in py_lines:
            f.write(pl + '\n')
        for comp, chars in comp_lines:
            f.write(f"{comp}\t{chars}\n")

    txt_size = os.path.getsize('data/ids_index.txt')
    print(f"data/ids_index.txt updated, size: {txt_size / 1024 / 1024:.2f} MB")

    print("Step 4: Packing data/ids_index.bin (IDX2 format)...")
    py_block = ('\n'.join(py_lines) + '\n').encode('utf-8')
    keys_dir = bytearray()
    postings_blob = bytearray()

    for k, val in comp_lines:
        k_bytes = k.encode('utf-8')
        count = len(val)
        offset = len(postings_blob) + 1  # 1-indexed
        cps = [ord(c) for c in val]
        postings_blob.extend(struct.pack(f'<{count}I', *cps))
        keys_dir.extend(struct.pack('<H', len(k_bytes)))
        keys_dir.extend(k_bytes)
        keys_dir.extend(struct.pack('<II', offset, count))

    header = struct.pack('<4sIII', b'IDX2', len(comp_lines), len(keys_dir), len(py_block))
    bin_output = "data/ids_index.bin"
    with open(bin_output, 'wb') as f:
        f.write(header)
        f.write(py_block)
        f.write(keys_dir)
        f.write(postings_blob)

    bin_size = os.path.getsize(bin_output)
    print(f"data/ids_index.bin updated, size: {bin_size / 1024 / 1024:.2f} MB")
    print("Done packing!")

if __name__ == '__main__':
    main()
