local lfs           = require "filesystem.local"
local imgui         = require "imgui"
local global_data   = require "common.global_data"
local setting       = import_package "ant.settings"
local serialize     = import_package "ant.serialize"

local ps = {
    id      = "ProjectSetting"
}

local default_tr_flags = imgui.flags.TreeNode{}
local default_win_flags= imgui.flags.Window{}
local default_tab_flags= imgui.flags.TabBar{"Reorderable", "AutoSelectNewTabs"}

local TreeNode      = imgui.widget.TreeNode
local TreePop       = imgui.widget.TreePop
local PropertyLabel = imgui.widget.PropertyLabel
local Checkbox      = imgui.widget.Checkbox
local BeginCombo    = imgui.widget.BeginCombo
local EndCombo      = imgui.widget.EndCombo
local Button        = imgui.widget.Button
local BeginDisabled = imgui.windows.BeginDisabled
local EndDisabled   = imgui.windows.EndDisabled
local BeginTabBar   = imgui.windows.BeginTabBar
local EndTabBar     = imgui.windows.EndTabBar
local BeginTabItem  = imgui.windows.BeginTabItem
local EndTabItem    = imgui.windows.EndTabItem
local BeginPopupModal=imgui.windows.BeginPopupModal
local EndPopup      = imgui.windows.EndPopup
local SameLine      = imgui.cursor.SameLine

local function Property(name, value, ctrltype)
    PropertyLabel(name)
    SameLine()
    return imgui.widget[ctrltype]("##"..name, value)
end

local function PropertyFloat(name, value)
    return Property(name, value, "DragFloat")
end

local function PropertyColor(name, value)
    return Property(name, value, "ColorEdit")
end

local function CheckProperty(name, value, enable, p, set_p)
    local _, result = Checkbox("##"..name, enable)
    SameLine()
    BeginDisabled(not result)
    
    if p(name, value) then
        set_p(value)
    end
    EndDisabled()

    return result
end

local function toRGBColor(dwColor)
    local r = dwColor & 0xff
    local g = (dwColor >> 8) & 0xff
    local b = (dwColor >> 16) & 0xff
    local a = (dwColor >> 24) & 0xff
    return {r/255.0, g/255.0, b/255.0, a/255.0}
end

local function toDWColor(rgbcolor)
    local r = math.floor(rgbcolor[1] * 255)
    local g = math.floor(rgbcolor[2] * 255)
    local b = math.floor(rgbcolor[3] * 255)
    local a = math.floor(rgbcolor[4] * 255)

    return r|g<<8|b<<16|a<<24
end

local default_curve_world<const> = {
    enable = false,
    type = "cylinder",
    dirVS = {0, 0, 1},
    flat_distance = 0,
    curve_rate = 0.05,
    distance = 500,
    max_rage = math.pi*0.6,
    type_options = {"cylinder", "view_sphere"}
}

