package vulk

import vk "vendor:vulkan"
import vma "../vma"
import "core:mem" //for mem.copy
import "core:c/libc" // for system
import "core:strings"
import "core:fmt"
import "core:os"
import "core:time"
import "core:math/linalg/glsl"
import "core:math"

renderable :: struct{ //initialized to 0, handle not pointer
	vertex_buffer: vk_buffer,
	index_buffer: vk_buffer,
	vertex: vk.ShaderEXT,
	tesselation_ctl: vk.ShaderEXT,
	tesselation_eval: vk.ShaderEXT,
	geometry: vk.ShaderEXT,
	fragment: vk.ShaderEXT,
}

triangle :: struct{
	render_info: renderable
}




//uniforms

uniform_buffer :: struct{
	buffer: vk_buffer,
	mapped_ptr: rawptr,
}



ubo :: struct{
	model: matrix[4,4]f32,
	view: matrix[4,4]f32,
	proj: matrix[4,4]f32,
}

create_uniform_buffer :: proc(buffers: []uniform_buffer, allocator: vma.Allocator){
	buffer_size: vk.DeviceSize = size_of(ubo)

	for i in 0..<len(buffers){
		buffers[i].buffer = create_buffer(allocator, buffer_size, {.UNIFORM_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT})
		vma.map_memory(allocator, buffers[i].buffer.memory, &buffers[i].mapped_ptr)
	}
}
create_descriptor_layout :: proc(device: vk.Device) -> vk.DescriptorSetLayout{ //creates a base descriptor set layout that passes nothing
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

	desc_set_layout: vk.DescriptorSetLayout
	vk.CreateDescriptorSetLayout(device, &layout_info, nil, &desc_set_layout)
	return desc_set_layout
}

create_descriptor_pool :: proc(device: vk.Device, render_state: ^render_loop_state) -> vk.DescriptorPool{
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

	desc_pool: vk.DescriptorPool

	if(vk.CreateDescriptorPool(device, &pool_info, nil, &desc_pool) != .SUCCESS){
		panic("failed to create descriptor pool")
	}

	return desc_pool
}

create_descriptor_sets :: proc(device: vk.Device, layout: vk.DescriptorSetLayout, pool: vk.DescriptorPool, render_state: ^render_loop_state) -> []vk.DescriptorSet{
	layouts := make([]vk.DescriptorSetLayout, render_state.frames_in_flight)
	defer delete(layouts)

	for i in 0..<len(layouts){
		layouts[i] = layout
	}

	ai: vk.DescriptorSetAllocateInfo = {
		sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool = pool,
		descriptorSetCount = u32(render_state.frames_in_flight),
		pSetLayouts = raw_data(layouts),
	}

	sets := make([]vk.DescriptorSet, render_state.frames_in_flight)
	if(vk.AllocateDescriptorSets(device, &ai, raw_data(sets)) != .SUCCESS){
		panic("failed to allocate descriptor sets")
	}

	return sets
}

write_desc_sets :: proc(device: vk.Device, sets: []vk.DescriptorSet, ubufs: []uniform_buffer){
	for i in 0..<len(sets){
		buffer_info: vk.DescriptorBufferInfo = {
			buffer = ubufs[i].buffer.handle,
			offset = 0,
			range = size_of(ubo), //could also use vk.WHOLE_SIZE
		}

		desc_write: vk.WriteDescriptorSet = {
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = sets[i],
			dstBinding = 0,
			dstArrayElement = 0,
			descriptorType = .UNIFORM_BUFFER,
			descriptorCount = 1,
			pBufferInfo = &buffer_info,
		}

		vk.UpdateDescriptorSets(device, 1, &desc_write, 0, nil)
	}
}

create_pipeline_layout :: proc(device: vk.Device, layout: ^vk.DescriptorSetLayout) -> vk.PipelineLayout{

	ci: vk.PipelineLayoutCreateInfo = {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts = layout,
		pushConstantRangeCount = 0,
	}

	layout: vk.PipelineLayout
	if( vk.CreatePipelineLayout(device, &ci, nil, &layout) != .SUCCESS){
		panic("failed to create pipeline layout")
	}

	return layout
}




















