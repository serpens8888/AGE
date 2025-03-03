package vulk

import "core:fmt"
import "core:mem"
import vk "vendor:vulkan"
import vma "../vma"

Uniform_Buffer :: struct{
	buffer: Buffer,
	mapped_ptr: rawptr,
	address: vk.DeviceAddress,
}

Push_Constant :: struct{
	range: vk.PushConstantRange,
	data: vk.DeviceAddress,
}

create_push_constant :: proc($T: typeid, stage_flags: vk.ShaderStageFlags, current_offset: ^u32) -> Push_Constant {

	pc: Push_Constant

	size := u32(size_of(T))

	assert(current_offset^ + size <= 128)
	pc.range ={
		stageFlags = stage_flags,
		offset = current_offset^,
		size = size,
	}
	current_offset^ += size

	return pc
}

align_size :: #force_inline proc(value: vk.DeviceSize, alignment: vk.DeviceSize) -> vk.DeviceSize{
	return (value + alignment -1) & ~(alignment-1) //idk how this works, but its gonna align the size
}

create_uniform_buffer :: proc(device: vk.Device, allocator: vma.Allocator, count: u32, $T: typeid) -> []Uniform_Buffer{
	uniform_buffers := make([]Uniform_Buffer, count)

	for &uniform, i in uniform_buffers{
		uniform.buffer = create_buffer(allocator, size_of(T), {.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS}, {.HOST_VISIBLE, .HOST_COHERENT})

		info: vk.BufferDeviceAddressInfo = {
			sType = .BUFFER_DEVICE_ADDRESS_INFO,
			buffer = uniform.buffer.handle,
		}

		vma.map_memory(allocator, uniform.buffer.memory, &uniform.mapped_ptr)
		uniform.address = vk.GetBufferDeviceAddress(device, &info)
	}

	return uniform_buffers
}

destroy_uniform_buffer :: proc(allocator: vma.Allocator, uniforms: []Uniform_Buffer){
	for &uniform in uniforms{
		vma.unmap_memory(allocator, uniform.buffer.memory)
		vma.destroy_buffer(allocator, uniform.buffer.handle, uniform.buffer.memory)
	}

	delete(uniforms)
}


create_pipeline_layout :: proc(device: vk.Device, layouts: []vk.DescriptorSetLayout, ranges: []vk.PushConstantRange) -> (layout: vk.PipelineLayout){

	create_info: vk.PipelineLayoutCreateInfo = {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = u32(len(layouts)),
		pSetLayouts = raw_data(layouts),
		pushConstantRangeCount = u32(len(ranges)),
		pPushConstantRanges = raw_data(ranges),
	}

	if(vk.CreatePipelineLayout(device, &create_info, nil, &layout) != .SUCCESS){
		panic("failed to create pipeline layout")
	}

	return
}




