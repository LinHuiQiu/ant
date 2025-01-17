local gltfutil  = require "model.glTF.util"
local utility   = require "model.utility"
local meshutil	= require "model.meshutil"
local packer 	= require "model.pack_vertex_data"
local pack_vertex_data = packer.pack

local function get_layout(name, accessor)
	local attribname, channel = name:match"(%w+)_(%d+)"
	local shortname = meshutil.SHORT_NAMES[attribname or name]
	local comptype_name = gltfutil.comptype_name_mapper[accessor.componentType]
	local shorttype = gltfutil.decl_comptype_mapper[comptype_name]
	local asInt = shorttype ~= 'f' and 'i' or 'I'
	return ("%s%d%d%s%s%s"):format(
		shortname,
		gltfutil.type_count_mapper[accessor.type],
		channel or 0,
		(accessor.normalized and "n" or "N"),
		asInt,
		shorttype)
end

local function attrib_data(desc, iv, buffers)
	local b = buffers[desc.bidx+1]
	local bin = b.bin
	local buf_offset = desc.bv + iv * desc.stride + desc.acc
	assert(buf_offset < b.byteLength)
	local e = buf_offset+desc.size
	assert(e <= b.byteLength)
	local s = buf_offset+1
	return bin:sub(s, e)
end

local function to_ib(indexbin, flag, count)
	return {
		memory 	= {indexbin, 1, #indexbin},
		flag 	= flag,
		start 	= 0,
		num 	= count,
	}
end

 local function fetch_ib_buffer(gltfscene, index_accessor, ib_table)
	local buffers = gltfscene.buffers
	local bufferViews = gltfscene.bufferViews

	local bvidx = index_accessor.bufferView+1
	local bv = bufferViews[bvidx]
	local elemsize = gltfutil.accessor_elemsize(index_accessor)
	local class = {
		acc_offset = index_accessor.byteOffset or 0,
		bv_offset = bv.byteOffset or 0,
		elemsize = elemsize,
		stride = bv.byteStride or elemsize,
	}

	assert(elemsize == 2 or elemsize == 4)
	local offset = class.acc_offset + class.bv_offset
	local n = index_accessor.count
	local size = n * elemsize

	local buf = buffers[bv.buffer+1]
	local indexbin = buf.bin:sub(offset+1, offset+size)
	local num_triangles = n // 3

	local buffer = {}
	local fmt = elemsize == 4 and "III" or "HHH"
	for tri=0, num_triangles-1 do
		local buffer_offset = tri * elemsize * 3
		local v0, v1, v2 = fmt:unpack(indexbin, buffer_offset+1)
		ib_table[#ib_table + 1] = v0
		ib_table[#ib_table + 1] = v2
		ib_table[#ib_table + 1] = v1
		buffer[#buffer+1] = fmt:pack(v0, v2, v1)
	end

	indexbin = table.concat(buffer, "")

	return to_ib(indexbin, elemsize == 4 and 'd' or '', index_accessor.count)
end

local function create_prim_bounding(math3d, meshscene, prim)
	local posacc = meshscene.accessors[assert(prim.attributes.POSITION)+1]
	local minv = posacc.min
	if minv then
		local maxv = posacc.max
		assert(#minv == 3)
		assert(#maxv == 3)

		local bounding = {
			aabb = {
				{math.min(minv[1], maxv[1]), math.min(minv[2], maxv[2]), math.min(minv[3], maxv[3]),},
				{math.max(minv[1], maxv[1]), math.max(minv[2], maxv[2]), math.max(minv[3], maxv[3]),}
			}
		}
		prim.bounding = bounding
		return bounding
	end
end

local function get_obj_name(obj, idx, defname)
	if obj.name then
		return obj.name
	end

	return defname .. idx
end

local typemapper<const> = {
	f = 'f',
	i = 'H',
	u = 'B',
}

local function unpack_vec(v, l)
	local t = l:sub(6, 6)
	t = typemapper[t] or error(("not support layout:%s, type:%s must be 'float'"):format(l, t))

	local n = tonumber(l:sub(2, 2))
	local fmt = t:rep(n)
	local vv = {fmt:unpack(v)}
	vv[n+1] = nil -- remove unpack offset
	return vv, fmt
end

-- change from right hand to left hand
-- left hand define as:
-- 		x: -left, +right
-- 		y: +up, -down
--		z: -point2user, +point2screen
-- right hand define as:
-- 		x: -left, +right
-- 		y: +up, -down
--		z: +point2user, -point2screen
local function r2l_vec_v(v, l)
	local vv, fmt = unpack_vec(v, l)
	if vv[3] and l:sub(6,6) == 'f' then
		vv[3] = -vv[3]
	end
	return vv, fmt
end


local function r2l_vec(v, l)
	local vv, fmt = r2l_vec_v(v, l)
	return fmt:pack(table.unpack(vv))
end

local function find_layout(layouts, name)
	for i=1, #layouts do
		local l = layouts[i]
		if l.name == name then
			return l
		end
	end
end

local function find_layout_idx(layouts, name)
	for i=1, #layouts do
		local l = layouts[i]
		if l.name == name then
			return i
		end
	end
end

local function calc_tangents(math3d, ib, vb_num, vertices, layouts, store)
	local tangents, bitangents = {}, {}

	local P_IDX<const>, N_IDX<const>, UV_IDX<const> = 1, 2, 3
	local function load_vertex(vidx)
		local vertex = vertices[vidx]
		local p = unpack_vec(vertex[P_IDX], layouts[P_IDX].layout)
		local t = unpack_vec(vertex[UV_IDX], layouts[UV_IDX].layout)
		return {
			p = math3d.vector(p),
			u = t[1], v = t[2]
		}
	end
	--[[
		tangent calculation:
		we have 3 vertices: a, b, c, which have position and uv defined in triangle abc, we make:
			tangent T and bitangent B:
				b.p - a.p = (b.u-a.u)*T + (b.v-a.v)*B
				c.p - a.p = (c.u-a.u)*T + (c.v-a.v)*B
			make:
				ba=b.p-a.p, bau=b.u-a.u, bav=b.v-a.v
				ca=c.p-a.p, cau=c.u-a.u, cav=c.v-a.v

				ba = bau*T + bav*B	==> ba.x = bau*T.x + bav*B.x | ba.y = bau*T.y + bav*B.y | ba.z = bau*T.z + bav*B.z
				ca = cau*T + cav*B	==> ca.x = cau*T.x + cav*B.x | ca.y = cau*T.y + cav*B.y | ca.z = cau*T.z + cav*B.z

				cav*ba = cav*bau*T + cav*bav*B
				bav*ca = bav*cau*T + bav*cav*B

				bav*ca - cav*ba = (bav*cau-cav*bau)*T	==> T = (bav*ca - cav*ba)/(bav*cau - cav*bau)

				let det = (bav*cau-cav*bau), invdet = 1/(bav*cau-cav*bau)
				T = (bav*ca - cav*ba) * invdet

			we can solve T and B
	]]

	local function calc_tangent(vidx0, vidx1, vidx2)
		local a, b, c = load_vertex(vidx0), load_vertex(vidx1), load_vertex(vidx2)

		local ba = math3d.sub(b.p, a.p)
		local ca = math3d.sub(c.p, a.p)
		local bau, bav = b.u - a.u, b.v - a.v
		local cau, cav = c.u - a.u, c.v - a.v

		local det<const> = bau * cav - bav * cau
		local t, bi
		if math3d.ext_util.iszero(det) then
			t, bi = math3d.ext_constant.XAXIS, math3d.ext_constant.ZAXIS
		else
			local invDet<const> = 1.0 / det

			--(ba * cav - ca * bav) * invDet
			--(ca * bau - ba * cau) * invDet
			t, bi = math3d.mul(math3d.sub(math3d.mul(ba, cav), math3d.mul(ca, bav)), invDet),
					math3d.mul(math3d.sub(math3d.mul(ca, bau), math3d.mul(ba, cau)), invDet)
		end

		-- we will merge tangent and bitangent value
		tangents[vidx0]		= tangents[vidx0] and math3d.add(tangents[vidx0], t) or t
		tangents[vidx1]		= tangents[vidx1] and math3d.add(tangents[vidx1], t) or t
		tangents[vidx2]		= tangents[vidx2] and math3d.add(tangents[vidx2], t) or t

		bitangents[vidx0]	= bitangents[vidx0] and math3d.add(bitangents[vidx0], bi) or bi
		bitangents[vidx1]	= bitangents[vidx1] and math3d.add(bitangents[vidx1], bi) or bi
		bitangents[vidx2]	= bitangents[vidx2] and math3d.add(bitangents[vidx2], bi) or bi
	end

	if ib then
		for i=1, #ib, 3 do
			local vidx0, vidx1, vidx2 = ib[i]+1, ib[i+1]+1, ib[i+2]+1
			calc_tangent(vidx0, vidx1, vidx2)
		end
	else
		for iv=1, vb_num, 3 do
			calc_tangent(iv, iv+1, iv+2)
		end
	end

	-- see: http://www.opengl-tutorial.org/intermediate-tutorials/tutorial-13-normal-mapping/#tangent-and-bitangent
	local function make_vector_perpendicular(srcvec, basevec)
		local ndt	= math3d.dot(srcvec, basevec)
		return math3d.sub(srcvec, math3d.mul(basevec, ndt))
	end

	for iv=1, vb_num do
		local tanu 		= tangents[iv]
		local tanv 		= bitangents[iv]
		local normal 	= unpack_vec(vertices[iv][N_IDX], layouts[N_IDX].layout)
		normal 			= math3d.vector(normal)
		local tangent	= make_vector_perpendicular(tanu, normal)
		local bitangent	= make_vector_perpendicular(tanv, normal)

		if math3d.ext_util.iszero_math3dvec(tangent) or math3d.ext_util.isnan_math3dvec(tangent) then
			if math3d.ext_util.iszero_math3dvec(bitangent) or math3d.ext_util.isnan_math3dvec(bitangent) then
				tangent = math3d.ext_constant.XAXIS
			else
				tangent = math3d.cross(bitangent, normal)
			end
		end

		tangent	= math3d.normalize(tangent)

		local nxt    	= math3d.cross(normal, tangent)
		tangent	= math3d.set_index(tangent, 4, math3d.dot(nxt, bitangent) < 0 and 1.0 or -1.0)
		store(iv, tangent)
	end
end

local function r2l_buf(d, iv, gltfbuffers)
	local v = attrib_data(d, iv, gltfbuffers)
	return r2l_vec(v, d.layout)
end

local function is_vec_attrib(an)
	return ("pnTbc"):match(an)
end

local function need_calc_tangent(layouts1, layouts2)
	return find_layout(layouts1, "TANGENT") == nil and find_layout(layouts1, "NORMAL") and find_layout(layouts2, "TEXCOORD_0")
end

local function generate_layouts(gltfscene, attributes)
	local accessors, bufferViews = gltfscene.accessors, gltfscene.bufferViews
	local layouts1 = {}
	local layouts2 = {}
	for _, attribname in ipairs(meshutil.LAYOUT_NAMES) do
		local accidx = attributes[attribname]
		if accidx then
			local acc 	= accessors[accidx+1]
			local bvidx	= acc.bufferView+1
			local bv	= bufferViews[bvidx]
			local elemsize = gltfutil.accessor_elemsize(acc)
			local layout = get_layout(attribname, accessors[accidx+1])
			local layouttype = layout:sub(1, 1)
			local l = {
				name	= attribname,
				layout 	= layout,
				acc		= acc.byteOffset or 0,
			 	bv		= bv.byteOffset or 0,
				bidx	= assert(bv.buffer),
				size	= elemsize,
			 	stride	= bv.byteStride or elemsize,
				fetch_buf = is_vec_attrib(layouttype) and r2l_buf or attrib_data,
			}
			local layout1_attr = attribname:match "POSITION" or attribname:match "TANGENT" or attribname:match "NORMAL" or attribname:match "JOINTS_0" or attribname:match "WEIGHTS_0"
			if layout1_attr then
				layouts1[#layouts1+1] = l
			else
				layouts2[#layouts2+1] = l
			end
		end
	end
	return layouts1, layouts2
end

local function fetch_vertices(layouts, gltfbuffers, numv, reverse_wing_order)
	local vertices = {}
	for iv=0, numv-1 do
		local v = {}
		for _, l in ipairs(layouts) do
			v[#v+1] = l:fetch_buf(iv, gltfbuffers)
		end
		vertices[#vertices+1] = v
	end

	if reverse_wing_order then
		assert((numv // 3)*3 == numv)
		for iv=1, numv, 3 do
			-- swap v3 and v2
			vertices[iv+1], vertices[iv+2] = vertices[iv+2], vertices[iv+1]
		end
	end
	return vertices
end

local function fetch_vb_buffers(math3d, gltfscene, prim, ib_table, meshexport)
	local gltfbuffers = gltfscene.buffers
	assert(prim.mode == nil or prim.mode == 4)
	local numv = gltfutil.num_vertices(prim, gltfscene)

	local function get_vb(layouts, vertices)
		local new_vertices, new_layout = pack_vertex_data(math3d, layouts, vertices)
		local bindata = table.concat(new_vertices, "")
		return {
			declname = new_layout,
			memory = {bindata, 1, #bindata},
			start = 0,
			num = numv,
		}
	end

	local layouts1, layouts2 = generate_layouts(gltfscene, prim.attributes)

	local vertices1 = fetch_vertices(layouts1, gltfbuffers, numv, ib_table == nil)
	if need_calc_tangent(layouts1, layouts2) then
		local cp = math3d.checkpoint()
		local tmp_layouts = {layouts1[find_layout_idx(layouts1, "POSITION")], layouts1[find_layout_idx(layouts1, "NORMAL")], layouts2[find_layout_idx(layouts2, "TEXCOORD_0")]}
		local tmp_vertices = fetch_vertices(tmp_layouts, gltfbuffers, numv, ib_table == nil)
		calc_tangents(math3d, ib_table, #vertices1, tmp_vertices, tmp_layouts,
		function (iv, v)
			local vv = vertices1[iv]
			vv[#vv+1] = math3d.serialize(v)
		end
		)
		math3d.recover(cp)
		layouts1[#layouts1+1] = {
			layout		= "T40NIf",
			fetch_buf	= attrib_data,	-- this tangent already in left hand space
			name		= "TANGENT",
		}
	end
	local vb = get_vb(layouts1, vertices1)
	-- normal and tangent info only valid in layouts1
	meshexport.pack_tangent_frame = packer.is_pack2tangentframe(layouts1)

	local vb2
	if #layouts2 ~= 0 then
		local vertices2 = fetch_vertices(layouts2, gltfbuffers, numv, ib_table == nil)
		vb2 = get_vb(layouts2, vertices2)
	end
	return vb, vb2
end

-- local function check_front_face(vb, ib)
-- 	local function read_memory(m, fmt, offset)
-- 		offset = offset or 1
-- 		local d, o = m[1], m[2]
-- 		return fmt:unpack(d, offset)
-- 	end


-- 	local i1, i2, i3
-- 	if ib then
-- 		local fmt = ib.flag == '' and "HHH" or "III"
-- 		i1, i2, i3 = read_memory(ib.memory, fmt)
-- 	else
-- 		i1, i2, i3 = 1, 2, 3
-- 	end

-- 	assert(#vb == 1 and vb[1].declname:match "p")
-- 	local b = vb[1]


-- 	local stride_offset = 0
-- 	local fmt
-- 	do
-- 		for d in b.declname:gmatch "[^|]" do
-- 			if d:sub(1, 1) == 'p' then
-- 				local t = d:sub(6, 6)
-- 				local m<const> = {
-- 					['f'] = 'f',
-- 					['u'] = 'B',
-- 					['i'] = 'h',
-- 				}
-- 				local n = math.floor(tonumber(d:sub(2, 2)))
-- 				fmt = m[t]:rep(n)
-- 				break
-- 			end

-- 			stride_offset = stride_offset + layoutmgr.elem_size(d)
-- 		end
-- 	end

-- 	local stride = layoutmgr.layout_stride(b.declname)
-- 	if fmt == nil then
-- 		error "invalid vertex buffer"
-- 	end

-- 	local function vertex_offset(idx)
-- 		return idx * stride + stride_offset
-- 	end
-- 	local v1 = {read_memory(b.memory, fmt, vertex_offset(i1))}
-- 	local v2 = {read_memory(b.memory, fmt, vertex_offset(i2))}
-- 	local v3 = {read_memory(b.memory, fmt, vertex_offset(i3))}

-- 	--left hand check
-- 	v1[3] = 0.0
-- 	v2[3] = 0.0
-- 	v3[3] = 0.0
-- 	local e1 = math3d.sub(v2, v1)
-- 	local e2 = math3d.sub(v3, v1)
-- 	math3d.cross(e1, e2)

-- end

local function save_meshbin_files(status, resname, meshgroup)
	local cfgname = ("meshes/%s.meshbin"):format(resname)

	local function write_bin_file(fn, bin)
		utility.save_file(status, "meshes/" .. fn, bin)
		return fn
	end

	local vb = assert(meshgroup.vb)
	vb.memory[1] = write_bin_file(resname .. ".vbbin", vb.memory[1])
	local vb2 = meshgroup.vb2
	if meshgroup.vb2 then
		vb2.memory[1] = write_bin_file(resname .. ".vb2bin", vb2.memory[1])
	end
	local ib = meshgroup.ib
	if ib then
		ib.memory[1] = write_bin_file(resname .. ".ibbin", ib.memory[1])
	end

	utility.save_txt_file(status, cfgname, meshgroup, function (v) return v end)
	return cfgname
end


 local function export_meshbin(status)
	local gltfscene = status.gltfscene
	local math3d = status.math3d
	status.mesh = {}
	local meshes = gltfscene.meshes
	if meshes == nil then
		return
	end
	for meshidx, mesh in ipairs(meshes) do
		local meshname = get_obj_name(mesh, meshidx, "mesh")
		status.mesh[meshidx] = {}
		for primidx, prim in ipairs(mesh.primitives) do
			local ib_table = {}
			local group = {}
			local indices_accidx = prim.indices
			if indices_accidx then
				group.ib = fetch_ib_buffer(gltfscene, gltfscene.accessors[indices_accidx+1], ib_table)
			end

			local meshexport = {}
			group.vb, group.vb2 = fetch_vb_buffers(math3d, gltfscene, prim, ib_table, meshexport)
			local bb = create_prim_bounding(math3d, gltfscene, prim)
			if bb then
				local aabb = math3d.aabb(bb.aabb[1], bb.aabb[2])
				if math3d.aabb_isvalid(aabb) then
					group.bounding = bb
				end
			end

			local stemname = ("%s_P%d"):format(meshname, primidx)

			meshexport.meshbinfile = save_meshbin_files(status, stemname, group)
			meshexport.declname = {
				group.vb.declname,
				group.vb2 and group.vb2.declname or nil,
			}
			status.mesh[meshidx][primidx] = meshexport
		end
	end

	--calculate tangent info will use too many math3d resource, we need to reset here
	math3d.reset()
end

--[[ local function export_meshbin(gltfscene, bindata, exports)
	exports.mesh = {}
	local meshes = gltfscene.meshes
	if meshes == nil then
		return
	end
	for meshidx, mesh in ipairs(meshes) do
		local meshname = get_obj_name(mesh, meshidx, "mesh")
		local meshaabb = math3d.aabb()
		exports.mesh[meshidx] = {}
		for primidx, prim in ipairs(mesh.primitives) do
			local group = {}
			group.vb = fetch_vb_buffers(math3d, gltfscene, bindata, prim)
			local indices_accidx = prim.indices
			group.ib = indices_accidx and
				fetch_ib_buffer(gltfscene, bindata, gltfscene.accessors[indices_accidx+1]) or
				gen_ib(group.vb.num)

			local bb = create_prim_bounding(math3d, gltfscene, prim)
			if bb then
				local aabb = math3d.aabb(bb.aabb[1], bb.aabb[2])
				if math3d.aabb_isvalid(aabb) then
					group.bounding = bb
					meshaabb = math3d.aabb_merge(meshaabb, aabb)
				end
			end

			local stemname = ("%s_P%d"):format(meshname, primidx)
			exports.mesh[meshidx][primidx] = save_meshbin_files(status, stemname, group)
		end
	end
end ]]

return function (status)
	export_meshbin(status)
end