//shader compilation & shader objects
swap_ext :: proc(filename: string, new_ext: string) -> string{
	name: string
	for i in 0..<len(filename){
		if(filename[i] == '.'){
			name := filename[0:i+1]
			slice: []string = {name, new_ext}
			name = strings.concatenate(slice, context.temp_allocator) //this is fine since the function calling it clears the temp allocator
			return name
		}
	}
	return ""
}

shader_src_dir :: "shaders/slang/"
shader_dst_dir :: "shaders/spirv/"
compile_shader :: proc(filename: string){
	src := strings.concatenate({shader_src_dir, filename}, context.temp_allocator)
	dst := strings.concatenate({shader_dst_dir, swap_ext(filename, "spv")}, context.temp_allocator)
	command_slice :[]string = {"slangc ", src, " -target spirv", " -o ", dst}
	libc.system(strings.clone_to_cstring(strings.concatenate(command_slice, context.temp_allocator), context.temp_allocator))
	free_all(context.temp_allocator)
}

read_spirv :: proc(filename: string) -> []u8{
	spirv_path := strings.concatenate({shader_dst_dir, filename})
	defer delete(spirv_path)
	data, ok := os.read_entire_file(spirv_path)
	assert(ok == true)

	return data
}



create_tri_vert :: proc(device: vk.Device, layout: ^vk.DescriptorSetLayout) -> vk.ShaderEXT{
	spirv := read_spirv("foo.spv")
	defer delete(spirv)

	vert_ci: vk.ShaderCreateInfoEXT = {
		sType = .SHADER_CREATE_INFO_EXT,
		flags = {.LINK_STAGE},
		stage = {.VERTEX},
		nextStage = {.FRAGMENT},
		codeType = .SPIRV,
		codeSize = len(spirv), // works becasue its read in bytes, len == size_of
		pCode = transmute([^]u32)raw_data(spirv),
		pName = "main",
		setLayoutCount = 1,
		pSetLayouts = layout,
		pushConstantRangeCount = 0,
		pPushConstantRanges = nil,
		pSpecializationInfo = nil,
	}
	vert_shader: vk.ShaderEXT
	vk.CreateShadersEXT(device, 1, &vert_ci, nil, &vert_shader)
	return vert_shader
}

create_tri_frag :: proc(device: vk.Device, layout: ^vk.DescriptorSetLayout) -> vk.ShaderEXT{
	spirv := read_spirv("foo.spv")
	defer delete(spirv)

	frag_ci: vk.ShaderCreateInfoEXT = {
		sType = .SHADER_CREATE_INFO_EXT,
		flags = {.LINK_STAGE},
		stage = {.FRAGMENT},
		nextStage = {},
		codeType = .SPIRV,
		codeSize = len(spirv), // works becasue its read in bytes, len == size_of
		pCode = transmute([^]u32)raw_data(spirv),
		pName = "main",
		setLayoutCount = 1,
		pSetLayouts = layout,
		pushConstantRangeCount = 0,
		pPushConstantRanges = nil,
		pSpecializationInfo = nil,
	}
	frag_shader: vk.ShaderEXT
	vk.CreateShadersEXT(device, 1, &frag_ci, nil, &frag_shader)
	return frag_shader

}

