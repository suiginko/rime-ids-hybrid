-- ids_hybrid_composer.lua - Rime 全功能汉字拼音混合检字中枢 (v4.1)
-- 架构升级：
-- 1. [双拼/全拼双向无缝支持] 全面覆盖小鹤双拼 (flypy) 与自然码 (zrm) 双拼编码（如 kz 自动映射 kou、ho 映射 huo、uv 映射 shui、gj 映射 gan 等），支持双拼字母直接回车作为部件检索！
-- 2. [汉字部件与拼音混合检字] 输入部件时，空格/数字键直接选汉字部件，按回车直接将字母编码（如 mu、kz、ho）作为部件上屏参与检字，完美支持汉字+全拼/双拼混合检索！
-- 2. [显式呈现大写 O] 键入单字 O 时显式呈现并提示“〔汉字部件检字〕”，杜绝空白与表情混淆；后边继续键入编码时无缝平滑隐匿 O；
-- 3. [纯大写 O 回车直出] 尚未输入部件时单打 O 按回车直接上屏大写 O，检字完成时按回车选字；
-- 4. [彻底消灭黑块与单引号] 检字态 preedit 采用 Unicode 零宽空格 (U+200B)，彻底消除黑块背景与单引号泄露，界面绝对纯净！
-- 5. [全量 400 拼音+频次覆盖] 离线倒排索引包含全量 10.4 万字汉字部件与全部 400 个拼音音节及重复频次（如 huo*2 自动命中 炎、谈、淡、焱；mu*2 自动命中 林、森）；
-- 6. [全套元数据注释无方括号] 检字目标字输出读音 xiā、IDS结构 ⿰目害、Unicode 码与分区，与 I 模式完全看齐；
-- 7. [按键深度适配] 1-5 / 分号精准选字，严格放行 7890 供万象用作 1234 声调！

local search = require("ids_hybrid_search")
local wanxiang = nil
pcall(function() wanxiang = require("wanxiang/wanxiang") end)

local M = {
    editor = {},
    segmentor = {},
    translator = {},
    filter = {}
}

local kAccepted = 1
local kNoop = 2
local property = "ids_hybrid_components"
local kDefaultTips = "〔汉字部件检字〕"
local kZeroWidthSpace = "\xE2\x80\x8B" -- Unicode 零宽空格 U+200B

-- 动态感知万象当前激活的输入法类型 (flypy/zrm/mspy/sogou/pinyin)
local function get_im_type(env)
    if wanxiang and wanxiang.get_input_method_type then
        local res = wanxiang.get_input_method_type(env)
        if res and res ~= "unknown" then
            return res
        end
    end
    -- 备用兜底：从 speller/algebra 检查
    local config = env.engine.schema.config
    local algebra = config:get_list("speller/algebra")
    if algebra then
        for i = 0, algebra.size - 1 do
            local v = algebra:get_value_at(i)
            local rule = v and v:get_string()
            if rule then
                if rule:find("小鹤双拼", 1, true) or rule:find("Ⅲ", 1, true) then return "flypy" end
                if rule:find("自然码", 1, true) or rule:find("Ⅱ", 1, true) then return "zrm" end
                if rule:find("微软双拼", 1, true) or rule:find("Ⅳ", 1, true) then return "mspy" end
                if rule:find("搜狗双拼", 1, true) or rule:find("Ⅴ", 1, true) then return "sogou" end
            end
        end
    end
    return "flypy"
end

local function configure(env)
    local config = env.engine.schema.config
    env.prefix = config:get_string("ids_hybrid/prefix") or "O"
    env.tag = config:get_string("ids_hybrid/tag") or "ids_search_hybrid"
    env.direct_prefix = config:get_string("ids_search/prefix") or "I"
    env.tips = config:get_string("ids_hybrid/tips") or kDefaultTips
    env.page_size = config:get_int("menu/page_size") or 5
    env.im_type = get_im_type(env)
end

