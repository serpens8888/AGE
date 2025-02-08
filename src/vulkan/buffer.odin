package vulk

import vk "vendor:vulkan"
import vma "../odin-vma"
import "core:mem"

vk_buffer :: struct{
	handle: vk.Buffer,
	memory: vma.Allocation,
}


create_buffer :: proc(allocator: vma.Allocator, size: vk.DeviceSize, usage: vk.BufferUsageFlags, properties: vk.MemoryPropertyFlags) -> vk_buffer{

	bci: vk.BufferCreateInfo = {
		sType = .BUFFER_CREATE_INFO,
		size = size,
		usage = usage,
		sharingMode = .EXCLUSIVE,
	}

	aci: vma.Allocation_Create_Info = {
		flags = {.Strategy_Min_Memory, .Strategy_Min_Time, .Strategy_Min_Offset},
		usage = .Auto,
		required_flags = properties,
	}

	buffer: vk_buffer

	vma.create_buffer(allocator, bci, aci, &buffer.handle, &buffer.memory, {})

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




copy_buffer :: proc(ctx: ^vk_context, src: vk.Buffer, dst: vk.Buffer, size: vk.DeviceSize){
	alloc_info: vk.CommandBufferAllocateInfo = {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		level = .PRIMARY,
		commandPool = ctx.queues.pools.transfer,
		commandBufferCount = 1,
	}
	
	cmd_buffer: vk.CommandBuffer
	vk.AllocateCommandBuffers(ctx.device, &alloc_info, &cmd_buffer)

	begin_info: vk.CommandBufferBeginInfo = {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT}
	}

	copy_region: vk.BufferCopy = {
		srcOffset = 0,
		dstOffset = 0,
		size = size,
	}

	vk.BeginCommandBuffer(cmd_buffer, &begin_info)
	vk.CmdCopyBuffer(cmd_buffer, src, dst, 1, &copy_region)
	vk.EndCommandBuffer(cmd_buffer)

	submit_info: vk.SubmitInfo = {
		sType = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers = &cmd_buffer,
	}

	vk.QueueSubmit(ctx.queues.transfer_queue, 1, &submit_info, {})
	vk.QueueWaitIdle(ctx.queues.transfer_queue) //not optimal?
	vk.FreeCommandBuffers(ctx.device, ctx.queues.pools.transfer, 1, &cmd_buffer)
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
