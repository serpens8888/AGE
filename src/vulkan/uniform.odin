package vulk

import "core:fmt"
import vk "vendor:vulkan"
import vma "../vma"

uniform_buffer :: struct{
	buffer: vk_buffer,
	mapped_ptr: rawptr,
}

UniformBufferFrame :: struct{
	buffer: vk_buffer,
	mapped_data: rawptr,
	set: vk.DescriptorSet,
}

Uniform :: struct{
	layout: vk.DescriptorSetLayout,
	pipeline_layout: vk.PipelineLayout,
	pool: vk.DescriptorPool,
	frames: []UniformBufferFrame,
}

create_uniform :: proc(device: vk.Device, render_state: ^render_loop_state, allocator: vma.Allocator, $T: typeid) -> Uniform{
	uniform: Uniform
	uniform.frames = make([]UniformBufferFrame, render_state.frames_in_flight)

	layout_binding: vk.DescriptorSetLayoutBinding = {
		binding = 0,
		descriptorType = .UNIFORM_BUFFER,
		descriptorCount = 1,
		stageFlags = vk.ShaderStageFlags_ALL,
		pImmutableSamplers = {},
	}

	layout_info: vk.DescriptorSetLayoutCreateInfo = {
		sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings = &layout_binding,
	}

	if( vk.CreateDescriptorSetLayout(device, &layout_info, nil, &uniform.layout) != .SUCCESS){
		panic("failed to create descriptor set layout")
	}



	ci: vk.PipelineLayoutCreateInfo = {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts = &uniform.layout,
		pushConstantRangeCount = 0,
	}

	if( vk.CreatePipelineLayout(device, &ci, nil, &uniform.pipeline_layout) != .SUCCESS){
		panic("failed to create pipeline layout")
	}



	pool_size: vk.DescriptorPoolSize = {
		type = .UNIFORM_BUFFER,
		descriptorCount = u32(render_state.frames_in_flight),
	}

	pool_info: vk.DescriptorPoolCreateInfo = {
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = 1,
		pPoolSizes = &pool_size,
		maxSets = u32(render_state.frames_in_flight)
	}

	if(vk.CreateDescriptorPool(device, &pool_info, nil, &uniform.pool) != .SUCCESS){
		panic("failed to create descriptor pool")
	}



	for i in 0..<len(uniform.frames){
		uniform.frames[i].buffer = create_buffer(allocator, size_of(T), {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT})
		vma.map_memory(allocator, uniform.frames[i].buffer.memory, &uniform.frames[i].mapped_data)

		
		ai: vk.DescriptorSetAllocateInfo = {
			sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool = uniform.pool,
			descriptorSetCount = 1,
			pSetLayouts = &uniform.layout,
		}

		if(vk.AllocateDescriptorSets(device, &ai, &uniform.frames[i].set) != .SUCCESS){
			panic("failed to allocate descriptor sets")
		}

		buffer_info: vk.DescriptorBufferInfo = {
			buffer = uniform.frames[i].buffer.handle,
			offset = 0,
			range = size_of(T), //could also use vk.WHOLE_SIZE
		}	

		desc_write: vk.WriteDescriptorSet = {
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = uniform.frames[i].set,
			dstBinding = 0,
			dstArrayElement = 0,
			descriptorType = .UNIFORM_BUFFER,
			descriptorCount = 1,
			pBufferInfo = &buffer_info,
		}

		vk.UpdateDescriptorSets(device, 1, &desc_write, 0, nil)
	}

	return uniform
}



destroy_uniform :: proc(device: vk.Device, allocator: vma.Allocator, uniform: ^Uniform){
	for i in 0..<len(uniform.frames){
		vma.destroy_buffer(allocator, uniform.frames[i].buffer.handle, uniform.frames[i].buffer.memory)
	}
	vk.DestroyPipelineLayout(device, uniform.pipeline_layout, nil)
	vk.DestroyDescriptorPool(device, uniform.pool, nil)
	vk.DestroyDescriptorSetLayout(device, uniform.layout, nil)
	delete(uniform.frames)
}



