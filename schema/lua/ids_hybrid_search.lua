-- ids_hybrid_search.lua - 全量 10.4 万汉字部件倒排极速求交与元数据模块 (v4.3)
-- 架构升级：
-- 1. [三大黄金排序准则]：
--    - 准则 1：优先展示“用完所打部件”（零剩余未用部件）的字，多余部件严格降级；
--    - 准则 2：部件消费与防虚假复用模型（如检索“沐木”，“木”被视作新加部件，单木字如湘/莯被扣除优先级）；
--    - 准则 3：部件顺序正序优先（正序 > 逆序，如 沐木->淋 优先于 𣒑）；
-- 2. 彻底解耦：ids_dict.bin 与 ids_offset.bin 保持纯净（仅存汉字部件与标准全拼），零冗余硬编码；
-- 3. 动态双拼解码：运行时结合万象原生 input_method_type (flypy/zrm/mspy/sogou等)，在内存中动态将双拼编码转化为合法全拼；
-- 4. 极速消歧与位图倒排：利用 offsets 中的 400 个全拼合法音节表进行毫秒级自动消歧与交集检索。

local M = {}

local dict_file = nil
local offsets = {}

local info_file = nil
local info_idx_file = nil

local loaded = false

-- IDS 结构符定义
local IDS_OPS = {
    ["⿰"] = true, ["⿱"] = true, ["⿲"] = true, ["⿳"] = true,
    ["⿴"] = true, ["⿵"] = true, ["⿶"] = true, ["⿷"] = true,
    ["⿸"] = true, ["⿹"] = true, ["⿺"] = true, ["⿻"] = true
}

-- 等价部首归一化映射 (水->氵, 人->亻, 火->灬 等)
local COMP_ALIASES = {
    ["水"] = "氵", ["⺡"] = "氵", ["氺"] = "氵",
    ["火"] = "灬", ["⺣"] = "灬",
    ["人"] = "亻", ["𠆢"] = "亻", ["⺅"] = "亻",
    ["手"] = "扌", ["龵"] = "扌",
    ["心"] = "忄", ["⺖"] = "忄", ["⺗"] = "忄",
    ["肉"] = "月", ["⺼"] = "月", ["⺝"] = "月",
    ["艸"] = "艹", ["⺾"] = "艹", ["⻀"] = "艹",
    ["示"] = "礻", ["⺬"] = "礻",
    ["衣"] = "衤", ["⺭"] = "衤", ["𧘇"] = "衤",
    ["金"] = "钅", ["釒"] = "钅", ["⻐"] = "钅",
    ["犬"] = "犭", ["⺲"] = "犭",
    ["辵"] = "辶", ["⻌"] = "辶", ["⻍"] = "辶",
    ["阜"] = "阝", ["邑"] = "阝", ["⻖"] = "阝", ["⻗"] = "阝",
}

