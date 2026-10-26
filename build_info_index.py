# -*- coding: utf-8 -*-
import os, struct

dump_path = r'C:\Users\Hg\Documents\antigravity\idsc++\release\ids_search_release\3.【部件读音与原始数据(供查阅)】\ids_data_dumped.txt'
info_bin_path = r'C:\Users\Hg\AppData\Roaming\Rime\lua\ids_info.bin'
info_idx_path = r'C:\Users\Hg\AppData\Roaming\Rime\lua\ids_info_idx.bin'

# 覆盖 Unicode 全量 CJK 字符集 (Ext-J 最大 codepoint 为 0x33479，设为 0x34000 确保 100% 容纳)
MAX_CP = 0x34000 # 212,992

idx_records = [(0, 0)] * MAX_CP
count_valid = 0

with open(dump_path, 'r', encoding='utf-8') as fin, open(info_bin_path, 'wb') as fbin:
    for line in fin:
        if line.startswith('#'): continue
        parts = line.strip().split('\t')
        if len(parts) >= 5:
            ch, ucode, py, ids_str, block = parts[0], parts[1], parts[2], parts[3], parts[4]
            cp = ord(ch)
            if cp < MAX_CP:
                # 构造标准注释: 与 C++ 原生实现完全对齐
                # 有拼音: "xiā ⿰目害 778E 基本"
                # 无拼音: "⿻丅𠃍 323B0 扩J"
                hex_cp = ucode.replace('U+', '').upper()
                comment_parts = []
                if py: comment_parts.append(py)
                if ids_str: comment_parts.append(ids_str)
                if hex_cp: comment_parts.append(hex_cp)
                if block: comment_parts.append(block)
                comment = ' '.join(comment_parts)
                raw_bytes = comment.encode('utf-8')
                
                pos = fbin.tell()
                fbin.write(raw_bytes)
                length = len(raw_bytes)
                idx_records[cp] = (pos, length)
                count_valid += 1

with open(info_idx_path, 'wb') as fidx:
    for pos, length in idx_records:
        fidx.write(struct.pack('<IH', pos, length))

print(f'Indexed {count_valid} characters (Max CP: {hex(MAX_CP)}).')
print(f'ids_info.bin size: {os.path.getsize(info_bin_path)} bytes ({os.path.getsize(info_bin_path)/1024/1024:.2f} MB)')
print(f'ids_info_idx.bin size: {os.path.getsize(info_idx_path)} bytes ({os.path.getsize(info_idx_path)/1024/1024:.2f} MB)')

# 抽样检验
for sample_cp in [ord('木'), ord('瞎'), 0x323B0, 0x33000, 0x33479]:
    pos, length = idx_records[sample_cp]
    with open(info_bin_path, 'rb') as fbin:
        fbin.seek(pos)
        res = fbin.read(length).decode('utf-8') if length > 0 else 'EMPTY'
        print(f"Comment for {hex(sample_cp)}: '{res}'")
