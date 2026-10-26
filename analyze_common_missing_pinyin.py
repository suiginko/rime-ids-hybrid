import struct
import collections

with open('data/ids_data.bin', 'rb') as f:
    blob = f.read()

# 解析 header
magic, ver, flags, max_cp, num_chars, num_keys, num_sec = struct.unpack('<4sHHIIII', blob[:24])
sections = {}
st = 32
for i in range(num_sec):
    sec_type, pad, off, length = struct.unpack('<IIQQ', blob[st + i * 24: st + (i + 1) * 24])
    sections[sec_type] = (off, length)

# 10: TB, 11: PB, 12: KB
tb_off, _ = sections[10]
pb_off, _ = sections[11]
kb_off, _ = sections[12]

# 读取所有 tokens
num_tokens = struct.unpack('<H', blob[tb_off: tb_off + 2])[0]
tokens = []
pos = tb_off + 2
for _ in range(num_tokens):
    tlen = struct.unpack('<H', blob[pos: pos + 2])[0]
    tstr = blob[pos + 2: pos + 2 + tlen].decode('utf-8')
    cp = struct.unpack('<I', blob[pos + 2 + tlen: pos + 2 + tlen + 4])[0]
    tokens.append((tstr, cp))
    pos += 2 + tlen + 4

# 读取 py_map: py -> list of token_id
num_py = struct.unpack('<H', blob[pb_off: pb_off + 2])[0]
py_map = collections.defaultdict(list)
pos = pb_off + 2
token_to_pys = collections.defaultdict(list)
for _ in range(num_py):
    pylen = struct.unpack('<H', blob[pos: pos + 2])[0]
    pystr = blob[pos + 2: pos + 2 + pylen].decode('utf-8')
    pos += 2 + pylen
    n_ids = struct.unpack('<H', blob[pos: pos + 2])[0]
    pos += 2
    ids = struct.unpack(f'<{n_ids}H', blob[pos: pos + n_ids * 2])
    pos += n_ids * 2
    py_map[pystr] = ids
    for tid in ids:
        token_to_pys[tid].append(pystr)

# 读取 keys 及其 full_cnt 覆盖字数
num_k = struct.unpack('<I', blob[kb_off: kb_off + 4])[0]
keys = {}
pos = kb_off + 4
for _ in range(num_k):
    klen = struct.unpack('<H', blob[pos: pos + 2])[0]
    kstr = blob[pos + 2: pos + 2 + klen].decode('utf-8')
    pos += 2 + klen
    ho, hc, fo, fc, kind = struct.unpack('<IIIIB', blob[pos: pos + 17])
    pos += 17
    if '*' not in kstr:
        keys[kstr] = fc

print(f"Total tokens: {num_tokens}, Total valid pinyins in py_map: {len(py_map)}")

# 找出所有覆盖字数 > 100，但是 token_to_pys 为空或者读音非常生僻/反人类的常见部件
missing = []
for tid, (tstr, tcp) in enumerate(tokens):
    pys = token_to_pys.get(tid, [])
    cnt = keys.get(tstr, 0)
    missing.append((tstr, tcp, cnt, pys))

# 按覆盖字数排序
missing.sort(key=lambda x: x[2], reverse=True)

print("\nTop 40 most frequent components with NO pinyin in ids_data.bin:")
count = 0
for tstr, tcp, cnt, pys in missing:
    if not pys and cnt >= 100:
        count += 1
        print(f"{count}. '{tstr}' (U+{tcp:04X}): count={cnt}")
        if count >= 40:
            break
