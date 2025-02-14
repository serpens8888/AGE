package vulk

import vk "vendor:vulkan"
import vma "../vma"
import "core:mem"

Buffer :: struct{
	handle: vk.Buffer,
	memory: vma.Allocation,
}


create_buffer :: proc(allocator: vma.Allocator, size: vk.DeviceSize, usage: vk.BufferUsageFlags, properties: vk.MemoryPropertyFlags) -> Buffer{

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

	buffer: Buffer

	vma.create_buffer(allocator, bci, aci, &buffer.handle, &buffer.memory, {})

	return buffer
}

copy_buffer :: proc(ctx: ^vk_context, src: vk.Buffer, dst: vk.Buffer, size: vk.DeviceSize){
	cmd_buf := begin_single_time_command(ctx.device, ctx.queues.pools.transfer)
	copy_region: vk.BufferCopy = {
		srcOffset = 0,
		dstOffset = 0,
		size = size,
	}
	vk.CmdCopyBuffer(cmd_buf, src, dst, 1, &copy_region)
	end_single_time_command(ctx.device, ctx.queues.pools.transfer, ctx.queues.transfer_queue, &cmd_buf)
}

create_command_buffers :: proc(device: vk.Device, pool: vk.CommandPool, count: u32) -> []vk.CommandBuffer{
	alloc_info: vk.CommandBufferAllocateInfo = {
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = pool,
		level = .PRIMARY,
		commandBufferCount = count,
	}
	
	buffers := make([]vk.CommandBuffer, count)

	if(vk.AllocateCommandBuffers(device, &alloc_info, raw_data(buffers)) != .SUCCESS){
		panic("failed to create command buffers")
	}

	return buffers
}

begin_single_time_command :: proc(device: vk.Device, pool: vk.CommandPool) -> vk.CommandBuffer{
	cmd_buf_slice := create_command_buffers(device, pool, 1)
	cmd_buf := cmd_buf_slice[0]
	delete(cmd_buf_slice)

	begin_info: vk.CommandBufferBeginInfo = {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	vk.BeginCommandBuffer(cmd_buf, &begin_info)

	return cmd_buf
}

end_single_time_command :: proc(device: vk.Device, pool: vk.CommandPool, queue: vk.Queue, cmd_buf: ^vk.CommandBuffer){
	vk.EndCommandBuffer(cmd_buf^)

	submit_info: vk.SubmitInfo = {
		sType = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers = cmd_buf
	}

	vk.QueueSubmit(queue, 1, &submit_info, 0)
	vk.QueueWaitIdle(queue)
	vk.FreeCommandBuffers(device, pool, 1, cmd_buf)
}