-- 基础原子部首表 (无需再拆到笔画)
local ATOMIC_COMPS = {
    ["木"]=true, ["氵"]=true, ["水"]=true, ["火"]=true, ["灬"]=true, ["土"]=true, ["金"]=true, ["钅"]=true,
    ["日"]=true, ["月"]=true, ["目"]=true, ["口"]=true, ["人"]=true, ["亻"]=true, ["手"]=true, ["扌"]=true,
    ["心"]=true, ["忄"]=true, ["女"]=true, ["子"]=true, ["艹"]=true, ["言"]=true, ["讠"]=true, ["石"]=true,
    ["田"]=true, ["山"]=true, ["刀"]=true, ["刂"]=true, ["力"]=true, ["又"]=true, ["十"]=true, ["大"]=true,
    ["小"]=true, ["工"]=true, ["弓"]=true, ["广"]=true, ["门"]=true, ["马"]=true, ["鸟"]=true, ["鱼"]=true,
    ["虫"]=true, ["犭"]=true, ["犬"]=true, ["辶"]=true, ["宀"]=true, ["冖"]=true, ["穴"]=true, ["竹"]=true,
    ["⺮"]=true, ["米"]=true, ["糸"]=true, ["纟"]=true, ["车"]=true, ["足"]=true, ["⻊"]=true, ["雨"]=true,
    ["页"]=true, ["酉"]=true, ["贝"]=true, ["走"]=true, ["身"]=true, ["辛"]=true, ["辰"]=true, ["邑"]=true,
    ["阝"]=true, ["阜"]=true, ["方"]=true, ["斤"]=true, ["止"]=true, ["歹"]=true, ["殳"]=true, ["毛"]=true,
    ["氏"]=true, ["气"]=true, ["白"]=true, ["皮"]=true, ["皿"]=true, ["矢"]=true, ["示"]=true, ["礻"]=true,
    ["禾"]=true, ["立"]=true, ["羽"]=true, ["舟"]=true, ["艮"]=true, ["见"]=true, ["角"]=true, ["谷"]=true,
    ["豆"]=true, ["豕"]=true, ["豸"]=true, ["赤"]=true, ["革"]=true, ["音"]=true, ["风"]=true, ["飞"]=true,
    ["食"]=true, ["饣"]=true, ["首"]=true, ["香"]=true, ["骨"]=true, ["鬼"]=true, ["黾"]=true, ["鼎"]=true,
    ["鼓"]=true, ["鼠"]=true, ["鼻"]=true, ["齐"]=true, ["齿"]=true, ["龙"]=true, ["龟"]=true,
}

-- 零声母表 (小鹤/自然码/微软等主流双拼)
local ZERO_VOWELS = {
    ["aa"] = "a",  ["ai"] = "ai", ["an"] = "an", ["ah"] = "ang", ["ao"] = "ao",
    ["ee"] = "e",  ["ei"] = "ei", ["en"] = "en", ["eg"] = "eng", ["er"] = "er",
    ["oo"] = "o",  ["ou"] = "ou",
    -- 微软双拼零声母 (以 o 引导)
    ["oa"] = "a",  ["oi"] = "ai", ["oj"] = "an", ["oh"] = "ang",
    ["oe"] = "e",  ["ow"] = "ei", ["of"] = "en", ["og"] = "eng", ["or"] = "er",
}

-- 声母映射
local SHUANGPIN_INITS = {
    flypy = { v = "zh", i = "ch", u = "sh" },
    zrm   = { v = "zh", i = "ch", u = "sh" },
    mspy  = { v = "zh", i = "ch", u = "sh" },
    sogou = { v = "zh", i = "ch", u = "sh" },
    abc   = { v = "zh", i = "ch", u = "sh" },
}

-- 韵母映射 (候选展开，结合合法音节自动消歧)
local SHUANGPIN_FINALS = {
    flypy = {
        q = {"iu"}, w = {"ei"}, r = {"uan"}, t = {"ue", "ve"}, y = {"un"},
        p = {"ie"}, d = {"ai"}, f = {"en"}, g = {"eng"}, h = {"ang"},
        j = {"an"}, k = {"uai", "ing"}, l = {"uang", "iang"}, z = {"ou"},
        x = {"ua", "ia"}, c = {"ao"}, v = {"ui", "v"}, b = {"in"},
        n = {"iao"}, m = {"ian"}, s = {"iong", "ong"}, o = {"uo", "o"},
        u = {"u"}, i = {"i"}, a = {"a"}, e = {"e"}
    },
    zrm = {
        q = {"iu"}, w = {"ua", "ia"}, r = {"uan"}, t = {"ue", "ve"}, y = {"uai", "ing"},
        p = {"un"}, d = {"uang", "iang"}, f = {"en"}, g = {"eng"}, h = {"ang"},
        j = {"an"}, k = {"ao"}, l = {"ai"}, z = {"ou"},
        x = {"ia"}, c = {"ch"}, v = {"ui", "v"}, b = {"in"},
        n = {"in"}, m = {"ian"}, s = {"iong", "ong"}, o = {"uo", "o"},
        u = {"u"}, i = {"i"}, a = {"a"}, e = {"e"}
    },
    mspy = {
        q = {"iu"}, w = {"ia", "ua"}, r = {"er", "uan"}, t = {"ue", "ve"}, y = {"uai", "v"},
        p = {"un"}, d = {"uang", "iang"}, f = {"en"}, g = {"eng"}, h = {"ang"},
        j = {"an"}, k = {"ao"}, l = {"ai"}, z = {"ou"},
        x = {"ia"}, c = {"ao"}, v = {"ui"}, b = {"in"},
        n = {"in"}, m = {"ian"}, s = {"iong", "ong"}, o = {"uo", "o"},
        u = {"u"}, i = {"i"}, a = {"a"}, e = {"e"}
    }
}
SHUANGPIN_FINALS.sogou = SHUANGPIN_FINALS.zrm

