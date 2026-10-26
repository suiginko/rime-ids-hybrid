-- ids_hybrid_search.lua - 全量 10.4 万汉字部件倒排极速求交与元数据模块 (v4.2)
-- 架构升级：
-- 1. 彻底解耦：ids_dict.bin 与 ids_offset.bin 保持纯净（仅存汉字部件与标准全拼），零冗余硬编码；
-- 2. 动态双拼解码：运行时结合万象原生 input_method_type (flypy/zrm/mspy/sogou等)，在内存中动态将双拼编码转化为合法全拼；
-- 3. 极速消歧与位图倒排：利用 offsets 中的 400 个全拼合法音节表进行毫秒级自动消歧与交集检索。

local M = {}

local dict_file = nil
local offsets = {}

local info_file = nil
local info_idx_file = nil

local loaded = false

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

-- 多部件求交 (自动按万象当前输入法类型动态转码并按频次合并如 火+火 -> 火*2，木+木+木 -> 木*3)
function M.find(components, im_type)
    if not components or #components == 0 then return {} end

    -- 1. 规范化处理与动态双拼转译
    local normalized_comps = {}
    for _, raw_comp in ipairs(components) do
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

    -- 6. 保留交集并返回
    local results = {}
    for _, ch in ipairs(first) do
        if set[ch] then
            table.insert(results, ch)
            set[ch] = nil
        end
    end

    return results
end

return M
