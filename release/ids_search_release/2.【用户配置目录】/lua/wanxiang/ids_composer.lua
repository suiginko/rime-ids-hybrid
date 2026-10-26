-- ids_composer.lua - 方案B：万象编码区内嵌部件组装与Tab一键求交检字处理器
-- 功能规范：
-- 1. 启动组装：按下 Control+i（或大写 I），激活【部件组装模式】；
-- 2. 原生万象辅助码打字：在组装态下，输入拼音完全由万象原生词库与直接辅助码提供候选（如 jiu 选 九，mu 选 木）；
-- 3. 空格/数字选字进区不上屏：按空格或数字键选字，选中的汉字部件直接进入内部组装区，绝不上屏污染外部应用；
-- 4. Tab 键一键求交：组装完毕后（如已组装【九木】），按下 Tab 键秒切【ids检字求交态】，弹出合体字候选（如【染】）；
-- 5. 随时双向切换：在检字态按 Tab 可切回组装态继续追加部件；在检字态按空格选字直接上屏最终字！

local kAccepted = 1
local kNoop = 2
local ok, wanxiang = pcall(require, "wanxiang/wanxiang")
if ok and wanxiang and wanxiang.RIME_PROCESS_RESULTS then
    kAccepted = wanxiang.RIME_PROCESS_RESULTS.kAccepted
    kNoop = wanxiang.RIME_PROCESS_RESULTS.kNoop
end

local M = {}

-- 组装器状态机
local state = {
    active = false,       -- 组装器是否处于激活状态
    mode = "input",       -- "input" (部件组装态) 或 "search" (检字求交态)
    components = {},      -- 已确认的汉字部件列表，如 {"九", "木"}
}

local function log_debug(msg)
    pcall(function()
        local f = io.open("C:/Users/Hg/AppData/Roaming/Rime/ids_debug.log", "a")
        if f then
            f:write(os.date("%Y-%m-%d %H:%M:%S") .. " [Composer] " .. tostring(msg) .. "\n")
            f:close()
        end
    end)
end

-- 严密判断是否按下了 Control+i
local function is_ctrl_i(key)
    if not key:ctrl() then return false end
    local repr = key:repr()
    local code = key.keycode
    return repr == "Control+i" or repr == "Control+I"
        or code == 0x69 or code == 0x49 or code == 9 or code == 0x09
end

-- 获取当前候选词文本（兼容空格、数字键1-5、分号次选）
local function get_candidate_text(ctx, key, page_size)
    if not ctx or not ctx.composition or ctx.composition:empty() then
        return nil
    end
    local seg = ctx.composition:back()
    if not seg then return nil end
    page_size = page_size or 5

    local repr = key:repr()
    local code = key.keycode
    local is_space = (repr == "space" or code == 32 or code == 0x20)

    if is_space then
        local cand = ctx:get_selected_candidate()
        if cand and cand.text and cand.text ~= "" then
            return cand.text
        end
        if seg.get_candidate_at then
            local c = seg:get_candidate_at(seg.selected_index or 0)
            if c and c.text then return c.text end
        end
    else
        local digit = nil
        if code >= 49 and code <= 57 then digit = code - 48 end
        if code >= 0xFFB1 and code <= 0xFFB9 then digit = code - 0xFFB0 end
        if repr == "semicolon" or code == 59 or code == 0x3B then digit = 2 end
        if not digit and tonumber(repr) then digit = tonumber(repr) end

        if digit and digit >= 1 and digit <= page_size then
            local sel_idx = seg.selected_index or 0
            local page = math.floor(sel_idx / page_size)
            local target_idx = page * page_size + (digit - 1)
            if seg.get_candidate_at then
                local c = seg:get_candidate_at(target_idx)
                if c and c.text then return c.text end
            end
        end
    end
    return nil
end

function M.init(env)
    local config = env.engine.schema.config
    env.prefix = config:get_string("ids_search/prefix") or "I"
    env.page_size = config:get_int("menu/page_size") or 5
end

function M.fini(env)
end