local function setting_ui(sc)
    local graphic = sc:data().graphic

    if TreeNode("Graphic", default_tr_flags) then
        --Render
        if TreeNode("Render", imgui.flags.TreeNode{}) then
            local r = graphic.render
            if TreeNode("Clear State", imgui.flags.TreeNode{}) then

                local rs = {}
                local rbgcolor = toRGBColor(r.clear_color)
                if CheckProperty("Color", rbgcolor, r.clear:match "C"~=nil, PropertyColor, function (rgbcolor)
                    sc:set("graphic/render/clear_color", toDWColor(rgbcolor))
                end) then
                    rs[#rs+1] = "C"
                end

                local v = {r.clear_depth}
                if CheckProperty("Depth", v, r.clear:match "D"~=nil, PropertyFloat, function (v)
                    sc:set("graphic/render/clear_depth", v[1])
                end) then
                    rs[#rs+1] = "D"
                end


                v[1] = r.clear_stencil
                if CheckProperty("Stencil", v, r.clear:match "S"~=nil, PropertyFloat, function (v)
                    sc:set("graphic/render/clear_stencil", v[1])
                end) then
                    rs[#rs+1] = "S"
                end

                if #rs >= 0 then
                    sc:set("graphic/render/clear" ,table.concat(rs, ""))
                end
                TreePop()
            end

            TreePop()
        end

        --shadow
        if TreeNode("Shadow", default_tr_flags) then
            TreePop()
        end

        --postprocess
        if TreeNode("Postprocess", default_tr_flags) then
            local pp = graphic.postprocess
            if TreeNode("Bloom", default_tr_flags) then
                local b = pp.bloom
                local change, enable = Checkbox("Enable", b.enable)
                if change then
                    sc:set("graphic/postprocess/bloom/enable", enable)
                end
                BeginDisabled(not enable)
                local v = {b.inv_highlight or 0.0}
                if PropertyFloat("Inverse HighLight", v) then
                    sc:set("graphic/postprocess/bloom/inv_highlight", v[1])
                end

                v[1] = b.threshold or 0.0
                if PropertyFloat("Lumnimance Thresthod", v) then
                    sc:set("graphic/postprocess/bloom/threshold", v[1])
                end
                EndDisabled()
                TreePop()
            end
            TreePop()
        end

        --curve world
        
        if TreeNode("Curve World", default_tr_flags)then
            local cw = graphic.curve_world
            local change, enable = Checkbox("Enable", cw and cw.enable or false)
            if change then
                if cw == nil then
                    sc:set("graphic/curve_world", default_curve_world)
                    cw = default_curve_world
                end
                sc:set("graphic/curve_world/enable", enable)
            end
            cw = cw or default_curve_world

            BeginDisabled(not enable)
            if BeginCombo("Type", {cw.type, flags = imgui.flags.Combo{} }) then
                for _, n in ipairs(default_curve_world.type_options) do
                    if imgui.widget.Selectable(n, cw.type == n) then
                        sc:set("graphic/curve_world/type", n)
                    end
                end
                EndCombo()
            end

            local t = cw.type
            if t == "cylinder" then
                local v = {cw.flat_distance}
                if PropertyFloat("Flat Distance", v) then
                    sc:set("graphic/curve_world/flat_distance", v[1])
                end
                v[1] = cw.curve_rate
                if PropertyFloat("Curve Rate", v) then
                    sc:set("graphic/curve_world/curve_rate", v[1])
                end

                v[1] = cw.distance
                if PropertyFloat("Curve distance", v) then
                    sc:set("graphic/curve_world/distance", v[1])
                end

                v[1] = math.deg(cw.max_range)
                if PropertyFloat("Max Range", v) then
                    sc:set("graphic/curve_world/max_range", math.rad(v[1]))
                end
            else
                assert(cw.type == "view_sphere")
                --log.info("curve world type 'view_sphere' is not used")
            end

            local origin_disVS = cw.dirVS or default_curve_world.dirVS
            local dirVS = {}; for i=1, #origin_disVS do dirVS[i] = origin_disVS[i] end
            if PropertyFloat("Direction", dirVS) then
                sc:set("graphic/curve_world/dirVS", dirVS)
            end
            EndDisabled()
            TreePop()
        end

        TreePop()
    end

    if Button "Save" then
        local p = sc:setting_path()
        local f<close> = lfs.open(p, "w")
        f:write(serialize.stringify(sc._data))
    end
end

local projsetting
local projpath

function ps.show(open_popup)
    if open_popup then
        imgui.windows.OpenPopup(ps.id)
        imgui.windows.SetNextWindowSize(800, 600)
    end

    if BeginPopupModal(ps.id, default_win_flags) then
        if BeginTabBar("PS_Bar", default_tab_flags) then
            if BeginTabItem "Editor" then
                setting_ui(setting.setting)
                EndTabItem()
            end

            local proj_root = global_data.project_root
            if proj_root then
                if BeginTabItem "Project" then
                    if projpath ~= proj_root or projsetting == nil then
                        projsetting = setting.create(proj_root / "settings")
                    end
                    
                    setting_ui(projsetting)
                    EndTabItem()
                end
            end

            EndTabBar()
        end

        EndPopup()
    end
end

return ps