//command buffer recording
record_triangle_rendering :: proc(ctx: ^vk_context, cmd_buffer: vk.CommandBuffer, vert: vk.ShaderEXT, frag: vk.ShaderEXT, vbuf: ^vk.Buffer, ibuf: ^vk.Buffer, pipeline_layout: vk.PipelineLayout, set: ^vk.DescriptorSet, image_idx: u32){
	begin_info: vk.CommandBufferBeginInfo
	begin_info.sType = .COMMAND_BUFFER_BEGIN_INFO
	vk.BeginCommandBuffer(cmd_buffer, &begin_info)

	//put swapchain image into correct format

	image_subresource_range: vk.ImageSubresourceRange = {
		aspectMask = {.COLOR},
		baseMipLevel = 0,
		levelCount = 1,
		baseArrayLayer = 0,
		layerCount = 1,
	}

	image_memory_barrier: vk.ImageMemoryBarrier = {
		sType = .IMAGE_MEMORY_BARRIER,
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		oldLayout = .UNDEFINED,
		newLayout = .PRESENT_SRC_KHR,
		image = ctx.display.swapchain_images[image_idx],
		subresourceRange = image_subresource_range,
	}

	vk.CmdPipelineBarrier(cmd_buffer, {.TOP_OF_PIPE}, {.COLOR_ATTACHMENT_OUTPUT}, {}, 0, nil, 0, nil, 1, &image_memory_barrier)


	//set dynamic state
	clear_color: vk.ClearValue
	clear_color.color.float32 = {0.0, 0.0, 0.0, 1.0}

	color_attachment: vk.RenderingAttachmentInfo = {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = ctx.display.swapchain_image_views[image_idx],
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = clear_color,
	}

	rendering_info: vk.RenderingInfo = {
		sType = .RENDERING_INFO,
		renderArea = { offset = {0,0}, extent = ctx.display.swapchain_extent },
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
	}

	shader_flags := []vk.ShaderStageFlags{ {.VERTEX}, {.FRAGMENT} }
	shaders := []vk.ShaderEXT{vert,frag}
	unused := []vk.ShaderStageFlags{ {.TESSELLATION_CONTROL}, {.TESSELLATION_EVALUATION}, {.GEOMETRY} }
	
	vk.CmdBeginRendering(cmd_buffer, &rendering_info)

	vk.CmdBindShadersEXT(cmd_buffer, 2, raw_data(shader_flags), raw_data(shaders))
	vk.CmdBindShadersEXT(cmd_buffer, 3, raw_data(unused), nil)

	viewport: vk.Viewport = {
		x = 0.0,
		y = 0.0,
		width = f32(ctx.display.swapchain_extent.width),
		height = f32(ctx.display.swapchain_extent.height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}
	vk.CmdSetViewportWithCount(cmd_buffer, 1, &viewport)

	scissor: vk.Rect2D = {
		offset = {0,0},
		extent = ctx.display.swapchain_extent,
	}

	vk.CmdSetScissorWithCount(cmd_buffer, 1, &scissor)

	vk.CmdSetRasterizerDiscardEnable(cmd_buffer, false)

	vk.CmdSetCullMode(cmd_buffer, {.BACK})

	vk.CmdSetDepthTestEnable(cmd_buffer, false)

	vk.CmdSetDepthWriteEnable(cmd_buffer, false)

	vk.CmdSetDepthBiasEnable(cmd_buffer, false)

	vk.CmdSetStencilTestEnable(cmd_buffer, false)

	vk.CmdSetPolygonModeEXT(cmd_buffer, .FILL)

	vk.CmdSetRasterizationSamplesEXT(cmd_buffer, {._1})
	sample_mask: vk.SampleMask = 0b1 //msaa
	vk.CmdSetSampleMaskEXT(cmd_buffer, {._1}, &sample_mask)

	vk.CmdSetFrontFace(cmd_buffer, .COUNTER_CLOCKWISE) //since we flip the orientation of the tris in the shader, because vulkan and opengl have opposite NDC

	vk.CmdSetAlphaToCoverageEnableEXT(cmd_buffer, false)

	vk.CmdSetPrimitiveTopology(cmd_buffer, .TRIANGLE_LIST)
	vk.CmdSetPrimitiveRestartEnable(cmd_buffer, false)


	enabled: b32 = true
	vk.CmdSetColorBlendEnableEXT(cmd_buffer, 0, 1, &enabled)

	color_write_mask: vk.ColorComponentFlags = {.R, .G, .B, .A}
	vk.CmdSetColorWriteMaskEXT(cmd_buffer, 0, 1, &color_write_mask)

	color_blend_equation: vk.ColorBlendEquationEXT = {
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ZERO,
		alphaBlendOp = .ADD,
	}

	vk.CmdSetColorBlendEquationEXT(cmd_buffer, 0, 1, &color_blend_equation)

	//bind data and render tris

	vertex_input_attributes := []vk.VertexInputAttributeDescription2EXT{get_pos_attr_desc(), get_normal_attr_desc(), get_uv_attr_desc()}
	vertex_input_binding := get_binding_desc()

	vk.CmdSetVertexInputEXT(cmd_buffer, 1, &vertex_input_binding, u32(len(vertex_input_attributes)) , raw_data(vertex_input_attributes))

	offsets := []vk.DeviceSize{0}
	vk.CmdBindVertexBuffers(cmd_buffer, 0, 1, vbuf, raw_data(offsets))

	vk.CmdBindIndexBuffer(cmd_buffer, ibuf^, 0, .UINT32)

	vk.CmdBindDescriptorSets(cmd_buffer, .GRAPHICS, pipeline_layout, 0, 1, set, 0, nil)

	vk.CmdDrawIndexed(cmd_buffer, 6, 1, 0, 0, 0)
 
	vk.CmdEndRendering(cmd_buffer)
	vk.EndCommandBuffer(cmd_buffer)
}

//render 
render_tri :: proc(ctx: ^vk_context, state: ^render_loop_state, cmd_buffers: []vk.CommandBuffer, vert: vk.ShaderEXT, frag: vk.ShaderEXT, vbuf: ^vk.Buffer, ibuf: ^vk.Buffer, ubufs: []uniform_buffer, pipeline_layout: vk.PipelineLayout, sets: []vk.DescriptorSet){
	timeout: u64 : 100000000

	vk.WaitForFences(ctx.device, 1, &state.in_flight_fences[state.current_frame], true, timeout)


	image_index: u32
	result := vk.AcquireNextImageKHR(ctx.device, ctx.display.swapchain, timeout,
	   								 state.image_available_semaphores[state.current_frame],
									 {}, &image_index);

	if(result == .ERROR_OUT_OF_DATE_KHR){
		recreate_swapchain(ctx)
		return
	} else if (result != .SUCCESS && result != .SUBOPTIMAL_KHR){
		panic("failed to retrieve swapchain image")
	}

	vk.ResetFences(ctx.device, 1, &state.in_flight_fences[state.current_frame])

	vk.ResetCommandBuffer(cmd_buffers[state.current_frame], {})

	update_uniform_buffer(ubufs[state.current_frame], ctx)

	record_triangle_rendering(ctx, cmd_buffers[state.current_frame], vert, frag, vbuf, ibuf, pipeline_layout, &sets[state.current_frame], image_index)


	wait_semaphores := []vk.Semaphore{state.image_available_semaphores[state.current_frame]}
	wait_stages: vk.PipelineStageFlags = {.COLOR_ATTACHMENT_OUTPUT}
	signal_semaphores := []vk.Semaphore{state.render_finished_semaphores[state.current_frame]}

	submit_info: vk.SubmitInfo = {
		sType = .SUBMIT_INFO,
		waitSemaphoreCount = 1,
		pWaitSemaphores = raw_data(wait_semaphores),
		pWaitDstStageMask = &wait_stages,
		commandBufferCount = 1,
		pCommandBuffers = &cmd_buffers[state.current_frame],
		signalSemaphoreCount = 1,
		pSignalSemaphores = raw_data(signal_semaphores),
	}

	if(vk.QueueSubmit(ctx.queues.graphics_queue, 1, &submit_info, state.in_flight_fences[state.current_frame]) != .SUCCESS){
		panic("failed to submit command buffer to graphics queue")
	}

	present_info: vk.PresentInfoKHR = {
		sType = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores = &state.render_finished_semaphores[state.current_frame],
		swapchainCount = 1,
		pSwapchains = &ctx.display.swapchain,
		pImageIndices = &image_index,
		pResults = nil
	}

	result = vk.QueuePresentKHR(ctx.queues.graphics_queue, &present_info)

	if(result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR){
		recreate_swapchain(ctx)
		return
	} else if(result != .SUCCESS){
		panic("failed to present swapchain image")
	}

	state.current_frame = (state.current_frame + 1) % state.frames_in_flight
}
start_time := time.tick_now()

update_uniform_buffer :: proc(ubuf: uniform_buffer, ctx: ^vk_context){
	curr_time := time.tick_now()
	duration := time.tick_diff(start_time, curr_time)
	seconds := time.duration_seconds(duration)

	obj: ubo
	obj.model = glsl.mat4Rotate( [3]f32{0.0,0.0,1.0}, math.PI/2 * f32(seconds))
	obj.view = glsl.mat4LookAt( [3]f32{2, 2, 2}, [3]f32{0, 0, 0}, [3]f32{0, 0, 1} )
	obj.proj = glsl.mat4Perspective(math.PI/4, f32(ctx.display.swapchain_extent.width) / f32(ctx.display.swapchain_extent.height), 0.1, 10)
	obj.proj[1][1] *= -1

	mem.copy(ubuf.mapped_ptr, &obj, size_of(obj))

}






