-- 动态双拼转全拼核心算法：利用 offsets 中的拼音表自动验证
local function decode_shuangpin(sp, scheme)
    if not sp or #sp ~= 2 or not sp:match("^%a%a$") then return sp end
    sp = sp:lower()
    scheme = scheme or "flypy"
    if scheme == "pinyin" or scheme == "unknown" then return sp end

    -- 1. 优先查零声母表
    if ZERO_VOWELS[sp] then
        local zero_py = ZERO_VOWELS[sp]
        if offsets[zero_py] then
            return zero_py
        end
    end

    local c1 = sp:sub(1, 1)
    local c2 = sp:sub(2, 2)

    local init_map = SHUANGPIN_INITS[scheme] or SHUANGPIN_INITS.flypy
    local final_map = SHUANGPIN_FINALS[scheme] or SHUANGPIN_FINALS.flypy

    local init = init_map[c1] or c1
    local cand_finals = final_map[c2]

    if not cand_finals then
        return sp
    end

    -- 2. 遍历候选韵母，结合 offsets 中的合法音节表消歧
    for _, fin in ipairs(cand_finals) do
        local py = init .. fin
        -- 特殊规范微调：如 j/q/x + ve/ue -> jue/que/xue
        if (init == "j" or init == "q" or init == "x" or init == "y") and fin == "ve" then
            py = init .. "ue"
        elseif (init == "j" or init == "q" or init == "x" or init == "y") and fin == "v" then
            py = init .. "u"
        end

        if offsets[py] then
            return py
        end
    end

    return sp
end

function M.init(dict_path, offset_path, info_path, info_idx_path)
    if loaded then return true end

    -- 1. 加载部件倒排偏移索引 (纯净全量全拼与汉字部件)
    local fidx = io.open(offset_path, "rb")
    if fidx then
        local hdr = fidx:read(4)
        if hdr and #hdr >= 4 then
            local count = string.unpack("<I4", hdr)
            for i = 1, count do
                local rec = fidx:read(16) -- 8字节 key, 4字节 pos, 4字节 len
                if not rec or #rec < 16 then break end
                local comp_raw, pos, len = string.unpack("<c8I4I4", rec)
                local comp = comp_raw:gsub("%z+$", "")
                offsets[comp] = {pos, len}
            end
        end
        fidx:close()
    end

    -- 2. 打开倒排字典主文件
    dict_file = io.open(dict_path, "rb")

    -- 3. 打开汉字元数据直寻址索引与数据文件
    if info_path and info_idx_path then
        info_file = io.open(info_path, "rb")
        info_idx_file = io.open(info_idx_path, "rb")
    end

    loaded = true
    return true
end

-- 获取单个汉字的元数据注释 (如: xiā ⿰目害 778E 基本，无拼音时: ⿻丅𠃍 323B0 扩J)
function M.get_comment(ch)
    if not info_file or not info_idx_file or not ch or ch == "" then
        return ""
    end
    local cp = utf8.codepoint(ch)
    if not cp or cp >= 0x34000 then
        return ""
    end

    info_idx_file:seek("set", cp * 6)
    local raw_idx = info_idx_file:read(6)
    if not raw_idx or #raw_idx < 6 then
        return ""
    end

    local pos, len = string.unpack("<I4I2", raw_idx)
    if len == 0 then
        return ""
    end

    info_file:seek("set", pos)
    local comment = info_file:read(len)
    if comment and comment:sub(1, 1) == "[" then
        comment = comment:gsub("^%[([^%]]+)%]", "%1")
    end
    return comment or ""
