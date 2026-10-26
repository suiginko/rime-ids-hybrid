-- rime.lua
-- 全局 librime-lua 入口初始化文件

-- 启用 Lua 5.4 官方原生分代垃圾回收模式 (Generational GC)
pcall(function()
    if _G.collectgarbage then
        _G.collectgarbage("generational", 20, 100)
    end
end)

-- 方案 A: 划选文本瞬时反查处理器
pcall(function()
    ids_reverse_lookup = require("ids_reverse_lookup")
    if _G.wanxiang and type(_G.wanxiang) == "table" then
        _G.wanxiang.ids_reverse_lookup = ids_reverse_lookup
    end
end)