function M.func(key, env)
    if key:release() then
        return kNoop
    end

    local ctx = env.engine.context
    local repr = key:repr()
    local code = key.keycode
    local is_composing = ctx:is_composing()

    -- -------------------------------------------------------------
    -- 0. 启动组装器：按 Control+i 或大写 I
    -- -------------------------------------------------------------
    if not state.active then
        if is_ctrl_i(key) then
            state.active = true
            state.mode = "input"
            state.components = {}
            log_debug("Activated Composer by Control+i! Mode=input")
            return kAccepted
        end

        if not is_composing and (repr == "I" or (code == 0x49 and key:shift())) and not key:ctrl() and not key:alt() then
            state.active = true
            state.mode = "input"
            state.components = {}
            log_debug("Activated Composer by 'I'! Mode=input")
            return kAccepted
        end

        return kNoop
    end

    -- -------------------------------------------------------------
    -- 1. 组装器已激活状态下的全局键控制 (Esc 取消 / Tab 切换)
    -- -------------------------------------------------------------

    -- 1.1 按 Escape 彻底退出组装器
    if repr == "Escape" then
        log_debug("Composer cancelled by Escape")
        state.active = false
        state.mode = "input"
        state.components = {}
        ctx:clear()
        return kAccepted
    end

    -- 1.2 按 Tab 键：在【部件组装态】与【检字求交态】之间随时切换！
    if repr == "Tab" or repr == "Shift+Tab" then
        if state.mode == "input" then
            -- 如果输入框里还有正在打的拼音（未按空格选字），一并吸纳进组装区
            if ctx.input and ctx.input ~= "" then
                table.insert(state.components, ctx.input)
            end

            if #state.components == 0 then
                -- 还没有部件，转为纯手动检字
                state.mode = "search"
                ctx.input = env.prefix
                ctx.cursor_pos = #env.prefix
                log_debug("Tab toggle -> search (empty components)")
                return kAccepted
            end

            -- 切换至【检字求交态】
            state.mode = "search"
            local query = env.prefix .. table.concat(state.components, "")
            ctx.input = query
            ctx.cursor_pos = #query
            log_debug("Tab toggle -> search! Query=" .. query)
            return kAccepted
        else
            -- 从【检字求交态】切换回【部件组装态】
            state.mode = "input"
            ctx:clear()
            log_debug("Tab toggle -> input! Preserved components: " .. table.concat(state.components, ", "))
            return kAccepted
        end
    end

    -- -------------------------------------------------------------
    -- 2. 模式 A：【部件组装态】(使用万象原生输入与辅助码，选字进区不上屏)
    -- -------------------------------------------------------------
    if state.mode == "input" then
        -- 2.1 候选词选择（空格、数字键1-5、分号次选）：吸纳汉字进组装区，绝不上屏！
        if is_composing and ctx:has_menu() then
            local cand_text = get_candidate_text(ctx, key, env.page_size)
            if cand_text and cand_text ~= "" then
                table.insert(state.components, cand_text)
                log_debug("Component added: '" .. cand_text .. "' -> all: " .. table.concat(state.components, ", "))
                
                -- 清空当前拼音段，留在组装器内等待打下一个部件
                ctx:clear()
                return kAccepted
            end
        end

        -- 2.2 退格键 BackSpace 处理
        if repr == "BackSpace" then
            if is_composing and ctx.input and #ctx.input > 0 then
                -- 还在拼写当前部件拼音，交由万象正常退格
                return kNoop
            else
                -- 拼音为空时，退掉组装区上一个确认的汉字部件
                if #state.components > 0 then
                    local removed = table.remove(state.components)
                    log_debug("Component removed: '" .. tostring(removed) .. "' -> remaining: " .. table.concat(state.components, ", "))
                    return kAccepted
                else
                    -- 已经没有部件了，退出组装器
                    state.active = false
                    state.mode = "input"
                    state.components = {}
                    log_debug("Composer closed by BackSpace")
                    return kAccepted
                end
            end
        end

        -- 2.3 动态提示：将当前已组装的汉字部件直观显示在候选窗口顶栏
        if is_composing and ctx.composition and not ctx.composition:empty() then
            local seg = ctx.composition:back()
            if seg then
                if #state.components > 0 then
                    seg.prompt = "〔部件: " .. table.concat(state.components, " ") .. " | 按Tab检字〕"
                else
                    seg.prompt = "〔部件组装态 | 按Tab检字〕"
                end
            end
        end

        -- 其它所有输入键（a-z, 辅助码分号, 翻页等）全部放行给万象原生处理！
        return kNoop
    end

    -- -------------------------------------------------------------
    -- 3. 模式 B：【检字求交态】(以 I 开头，由 C++ ids_search_translator 求交)
    -- -------------------------------------------------------------
    if state.mode == "search" then
        -- 3.1 选词上屏（空格、数字键1-5、分号次选）：直接将合体字上屏到外部应用，完成闭环！
        if is_composing and ctx:has_menu() then
            local cand_text = get_candidate_text(ctx, key, env.page_size)
            if cand_text and cand_text ~= "" then
                log_debug("Final character chosen: '" .. cand_text .. "' -> committing!")
                state.active = false
                state.mode = "input"
                state.components = {}
                
                ctx:clear()
                env.engine:commit_text(cand_text)
                return kAccepted
            end
        end

        -- 3.2 检字态下的退格键
        if repr == "BackSpace" then
            if ctx.input and #ctx.input > #env.prefix then
                local last_offset = utf8.offset(ctx.input, -1)
                if last_offset then
                    local new_input = ctx.input:sub(1, last_offset - 1)
                    ctx.input = new_input
                    ctx.cursor_pos = #new_input
                    return kAccepted
                end
            else
                -- 退回到组装态
                state.mode = "input"
                ctx:clear()
                return kAccepted
            end
        end

        -- 3.3 检字态下的字母追加 (支持输入拼音过滤检字候选)
        local code = key.keycode
        if not key:ctrl() and not key:alt() and ((code >= 0x61 and code <= 0x7A) or (code >= 0x41 and code <= 0x5A) or code == 0x2A or code == 0x2F) then
            local ch = string.char(code):lower()
            local new_input = ctx.input .. ch
            ctx.input = new_input
            ctx.cursor_pos = #new_input
            return kAccepted
        end

        return kNoop
    end

    return kNoop
end

return M