end

-- 解析单个字符的 IDS 注释信息 (获取 ids_str, block, leaves)
local function parse_char_info(ch)
    local comment = M.get_comment(ch)
    if not comment or comment == "" then
        return { ids = "", block = "", leaves = {ch} }
    end
    
    local ids_str = ""
    local block = ""
    for p in comment:gmatch("%S+") do
        local has_op = false
        for _, c in utf8.codes(p) do
            if IDS_OPS[utf8.char(c)] then
                has_op = true
                break
            end
        end
        if has_op then
            ids_str = p
        elseif p == "基本" or p:match("^扩[A-J]$") or p == "兼容区" then
            block = p
        end
    end
    
    local leaves = {}
    if ids_str ~= "" then
        for _, c in utf8.codes(ids_str) do
            local char_c = utf8.char(c)
            if not IDS_OPS[char_c] then
                table.insert(leaves, COMP_ALIASES[char_c] or char_c)
            end
        end
    end
    if #leaves == 0 then
        table.insert(leaves, COMP_ALIASES[ch] or ch)
    end
    
    return { ids = ids_str, block = block, leaves = leaves }
end

-- 递归展开原子部件 (遇到常用部首或深度超过2层时停止)
local function get_atomic_decomposition(ch, cache, depth)
    ch = COMP_ALIASES[ch] or ch
    if cache and cache[ch] then
        return cache[ch]
    end
    depth = depth or 0
    if depth > 2 or ATOMIC_COMPS[ch] then
        local r = { ch }
        if cache then cache[ch] = r end
        return r
    end
    
    local info = parse_char_info(ch)
    local leaves = info.leaves
    if #leaves <= 1 then
        local r = { ch }
        if cache then cache[ch] = r end
        return r
    end
    
    local res = {}
    for _, c in ipairs(leaves) do
        if c == ch then
            table.insert(res, c)
        else
            local sub = get_atomic_decomposition(c, cache, depth + 1)
            for _, sc in ipairs(sub) do
                table.insert(res, sc)
            end
        end
    end
    if cache then cache[ch] = res end
    return res
end

