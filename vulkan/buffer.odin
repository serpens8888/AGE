package vulk

import vk "vendor:vulkan"

vk_buffer :: struct{
	handle: vk.Buffer,
	memory: vk.DeviceMemory,
}

create_command_buffers :: proc(device: vk.Device, pool: vk.CommandPool, count: u32) -> []vk.CommandBuffer{
	alloc_info: vk.CommandBufferAllocateInfo = {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = pool,
		level = .PRIMARY,
		commandBufferCount = count,
	}
	
	buffers := make([]vk.CommandBuffer, 3)

	if(vk.AllocateCommandBuffers(device, &alloc_info, raw_data(buffers)) != .SUCCESS){
		panic("failed to create command buffers")
	}

	return buffers
}

create_buffer :: proc(device: vk.Device, gpu: vk.PhysicalDevice, size: vk.DeviceSize,
					  usage: vk.BufferUsageFlags, properties: vk.MemoryPropertyFlags) -> vk_buffer{

	ci: vk.BufferCreateInfo = {
		sType = .BUFFER_CREATE_INFO,
		size = size,
		usage = usage,
		sharingMode = .EXCLUSIVE,
	}

	buffer: vk_buffer
	vk.CreateBuffer(device, &ci, nil, &buffer.handle)

	mem_reqs: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, buffer.handle, &mem_reqs)

	alloc_info: vk.MemoryAllocateInfo = {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = mem_reqs.size,
		memoryTypeIndex = find_memory_type(gpu, mem_reqs.memoryTypeBits, properties)
	}

	vk.AllocateMemory(device, &alloc_info, nil, &buffer.memory)
	vk.BindBufferMemory(device, buffer.handle, buffer.memory, 0)

	return buffer
}


find_memory_type :: proc(gpu: vk.PhysicalDevice, type_filter: u32, properties: vk.MemoryPropertyFlags) -> u32{
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(gpu, &mem_properties)

	for i in 0..<mem_properties.memoryTypeCount{
		if(type_filter & (1<<i) != 0 && (mem_properties.memoryTypes[i].propertyFlags & properties) == properties){
			return u32(i)
		}
	}
	panic("failed to find suitable device memory")
}


