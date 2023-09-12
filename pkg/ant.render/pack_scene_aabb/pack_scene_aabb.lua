local ecs   = ...
local world = ecs.world
local w     = world.w
local queuemgr	= ecs.require "queue_mgr"
local psa_sys = ecs.system "pack_scene_aabb_system"
local math3d    = require "math3d"
local setting	= import_package "ant.settings"
local ENABLE_SHADOW<const> = setting:get "graphic/shadow/enable"
local renderutil= require "util"
local mc = import_package "ant.math".constant

if not ENABLE_SHADOW then
	renderutil.default_system(psa_sys, 	"init", "entity_init", "entity_remove", "after_scene_update")
	return
end

function psa_sys:init()
    world:create_entity {
        policy = {
            "ant.render|pack_scene_aabb",
        },
        data = {
            pack_scene_aabb = {
                need_update = true
            },
        }
    }
end

local dirty

function psa_sys:entity_init()
    dirty = w:first "INIT scene bounding"
    for e in w:select "INIT pack_scene_aabb:update" do
        e.pack_scene_aabb.scene_aabb = math3d.marked_aabb(math3d.vector(-1e9, -1e9, -1e9), math3d.vector(1e9, 1e9, 1e9)) 
    end
        
end

function psa_sys:entity_remove()
    if not dirty then
        dirty = w:first "REMOVED scene bounding" 
    end
end

local function merge_aabb(mask, visible_masks, cull_masks, entity_scene_aabb, whole_scene_aabb)
    local has_objects = false
    if (mask & visible_masks) and (mask & cull_masks) then
        if entity_scene_aabb and entity_scene_aabb ~= mc.NULL then
            whole_scene_aabb = math3d.aabb_merge(whole_scene_aabb, entity_scene_aabb) 
            has_objects = true
        end
    end
    return whole_scene_aabb, has_objects
end

function psa_sys:after_scene_update()
    if not dirty then
        dirty = w:first "scene_changed scene bounding" 
    end
    local psae = w:first "pack_scene_aabb:update"
    if dirty and psae and psae.pack_scene_aabb.need_update then
        local scene_aabb = math3d.aabb(math3d.vector(0, 0, 0), math3d.vector(0, 0, 0))
        local mask = assert(queuemgr.queue_mask("main_queue"))
        local has_objects = false
        for e in w:select "render_object_visible bounding:in render_object:in" do
            scene_aabb, has_objects = merge_aabb(mask, e.render_object.visible_masks, e.render_object.cull_masks, e.bounding.scene_aabb, scene_aabb)
        end
        for e in w:select "hitch_visible bounding:in hitch:in" do
            scene_aabb, has_objects = merge_aabb(mask, e.hitch.visible_masks, e.hitch.cull_masks, e.bounding.scene_aabb, scene_aabb)
        end
        if has_objects then
            math3d.unmark(psae.pack_scene_aabb.scene_aabb)
            local center, extent = math3d.aabb_center_extents(scene_aabb)
            local aabb_min, aabb_max = math3d.sub(center, extent), math3d.add(center, extent)
            psae.pack_scene_aabb.scene_aabb = math3d.marked_aabb(aabb_min, aabb_max)
            w:submit(psae) 
        end
        dirty = false
    end
end

