# -*- coding: utf-8 -*-
import os, struct, time

src_index = r'C:\Users\Hg\Documents\antigravity\idsc++\release\ids_search_release\3.【部件读音与原始数据(供查阅)】\ids_index.txt'
dict_data_path = r'C:\Users\Hg\AppData\Roaming\Rime\lua\ids_dict.bin'
offset_index_path = r'C:\Users\Hg\AppData\Roaming\Rime\lua\ids_offset.bin'

t0 = time.time()
comp_chars = {}
py_comps = {}

# 1. 读取原始数据：汉字部件表与拼音部件映射
with open(src_index, 'r', encoding='utf-8') as fin:
    for line in fin:
        parts = line.strip().split('\t')
        if line.startswith('@py\t'):
            if len(parts) >= 3:
                py_comps[parts[1]] = parts[2].split()
        elif len(parts) == 2:
            comp_chars[parts[0]] = parts[1]

# 2. 写入倒排主文件 ids_dict.bin 并记录 offsets
# 保持纯净：只存储汉字部件与标准全拼音节，完全不硬编码任何双拼
offsets = {}
with open(dict_data_path, 'wb') as fbin:
    # 2.1 写入所有汉字部件（含 '木'、'木*2'、'木*3' 等）
    for comp, chars_str in comp_chars.items():
        raw_bytes = chars_str.encode('utf-8')
        pos = fbin.tell()
        fbin.write(raw_bytes)
        length = len(raw_bytes)
        offsets[comp] = (pos, length)

    # 2.2 写入标准全拼音节对应汉字倒排
    for py, comps in py_comps.items():
        # 单频次 pinyin
        seen = set()
        py_chars_list = []
        for c in comps:
            if c in comp_chars:
                for ch in comp_chars[c]:
                    if ch not in seen:
                        seen.add(ch)
                        py_chars_list.append(ch)
        if py_chars_list:
            raw_bytes = ''.join(py_chars_list).encode('utf-8')
            pos = fbin.tell()
            fbin.write(raw_bytes)
            offsets[py] = (pos, len(raw_bytes))

        # 重复频次全拼（如 'huo*2'、'mu*2'、'gan*2'）
        for n in [2, 3]:
            py_multi = f'{py}*{n}'
            seen_m = set()
            m_list = []
            for c in comps:
                cn = f'{c}*{n}'
                if cn in comp_chars:
                    for ch in comp_chars[cn]:
                        if ch not in seen_m:
                            seen_m.add(ch)
                            m_list.append(ch)
            if m_list:
                raw_bytes = ''.join(m_list).encode('utf-8')
                pos = fbin.tell()
                fbin.write(raw_bytes)
                offsets[py_multi] = (pos, len(raw_bytes))

# 3. 将偏移量打包为二进制索引 ids_offset.bin
with open(offset_index_path, 'wb') as fidx:
    fidx.write(struct.pack('<I', len(offsets)))
    for comp, (pos, length) in offsets.items():
        comp_bytes = comp.encode('utf-8').ljust(8, b'\x00')
        fidx.write(struct.pack('<8sII', comp_bytes, pos, length))

print(f'Done in {time.time()-t0:.2f}s:')
print(f'Generated ids_dict.bin: {os.path.getsize(dict_data_path)} bytes ({os.path.getsize(dict_data_path)/1024/1024:.2f} MB)')
print(f'Generated ids_offset.bin: {os.path.getsize(offset_index_path)} bytes (total keys: {len(offsets)})')
