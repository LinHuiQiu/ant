#define LUA_LIB

#include <lua.h>
#include <lauxlib.h>
#include <stdint.h>
#include "luabgfx.h"

#define EVENT_QUEUE_SIZE 0x8000
#define TEXTURE_MAX_ID 0x7fff

static short int g_eventqueue[EVENT_QUEUE_SIZE] = { 0 };
static short int g_ptr = 0;
static uint16_t g_texture[TEXTURE_MAX_ID];
static uint16_t g_texture_id = 0;
static uint32_t g_frame = 0;
static uint32_t g_texture_timestamp[TEXTURE_MAX_ID];

static int
levent_push(lua_State *L) {
	int e = luaL_checkinteger(L, 1);
	if (e == 0 || e > 0x7fff || e < -0x7ffff)
		return luaL_error(L, "Invalid event %d", e);
	int next = (g_ptr + 1) % EVENT_QUEUE_SIZE;
	g_eventqueue[next] = 0;
	g_eventqueue[g_ptr] = e;
	g_ptr = next;
	return 0;
}

static int
levent_pop(lua_State *L) {
	int ptr = lua_tointeger(L, lua_upvalueindex(1));
	int e = g_eventqueue[ptr];
	if (e == 0)
		return 0;
	int next = (ptr + 1) % EVENT_QUEUE_SIZE;
	lua_pushinteger(L, next);
	lua_replace(L, lua_upvalueindex(1));
	lua_pushinteger(L, e);
	return 1;
}

static int
ltexture_create(lua_State *L) {
	uint16_t handle = BGFX_LUAHANDLE_ID(TEXTURE, luaL_checkinteger(L, 1));
	if (g_texture_id >= TEXTURE_MAX_ID) {
		return luaL_error(L, "Too many textures");
	}
	int id = g_texture_id++;
	g_texture[id] = handle;
	g_texture_timestamp[id] = g_frame;
	lua_pushinteger(L, id+1);
	return 1;
}

static int
ltexture_get(lua_State *L) {
	int id = luaL_checkinteger(L, 1);
	if (id <= 0 || id > g_texture_id)
		return luaL_error(L, "Invalid texture handle %d", id);
	uint16_t h = g_texture[id - 1];
	g_texture_timestamp[id - 1] = g_frame;
	int luahandle = (BGFX_HANDLE_TEXTURE << 16) | h;
	lua_pushinteger(L, luahandle);
	return 1;
}

static int
ltexture_set(lua_State *L) {
	int id = luaL_checkinteger(L, 1);
	if (id <= 0 || id > g_texture_id)
		return luaL_error(L, "Invalid texture handle %d", id);
	uint16_t handle = BGFX_LUAHANDLE_ID(TEXTURE, luaL_checkinteger(L, 2));
	g_texture[id - 1] = handle;
	return 0;
}

static int
lframe_tick(lua_State *L) {
	int f = g_frame++;
	lua_pushinteger(L, f);
	return 1;
}

static inline uint32_t
read_timestamp(int index) {
	uint32_t t = g_texture_timestamp[index];
	return (uint32_t)(g_frame - t);
}

static void
frame_get(lua_State *L,int index, int range) {
	int i;
	int n = 0;
	if (range >= 0) {
		// filter new
		for (i=0;i<g_texture_id;i++) {
			if (read_timestamp(i) <= range) {
				lua_pushinteger(L, i+1);
				lua_rawseti(L, index, ++n);
			}
		}
	} else {
		// filter old
		int old = - range;
		for (i=0;i<g_texture_id;i++) {
			if (read_timestamp(i) >= old) {
				lua_pushinteger(L, i+1);
				lua_rawseti(L, index, ++n);
			}
		}
	}
	int on = lua_rawlen(L, index);
	for (i=n;i<=on;i++) {
		lua_pushnil(L);
		lua_rawseti(L, index, i);
	}
}

static void
check_result(lua_State *L) {
	if (lua_isnoneornil(L, 2)) {
		lua_settop(L, 1);
		lua_newtable(L);
	} else {
		luaL_checktype(L, 2, LUA_TTABLE);
		lua_settop(L, 2);
	}
}

static int
lframe_new(lua_State *L) {
	int range = luaL_optinteger(L, 1, 0);
	if (range < 0)
		return luaL_error(L, "Invalid range %d", range);
	check_result(L);
	frame_get(L, 2, range);
	return 1;
}

static int
lframe_old(lua_State *L) {
	int range = luaL_checkinteger(L, 1);
	if (range <= 0)
		return luaL_error(L, "Invalid range %d", range);
	check_result(L);
	frame_get(L, 2, -range);
	return 1;
}

LUAMOD_API int
luaopen_textureman_client(lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{ "texture_get", ltexture_get },
		{ "event_pop", NULL },
		{ NULL, NULL },
	};
	luaL_newlib(L, l);

	lua_pushinteger(L, 0);
	lua_pushcclosure(L, levent_pop, 1);
	lua_setfield(L, -2, "event_pop");

	return 1;
}

LUAMOD_API int
luaopen_textureman_server(lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{ "event_push", levent_push },
		{ "texture_create", ltexture_create },
		{ "texture_set", ltexture_set },
		{ "frame_tick", lframe_tick },
		{ "frame_new", lframe_new },
		{ "frame_old", lframe_old },
		{ NULL, NULL },
	};
	luaL_newlib(L, l);	

	return 1;
}