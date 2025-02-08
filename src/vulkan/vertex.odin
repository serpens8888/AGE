package vulk

import vk "vendor:vulkan"
import vma "../vma"
import "core:mem"


Vertex :: struct{
	pos: [3]f32,
	normal: [3]f32,
	uv: [2]f32,
}

get_binding_desc :: proc() -> vk.VertexInputBindingDescription2EXT{
	binding_desc: vk.VertexInputBindingDescription2EXT
	binding_desc.sType = .VERTEX_INPUT_BINDING_DESCRIPTION_2_EXT
	binding_desc.binding = 0
	binding_desc.stride = size_of(Vertex)
	binding_desc.inputRate = .VERTEX
	binding_desc.divisor = 1
	return binding_desc
}

get_pos_attr_desc :: proc() -> vk.VertexInputAttributeDescription2EXT{
	attr_desc: vk.VertexInputAttributeDescription2EXT
	attr_desc.sType = .VERTEX_INPUT_ATTRIBUTE_DESCRIPTION_2_EXT
	attr_desc.binding = 0
	attr_desc.location = 0
	attr_desc.format = .R32G32B32_SFLOAT
	attr_desc.offset = u32(offset_of(Vertex, pos))
	return attr_desc
}

get_normal_attr_desc :: proc() -> vk.VertexInputAttributeDescription2EXT{
	attr_desc: vk.VertexInputAttributeDescription2EXT
	attr_desc.sType = .VERTEX_INPUT_ATTRIBUTE_DESCRIPTION_2_EXT
	attr_desc.binding = 0
	attr_desc.location = 1
	attr_desc.format = .R32G32B32_SFLOAT
	attr_desc.offset = u32(offset_of(Vertex, normal))
	return attr_desc
}

get_uv_attr_desc :: proc() -> vk.VertexInputAttributeDescription2EXT{
	attr_desc: vk.VertexInputAttributeDescription2EXT
	attr_desc.sType = .VERTEX_INPUT_ATTRIBUTE_DESCRIPTION_2_EXT
	attr_desc.binding = 0
	attr_desc.location = 2
	attr_desc.format = .R32G32_SFLOAT
	attr_desc.offset = u32(offset_of(Vertex, uv))
	return attr_desc
}

create_vertex_buffer :: proc(ctx: ^vk_context, allocator: vma.Allocator, verts: []Vertex) -> vk_buffer{
	buffer_size := vk.DeviceSize(len(verts)* size_of(verts[0]))
	staging_buffer := create_buffer(allocator, buffer_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})

	data: rawptr
	vma.map_memory(allocator, staging_buffer.memory, &data)
	mem.copy(data, raw_data(verts), int(buffer_size))
	vma.unmap_memory(allocator, staging_buffer.memory)

	vertex_buffer := create_buffer(allocator, buffer_size, {.TRANSFER_DST, .VERTEX_BUFFER}, {.DEVICE_LOCAL})
	copy_buffer(ctx, staging_buffer.handle, vertex_buffer.handle, buffer_size)

	vma.destroy_buffer(allocator, staging_buffer.handle, staging_buffer.memory)

	return vertex_buffer
}

create_index_buffer :: proc(ctx: ^vk_context, allocator: vma.Allocator, indices: []u32) -> vk_buffer{
	buffer_size := vk.DeviceSize(len(indices) * size_of(indices[0]))
	staging_buffer := create_buffer(allocator, buffer_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})

	data: rawptr
	vma.map_memory(allocator, staging_buffer.memory, &data)
	mem.copy(data, raw_data(indices), int(buffer_size))
	vma.unmap_memory(allocator, staging_buffer.memory)

	index_buffer := create_buffer(allocator, buffer_size, {.TRANSFER_DST, .INDEX_BUFFER}, {.DEVICE_LOCAL})
	copy_buffer(ctx, staging_buffer.handle, index_buffer.handle, buffer_size)

	vma.destroy_buffer(allocator, staging_buffer.handle, staging_buffer.memory)

	return index_buffer
}