-- 三大黄金准则打分排序算法
local function rank_candidates(cands, components)
    if not cands or #cands <= 1 or not components or #components == 0 then
        return cands
    end

    local cache = {}
    local user_atomics = {}
    local user_atomic_seq = {}
    local norm_input_comps = {}

    for _, c in ipairs(components) do
        local norm_c = COMP_ALIASES[c] or c
        table.insert(norm_input_comps, norm_c)
        local atomics = get_atomic_decomposition(norm_c, cache, 0)
        for _, a in ipairs(atomics) do
            user_atomics[a] = (user_atomics[a] or 0) + 1
            table.insert(user_atomic_seq, a)
        end
    end

    local limit = math.min(#cands, 500)
    local scored = {}

    for i = 1, limit do
        local ch = cands[i]
        local info = parse_char_info(ch)
        local cand_leaves = info.leaves
        local cand_atomics_list = get_atomic_decomposition(ch, cache, 0)
        
        local cand_atomics = {}
        for _, a in ipairs(cand_atomics_list) do
            cand_atomics[a] = (cand_atomics[a] or 0) + 1
        end

        -- 准则 2：部件满足度检查与新增部件数量门禁 (防虚假复用)
        local satisfied = true
        local missing_count = 0
        for a, req_count in pairs(user_atomics) do
            local avail = cand_atomics[a] or 0
            if avail < req_count then
                satisfied = false
                missing_count = missing_count + (req_count - avail)
            end
        end

        -- 准则 1：零剩余部件度量 (是否恰好用完所打部件)
        local extra_count = 0
        for a, avail in pairs(cand_atomics) do
            local req = user_atomics[a] or 0
            if avail > req then
                extra_count = extra_count + (avail - req)
            end
        end

        -- 准则 3：部件顺序一致性 (正序优先于逆序)
        local ordered_bonus = 0
        local match_macro = (#cand_leaves == #norm_input_comps)
        if match_macro then
            for idx = 1, #norm_input_comps do
                if cand_leaves[idx] ~= norm_input_comps[idx] then
                    match_macro = false
                    break
                end
            end
        end

        local match_macro_rev = false
        if not match_macro and (#cand_leaves == #norm_input_comps) then
            match_macro_rev = true
            local n = #norm_input_comps
            for idx = 1, n do
                if cand_leaves[idx] ~= norm_input_comps[n - idx + 1] then
                    match_macro_rev = false
                    break
                end
            end
        end

        if match_macro then
            ordered_bonus = 20000000
        elseif match_macro_rev then
            ordered_bonus = 10000000
        else
            -- 原子部件出现顺序比对
            if #user_atomic_seq == #cand_atomics_list then
                local seq_match = true
                for idx = 1, #user_atomic_seq do
                    if user_atomic_seq[idx] ~= cand_atomics_list[idx] then
                        seq_match = false
                        break
                    end
                end
                if seq_match then
                    ordered_bonus = 15000000
                end
            end
        end

        -- 分层打分
        local score = 0
        if satisfied then
            if extra_count == 0 then
                score = 50000000 + ordered_bonus
            else
                score = 20000000 - extra_count * 500000 + math.floor(ordered_bonus / 2)
            end
        else
            score = - missing_count * 5000000 - extra_count * 500000
        end

        -- 分区加权：基本区常用字加权置顶
        if info.block == "基本" then
            score = score + 2000000
        elseif info.block == "扩A" then
            score = score + 1000000
        end

        table.insert(scored, { ch = ch, score = score, index = i })
    end

    table.sort(scored, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.index < b.index
    end)

    local res = {}
    for _, item in ipairs(scored) do
        table.insert(res, item.ch)
    end
    for i = limit + 1, #cands do
        table.insert(res, cands[i])
    end
    return res
end

-- 获取单个 key 对应的全部汉字列表 (支持 '火' 或 '火*2')
local function get_key_chars(key)
    if not loaded or not dict_file then return {} end
    local info = offsets[key]
    if not info then return {} end

    dict_file:seek("set", info[1])
    local raw = dict_file:read(info[2])
    if not raw then return {} end

    local chars = {}
    for _, c in utf8.codes(raw) do
        table.insert(chars, utf8.char(c))
    end
    return chars
end

-- 多部件求交与减法运算 (如 佩-亻=𫥞, 泰-氺=𡗗, 森-木=林)
function M.find(components, im_type)
    if not components or #components == 0 then return {} end

    -- 0. 减法功能支持：分离正向部件与减法部件 (如 "佩", "-亻" 或 "佩-亻")
    local pos_comps = {}
    local neg_comps = {}
    local idx_comp = 1
    while idx_comp <= #components do
        local raw = components[idx_comp]:gsub("[\r\n\t ]", "")
        if raw ~= "" then
            if raw == "-" then
                if idx_comp + 1 <= #components then
                    table.insert(neg_comps, components[idx_comp + 1]:gsub("[\r\n\t ]", ""))
                    idx_comp = idx_comp + 1
                end
            elseif raw:sub(1, 1) == "-" then
                table.insert(neg_comps, raw:sub(2))
            elseif raw:find("-", 1, true) then
                for part in raw:gmatch("[^-]+") do
                    if #pos_comps == 0 then
                        table.insert(pos_comps, part)
                    else
                        table.insert(neg_comps, part)
                    end
                end
            else
                table.insert(pos_comps, raw)
            end
        end
        idx_comp = idx_comp + 1
    end

    -- 若触发了减法模式 (包含需要去掉的部件)
    if #neg_comps > 0 then
        local sub_results = {}
        local seen_sub = {}

        -- 对 neg_comps 进行规范化与动态双拼转译
        local norm_neg = {}
        for _, n in ipairs(neg_comps) do
            local dec_n = n
            if #n == 2 and n:match("^%a%a$") then
                dec_n = decode_shuangpin(n, im_type)
            end
            table.insert(norm_neg, COMP_ALIASES[dec_n] or dec_n)
        end

        -- 阶段 1：直接子结构精确扣除 (如 佩 - 亻 = 𫥞, 泰 - 氺 = 𡗗, 森 - 木 = 林, 休 - 亻 = 木)
        for _, p in ipairs(pos_comps) do
            local info = parse_char_info(p)
            local leaves = {}
            for _, l in ipairs(info.leaves) do
                table.insert(leaves, l)
            end
            local matched_count = 0
            local remains = {}
            local used_neg = {}
            for _, leaf in ipairs(leaves) do
                local norm_leaf = COMP_ALIASES[leaf] or leaf
                local found = false
                for idx, neg in ipairs(norm_neg) do
                    if not used_neg[idx] and (neg == norm_leaf or neg == leaf) then
                        used_neg[idx] = true
                        matched_count = matched_count + 1
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(remains, leaf)
                end
            end

            if matched_count == #norm_neg and #remains == 1 then
                local hit = remains[1]
                if not seen_sub[hit] then
                    table.insert(sub_results, hit)
                    seen_sub[hit] = true
                end
            end
        end

        if #sub_results > 0 then
            return sub_results
        end
    end

    -- 1. 规范化处理与动态双拼转译
    local normalized_comps = {}
    for _, raw_comp in ipairs(pos_comps) do
        local comp = raw_comp:gsub("[\r\n\t ]", "")
        if comp ~= "" then
            -- 若已直接命中（如汉字部件或合法全拼），直接采用
            if offsets[comp] then
                table.insert(normalized_comps, comp)
            elseif #comp == 2 and comp:match("^%a%a$") then
                -- 动态调用万象双拼算法解算全拼 (如 kz -> kou, uv -> shui, ho -> huo)
                local full_py = decode_shuangpin(comp, im_type)
                table.insert(normalized_comps, full_py)
            else
                table.insert(normalized_comps, comp)
            end
        end
    end

    -- 2. 统计各部件出现的频次
    local counts = {}
    local order = {}
    for _, comp in ipairs(normalized_comps) do
        if not counts[comp] then
            counts[comp] = 1
            table.insert(order, comp)
        else
            counts[comp] = counts[comp] + 1
        end
    end

    -- 3. 构造查询 keys 列表 (如 '火*2' 或 '木')
    local query_keys = {}
    for _, comp in ipairs(order) do
        local n = counts[comp]
        if n > 1 then
            local k_multi = string.format("%s*%d", comp, n)
            if offsets[k_multi] then
                table.insert(query_keys, k_multi)
            else
                table.insert(query_keys, comp)
            end
        else
            table.insert(query_keys, comp)
        end
    end

    -- 4. 取第 1 个 key 的倒排列表
    local first = get_key_chars(query_keys[1])
    if #first == 0 or #query_keys == 1 then
        return first
    end

    local set = {}
    for _, ch in ipairs(first) do
        set[ch] = true
    end

    -- 5. 逐一取交集
    for i = 2, #query_keys do
        local next_chars = get_key_chars(query_keys[i])
        local next_set = {}
        for _, ch in ipairs(next_chars) do
            if set[ch] then
                next_set[ch] = true
            end
        end
        set = next_set
    end

    -- 6. 保留交集
    local results = {}
    for _, ch in ipairs(first) do
        if set[ch] then
            table.insert(results, ch)
            set[ch] = nil
        end
    end

    -- 7. 黄金排序：三大准则打分（用完所打部件置顶 > 防虚假复用 > 正序优先）
    if #results > 1 and #normalized_comps > 0 then
        results = rank_candidates(results, normalized_comps)
    end

    return results
end

return M
