import struct

with open('data/ids_data.bin', 'rb') as f:
    blob = f.read()

sections = {}
st = 32
magic, ver, flags, max_cp, num_chars, num_keys, num_sec = struct.unpack('<4sHHIIII', blob[:24])
for i in range(num_sec):
    sec_type, pad, off, length = struct.unpack('<IIQQ', blob[st + i * 24: st + (i + 1) * 24])
    sections[sec_type] = (off, length)

id2cp_off, _ = sections[2]
hot_off, _ = sections[3]
cold_off_off, _ = sections[8]
cold_off, _ = sections[9]
id2cp = struct.unpack(f'<{num_chars}I', blob[id2cp_off: id2cp_off + num_chars * 4])
cp_to_id = {cp: i for i, cp in enumerate(id2cp)}

tb_off, _ = sections[10]
pb_off, _ = sections[11]
kb_off, _ = sections[12]
head_off_base, _ = sections[13]
small_off_base, _ = sections[14]
bits_off_base, _ = sections[15]

num_tokens = struct.unpack('<H', blob[tb_off: tb_off + 2])[0]
tokens = []
pos = tb_off + 2
for _ in range(num_tokens):
    tlen = struct.unpack('<H', blob[pos: pos + 2])[0]
    tstr = blob[pos + 2: pos + 2 + tlen].decode('utf-8')
    cp = struct.unpack('<I', blob[pos + 2 + tlen: pos + 2 + tlen + 4])[0]
    tokens.append((tstr, cp))
    pos += 2 + tlen + 4

num_py = struct.unpack('<H', blob[pb_off: pb_off + 2])[0]
py_map = {}
pos = pb_off + 2
for _ in range(num_py):
    pylen = struct.unpack('<H', blob[pos: pos + 2])[0]
    pystr = blob[pos + 2: pos + 2 + pylen].decode('utf-8')
    pos += 2 + pylen
    n_ids = struct.unpack('<H', blob[pos: pos + 2])[0]
    pos += 2
    ids = struct.unpack(f'<{n_ids}H', blob[pos: pos + n_ids * 2])
    pos += n_ids * 2
    py_map[pystr] = ids

num_k = struct.unpack('<I', blob[kb_off: kb_off + 4])[0]
keys = {}
pos = kb_off + 4
for _ in range(num_k):
    klen = struct.unpack('<H', blob[pos: pos + 2])[0]
    kstr = blob[pos + 2: pos + 2 + klen].decode('utf-8')
    pos += 2 + klen
    ho, hc, fo, fc, kind = struct.unpack('<IIIIB', blob[pos: pos + 17])
    pos += 17
    keys[kstr] = (ho, hc, fo, fc, kind)

# 查找所有包含 '屑' 的 key
xie_id = cp_to_id[ord('屑')]
for k, entry in keys.items():
    ho, hc, fo, fc, kind = entry
    # 检查 head
    h_start = head_off_base + ho * 4
    hids = struct.unpack(f'<{hc}I', blob[h_start: h_start + hc * 4])
    if xie_id in hids:
        print(f"Key '{k}' contains 屑 in HEAD (count={fc})")
