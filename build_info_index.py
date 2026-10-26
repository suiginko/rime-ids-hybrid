# -*- coding: utf-8 -*-
import os, struct

dump_path = r'C:\Users\Hg\Documents\antigravity\idsc++\release\ids_search_release\3.【部件读音与原始数据(供查阅)】\ids_data_dumped.txt'
info_bin_path = r'C:\Users\Hg\AppData\Roaming\Rime\lua\ids_info.bin'
info_idx_path = r'C:\Users\Hg\AppData\Roaming\Rime\lua\ids_info_idx.bin'

# 读取 ids_data_dumped.txt
# 每一行: 汉字 \t Unicode \t 读音 \t IDS结构 \t 分区 \t ...
max_cp = 0x33000 # 足够覆盖到 Ext-J

# 我们将所有 comment 拼接到 ids_info.bin，并在 ids_info_idx.bin 中保存每个 codepoint 的 (offset, len)
# 4字节 offset, 2字节 length -> 每个 codepoint 占 6 字节
idx_records = [(0, 0)] * max_cp

with open(dump_path, 'r', encoding='utf-8') as fin, open(info_bin_path, 'wb') as fbin:
    for line in fin:
        if line.startswith('#'): continue
        parts = line.strip().split('\t')
        if len(parts) >= 5:
            ch, ucode, py, ids_str, block = parts[0], parts[1], parts[2], parts[3], parts[4]
            cp = ord(ch)
            if cp < max_cp:
                # 构造标准注释: xiā ⿰目害 778E 基本 (去掉方括号，与 I 模式完全一致)
                # 去除 U+ 前缀
                hex_cp = ucode.replace('U+', '')
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

with open(info_idx_path, 'wb') as fidx:
    for pos, length in idx_records:
        fidx.write(struct.pack('<IH', pos, length))

print(f'ids_info.bin size: {os.path.getsize(info_bin_path)} bytes ({os.path.getsize(info_bin_path)/1024/1024:.2f} MB)')
print(f'ids_info_idx.bin size: {os.path.getsize(info_idx_path)} bytes ({os.path.getsize(info_idx_path)/1024/1024:.2f} MB)')

# 验证读取 '瞎'
cp_xia = ord('瞎')
with open(info_idx_path, 'rb') as fidx, open(info_bin_path, 'rb') as fbin:
    fidx.seek(cp_xia * 6)
    pos, length = struct.unpack('<IH', fidx.read(6))
    fbin.seek(pos)
    res = fbin.read(length).decode('utf-8')
    print(f"Comment for '瞎': {res}")