local function is_active(ctx, prefix)
    return ctx.input:sub(1, #prefix) == prefix and not ctx:get_option("ascii_mode")
end

-- 解析当前状态：返回 components 数组、codes 数组、以及当前未确认的 pending 拼音
local function state(ctx, trigger)
    local components, codes = {}, {}
    local prop = ctx:get_property(property) or ""
    for text, code in prop:gmatch("([^\t\n]+)\t([^\n]+)\n") do
        components[#components + 1], codes[#codes + 1] = text, code
    end
    local expected_prefix = trigger
    for _, code in ipairs(codes) do
        expected_prefix = expected_prefix .. code .. "'"
    end
    if ctx.input:sub(1, #expected_prefix) ~= expected_prefix then
        return {}, {}, ctx.input:sub(#trigger + 1)
    end
    return components, codes, ctx.input:sub(#expected_prefix + 1)
end

local function save(ctx, components, codes)
    local encoded = {}
    for i, text in ipairs(components) do
        encoded[i] = text .. "\t" .. codes[i] .. "\n"
    end
    ctx:set_property(property, table.concat(encoded))
end

local function kind(cand)
    if not cand then return nil end
    return cand:get_genuine().type
end

-------------------------------------------------------------------------------
-- 1. Segmentor: 动态分段与提示区常驻
-------------------------------------------------------------------------------
M.segmentor.init = configure

function M.segmentor.func(segmentation, env)
    local ctx = env.engine.context
    if not is_active(ctx, env.prefix) then return true end

    local start = segmentation:get_current_start_position()
    if start >= #segmentation.input then return false end

    local input = segmentation.input
    local prefix_end = (start == 0 and #env.prefix) or (start + 1)
    local is_prefix = (start == 0) or (input:sub(start + 1, start + 1) == "'")

    local components, _, pending = state(ctx, env.prefix)

    local seg
    if is_prefix and prefix_end < #input then
        seg = Segment(start, prefix_end)
        seg.tags = Set({"phony"})
        seg.status = "kConfirmed"
    elseif is_prefix then
        seg = Segment(start, #input)
        if start == 0 then
            -- 处于未确认的前缀段（单打大写 O）：仅保留 env.tag，严禁附加 ids_search 标签，绝不误触发 C++ 输出 ou 读音候选！
            seg.tags = Set({env.tag})
        else
            -- 处于检字结果段（末尾单引号）：附带 ids_search 标签，激活万象放行白名单，豁免生僻字字符集过滤
            seg.tags = Set({env.tag, "ids_search"})
        end
    else
        -- 处于字母或部件编码段
        local next_quote = input:find("'", start + 1)
        if next_quote then
            seg = Segment(start, next_quote - 1)
            seg.status = "kConfirmed"
            seg.tags = Set({"confirmed_component"})
        else
            seg = Segment(start, #input)
            seg.tags = Set({"abc", "hanzi_component"})
        end
    end

    -- 始终在编码右侧提示区展示“〔汉字部件检字〕”
    seg.prompt = env.tips or kDefaultTips

    segmentation:add_segment(seg)
    return false
end

-------------------------------------------------------------------------------
-- 2. Translator: 产生全量检字候选（带全套结构、读音与Unicode信息，彻底消灭黑块与单引号外泄）
-------------------------------------------------------------------------------
function M.translator.init(env)
    configure(env)
    local rime_dir = rime_api.get_user_data_dir()
    search.init(
        rime_dir .. "/lua/ids_dict.bin",
        rime_dir .. "/lua/ids_offset.bin",
        rime_dir .. "/lua/ids_info.bin",
        rime_dir .. "/lua/ids_info_idx.bin"
    )
end

function M.translator.func(_, seg, env)
    if not seg:has_tag(env.tag) then return end
    local components, _, pending = state(env.engine.context, env.prefix)
    if pending == "" and #components > 0 then
        local im_type = get_im_type(env)
        local results = search.find(components, im_type)
        for _, text in ipairs(results) do
            local comment = search.get_comment(text)
            -- 采用 ids_search 原生类型，获得万象全套 filter 最高级直接放行通道，杜绝注释篡改
            local cand = Candidate("ids_search", seg.start, seg._end, text, comment)
            -- 核心：利用 librime composition 内部 \t (caret_placeholder) 原生特性：
            -- 1. \t 置于首位使得 preedit.sel_start == preedit.sel_end，小狼毫判定高亮范围为零，彻底消灭残留黑块；
            -- 2. 预编辑文本追加为空，前置已确认部件自然呈现为“金色”，绝不重复最后一个部件！
            cand.preedit = "\t"
            yield(cand)
        end
    end
end

-------------------------------------------------------------------------------
-- 3. Filter: 部件单字过滤与万象自定义短语置顶
-------------------------------------------------------------------------------
function M.filter.init(env)
    configure(env)
    pcall(function()
        env.custom_translator = Component.Translator(env.engine, "custom_phrase", "script_translator")
    end)
    pcall(function()
        local config = env.engine.schema.config
        env.insert_position = math.max(1, config:get_int("abbrev_phrase/insert_position") or 2)
        env.max_candidates = math.max(0, config:get_int("abbrev_phrase/max_candidates") or 3)
        env.abbrev_translator = Component.Translator(env.engine, "abbrev_phrase", "script_translator")
    end)
end

function M.filter.fini(env)
    if env.custom_translator and type(env.custom_translator.disconnect) == "function" then
        env.custom_translator:disconnect()
    end
    if env.abbrev_translator and type(env.abbrev_translator.disconnect) == "function" then
        env.abbrev_translator:disconnect()
    end
    env.custom_translator = nil
    env.abbrev_translator = nil
end

function M.filter.func(input, env)
    local ctx = env.engine.context
    local searching = is_active(ctx, env.prefix)
    local seg = searching and not ctx.composition:empty() and ctx.composition:back()

    -- 非检字模式或非部件选择段，直接放行
    if not searching or not seg or not seg:has_tag("hanzi_component") then
        for cand in input:iter() do
            yield(cand)
        end
        return
    end

    local code = ctx.input:sub(seg.start + 1, seg._end)
    local seen_texts = {}
    local custom_cands = {}

    -- 1. 查询万象自定义短语（custom_phrase），置顶用户定义的单字（如干、得、再、有、大、酉等）
    -- 必须满足完整编码匹配（c._end == seg._end），严禁前缀残码匹配（杜绝打 kz 误匹配 k 的可字并吞噬 z）
    if env.custom_translator and code ~= "" then
        local ok, trans = pcall(function() return env.custom_translator:query(code, seg) end)
        if ok and trans then
            for c in trans:iter() do
                local text = c.text
                if c._end == seg._end and c.type ~= "sentence"
                    and text and utf8.len(text) == 1 and not seen_texts[text] and not text:find("[\t\r\n ]") then
                    seen_texts[text] = true
                    local comp_cand = Candidate("hanzi_component", seg.start, seg._end, text, c.comment or "")
                    comp_cand.preedit = c.preedit
                    custom_cands[#custom_cands + 1] = comp_cand
                end
            end
        end
    end

    -- 2. 查询万象简码（abbrev_phrase，支持前置单字简码，同样严格要求整码匹配）
    local abbrev_cands = {}
    local abbrev_enabled = ctx:get_option("abbrev")
    if abbrev_enabled and env.abbrev_translator and env.max_candidates and env.max_candidates > 0 and code ~= "" then
        local ok, trans = pcall(function() return env.abbrev_translator:query(code, seg) end)
        if ok and trans then
            for c in trans:iter() do
                local text = c.text
                if c._end == seg._end and c.type ~= "sentence"
                    and text and utf8.len(text) == 1 and not seen_texts[text] and not text:find("[\t\r\n ]") then
                    seen_texts[text] = true
                    local comp_cand = Candidate("hanzi_component", seg.start, seg._end, text, c.comment or "")
                    comp_cand.preedit = c.preedit
                    abbrev_cands[#abbrev_cands + 1] = comp_cand
                    if #abbrev_cands >= env.max_candidates then break end
                end
            end
        end
    end

    local emitted = 0
    -- 首先输出自定义短语置顶候选
    for _, cc in ipairs(custom_cands) do
        emitted = emitted + 1
        yield(cc)
    end

    local abbrev_done = (#abbrev_cands == 0)
    local insert_pos = env.insert_position or 2

    -- 遍历常规翻译器输出的候选，过滤单字并去重
    for cand in input:iter() do
        local typ = kind(cand)
        if typ == "ids_search" or typ == "hanzi_result" then
            yield(cand)
        elseif cand._end == seg._end and utf8.len(cand.text) == 1 and not cand.text:find("[\t\r\n ]") then
            -- 达到插入位时输出简码
            if not abbrev_done and emitted >= insert_pos - 1 then
                abbrev_done = true
                for _, ac in ipairs(abbrev_cands) do
                    emitted = emitted + 1
                    yield(ac)
                end
            end

            -- 去重输出常规单字候选
            if not seen_texts[cand.text] then
                seen_texts[cand.text] = true
                local comp_cand = Candidate("hanzi_component", cand.start, cand._end, cand.text, cand.comment)
                comp_cand.preedit = cand.preedit
                comp_cand.quality = cand.quality
                emitted = emitted + 1
                yield(comp_cand)
            end
        end
    end

    -- 兜底输出剩余简码（若常规候选数量不足以触发插入位）
    if not abbrev_done then
        for _, ac in ipairs(abbrev_cands) do
            yield(ac)
        end
    end
end

-------------------------------------------------------------------------------
-- 4. Editor (Processor): 按键交互、大写 O 回车直出与部件拦截
-------------------------------------------------------------------------------
function M.editor.init(env)
    configure(env)
    local ctx = env.engine.context
    local rime_dir = rime_api.get_user_data_dir()
    search.init(
        rime_dir .. "/lua/ids_dict.bin",
        rime_dir .. "/lua/ids_offset.bin",
        rime_dir .. "/lua/ids_info.bin",
        rime_dir .. "/lua/ids_info_idx.bin"
    )

    env.before = ctx.select_notifier:connect(function(context)
        if not is_active(context, env.prefix) then return end
        local cand = context:get_selected_candidate()
        local typ = kind(cand)
        if typ ~= "hanzi_component" and typ ~= "ids_search" and typ ~= "hanzi_result" then return end
        env.selection = {
            type = typ,
            text = cand.text,
            component = cand:get_genuine().text
        }
        env.auto_commit = context:get_option("_auto_commit")
        context:set_option("_auto_commit", false)
    end, 0)

    env.after = ctx.select_notifier:connect(function(context)
        local selected = env.selection
        if not selected then return end
        env.selection = nil
        context:set_option("_auto_commit", env.auto_commit)

        if selected.type == "ids_search" or selected.type == "hanzi_result" then
            env.engine:commit_text(selected.text)
            context:clear()
        else
            local components, codes, pending = state(context, env.prefix)
            components[#components + 1] = selected.component
            codes[#codes + 1] = pending
            save(context, components, codes)
            -- 推入单引号分隔符，驱动新段并保留所有已选部件！
            context:push_input("'")
        end
    end)

    env.update = ctx.update_notifier:connect(function(context)
        if is_active(context, env.prefix) then
            local seg = not context.composition:empty() and context.composition:back()
            if seg then
                seg.prompt = env.tips or kDefaultTips
            end
        elseif context:get_property(property) ~= "" then
            context:set_property(property, "")
        end
    end)
end

function M.editor.fini(env)
    for _, name in ipairs({"before", "after", "update"}) do
        if env[name] then env[name]:disconnect() end
    end
end

function M.editor.func(key, env)
    if key:release() then return kNoop end

    local ctx = env.engine.context
    local repr = key:repr()
    local code = key.keycode
    local is_composing = ctx:is_composing()

    -- 0. 方案 A 划选文本瞬时反查
    if not is_composing and (repr == "I" or (code == 0x49 and key:shift())) and not key:ctrl() and not key:alt() then
        local clip_path = "C:/Users/Hg/AppData/Roaming/Rime/ids_clip.txt"
        local f = io.open(clip_path, "r")
        if f then
            local text = f:read("*a")
            f:close()
            os.remove(clip_path)
            if text then
                text = text:gsub("[\r\n\t ]", "")
                if text ~= "" then
                    local full_input = env.direct_prefix .. text
                    ctx.input = full_input
                    pcall(function() ctx.caret_pos = #full_input end)
                    pcall(function() ctx.cursor_pos = #full_input end)
                    return kAccepted
                end
            end
        end
        return kNoop
    end

    if not is_active(ctx, env.prefix) then return kNoop end

    -- 1. 取消键
    if repr == "Escape" then
        ctx:clear()
        return kAccepted
    end

    -- 2. 回车键：
    if repr == "Return" then
        local components, codes, pending = state(ctx, env.prefix)
        -- A. 尚未开始检字（仅有单独大写 O）：回车直接上屏大写 O
        if #components == 0 and pending == "" then
            env.engine:commit_text(env.prefix)
            ctx:clear()
            return kAccepted
        end
        -- B. 正在输入部件编码（pending ~= ""）：回车直接将字母编码作为部件参与检字，不选首选字！
        if pending ~= "" then
            if not ctx.composition:empty() then
                ctx.composition:pop_back()
            end
            components[#components + 1] = pending
            codes[#codes + 1] = pending
            save(ctx, components, codes)
            ctx:push_input("'")
            return kAccepted
        end
        -- C. 若处于检字结果展示阶段（pending == ""）：回车确认选中字上屏
        if ctx:has_menu() and ctx:get_selected_candidate() then
            ctx:confirm_current_selection()
            return kAccepted
        end
        return kNoop
    end

    -- 3. 退格键：安全层级回退
    if repr == "BackSpace" then
        local components, codes, pending = state(ctx, env.prefix)
        if pending ~= "" then
            if #pending == 1 and #components > 0 then
                ctx.composition:pop_back()
                local separator = ctx.composition:back()
                if separator then
                    separator.tags = Set({env.tag})
                    separator.status = "kVoid"
                end
            end
            ctx:pop_input(1)
        elseif #components > 0 then
            table.remove(codes)
            table.remove(components)
            save(ctx, components, codes)
            ctx.composition:pop_back()
            if not ctx.composition:empty() then
                ctx.composition:back().status = "kGuess"
            end
            ctx:pop_input(1)
        else
            ctx:clear()
        end
        return kAccepted
    end

    -- 4. 数字键选字与分号次选：
    -- 严格限定为 1 ~ min(page_size, 6)；数字 7890 严格放行给万象用作声调！
    local page_size = env.page_size or 5
    local max_select_digit = math.min(page_size, 6)

    local digit = nil
    if repr:match("^[1-6]$") then
        local d = tonumber(repr)
        if d >= 1 and d <= max_select_digit then
            digit = d
        end
    elseif repr == "semicolon" then
        digit = 2 -- 分号次选
    end

    if digit and ctx:has_menu() then
        local seg = not ctx.composition:empty() and ctx.composition:back()
        if seg and seg.menu then
            local sel_index = seg.selected_index or 0
            local page_start = math.floor(sel_index / page_size) * page_size
            local target_index = page_start + (digit - 1)
            seg.menu:prepare(target_index + 1)
            if target_index < seg.menu:candidate_count() then
                if ctx:select(target_index) then
                    return kAccepted
                end
            end
        end
        return kAccepted
    end

    -- 5. 空格确认当前高亮候选
    if repr == "space" then
        if ctx:has_menu() and ctx:get_selected_candidate() then
            ctx:confirm_current_selection()
            return kAccepted
        end
    end

    -- 6. 字母输入：追加到输入串
    if repr:match("^[a-z]$") then
        if ctx.caret_pos ~= #ctx.input then
            ctx.caret_pos = #ctx.input
        end
        if not ctx.composition:empty() and ctx.composition:back():has_tag(env.tag) then
            ctx:clear_non_confirmed_composition()
        end
        ctx:push_input(repr)
        return kAccepted
    end

    -- 7. 翻页键与 7890 声调键放行
    if repr:match("^[7890]$")
        or repr == "Up" or repr == "Down"
        or repr == "Page_Up" or repr == "Page_Down"
        or repr == "comma" or repr == "period" or repr == "minus" or repr == "equal" then
        return kNoop
    end

    return kNoop
end

return M
