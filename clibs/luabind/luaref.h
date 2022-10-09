#pragma once

#include <lua.hpp>
typedef lua_State* luaref;

luaref luaref_init   (lua_State* L);
void   luaref_close  (luaref refL);
bool   luaref_isvalid(luaref refL, int ref);
int    luaref_ref    (luaref refL, lua_State* L);
void   luaref_unref  (luaref refL, int ref);
void   luaref_get    (luaref refL, lua_State* L, int ref);

class luaref_box {
public:
    luaref_box(luaref refL, lua_State* L)
        : refL(refL)
        , ref(luaref_ref(refL, L))
    {}
    ~luaref_box() {
        luaref_unref(refL, ref);
    }
    bool isvalid() const {
        return luaref_isvalid(refL, ref);
    }
    void get(lua_State* L) const {
        luaref_get(refL, L, ref);
    }
    int handle() const {
        return ref;
    }
private:
    luaref refL;
    int ref;
};
