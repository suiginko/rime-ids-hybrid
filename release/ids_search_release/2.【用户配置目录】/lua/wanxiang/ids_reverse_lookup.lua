-- ids_reverse_lookup.lua - 方案A：鼠标划选文本瞬时反查处理器
-- 功能规范：
-- 1. 用户高亮选中任何文字（如【九木】或【九uv木】），按下 Ctrl+i；
-- 2. IdsDaemon 瞬时将选中文本投递至 ids_clip.txt 并发送 I 唤起 Rime；
-- 3. 本处理器接收到 I 后，直接装载为【I九木】，由 C++ ids_search_translator 毫秒级求交检字；
-- 4. 选字直接上屏（如【染】），替换原选中文本！

local kAccepted = 1
local kNoop = 2
local ok, wanxiang = pcall(require, "wanxiang/wanxiang")
if ok and wanxiang and wanxiang.RIME_PROCESS_RESULTS then
    kAccepted = wanxiang.RIME_PROCESS_RESULTS.kAccepted
    kNoop = wanxiang.RIME_PROCESS_RESULTS.kNoop
end

local M = {}

local function log_debug(msg)
    pcall(function()
        local f = io.open("C:/Users/Hg/AppData/Roaming/Rime/ids_debug.log", "a")
        if f then
            f:write(os.date("%Y-%m-%d %H:%M:%S") .. " [SelectionSearch] " .. tostring(msg) .. "\n")
            f:close()
        end
    end)
end

function M.init(env)
    local config = env.engine.schema.config
    env.prefix = config:get_string("ids_search/prefix") or "I"
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

    -- 检查是否为 I 触发（由 IdsDaemon 发送或用户手动敲击大写 I）
    if not is_composing and (repr == "I" or (code == 0x49 and key:shift())) and not key:ctrl() and not key:alt() then
        local clip_path = "C:/Users/Hg/AppData/Roaming/Rime/ids_clip.txt"
        local f = io.open(clip_path, "r")
        if f then
            local text = f:read("*a")
            f:close()
            os.remove(clip_path) -- 立即销毁，单次消费防残留！
            if text then
                text = text:gsub("[\r\n\t ]", "") -- 剔除前后空白换行
                if text ~= "" then
                    log_debug("Selection reverse lookup matched: text='" .. text .. "'")
                    local full_input = env.prefix .. text
                    ctx.input = full_input
                    ctx.cursor_pos = #full_input
                    return kAccepted
                end
            end
        end
        return kNoop
    end

    return kNoop
end

return M
