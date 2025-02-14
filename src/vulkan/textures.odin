package vulk

import vk "vendor:vulkan"
import vma "../vma"
import "core:image/png"
import img "core:image"
import "core:mem"
import "core:fmt"
import "core:log"



Texture :: struct{
	w: u32,
	h: u32,
	image: Image,
	view: vk.ImageView,
	sampler: vk.Sampler,
	uniform: Uniform,
}

create_texture :: proc(ctx: ^vk_context, render_state: ^render_loop_state, allocator: vma.Allocator, filename: string, binding: u32) -> Texture{
	image, err := png.load_from_file(filename, {.alpha_add_if_missing})
	if(err != nil){ panic("failed to load image") }
	defer img.destroy(image)

	buffer_size := vk.DeviceSize(len(image.pixels.buf))
	staging_buffer := create_buffer(allocator, buffer_size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})
	defer vma.destroy_buffer(allocator, staging_buffer.handle, staging_buffer.memory)

	data: rawptr
	vma.map_memory(allocator, staging_buffer.memory, &data)
	mem.copy(data, raw_data(image.pixels.buf), int(buffer_size))
	vma.unmap_memory(allocator, staging_buffer.memory)

	image_ci: ImageInfo = {
		w = u32(image.width),
		h = u32(image.height),
		size = buffer_size,
		format = .R8G8B8A8_SRGB,
		usage = {.TRANSFER_DST, .SAMPLED},
		properties = {.DEVICE_LOCAL},
	}

	tex_image := create_image(&image_ci, allocator)

	cmd_buffer := begin_single_time_command(ctx.device, ctx.queues.pools.graphics)

	transition_image_layout(ctx, cmd_buffer, tex_image.handle, .R8G8B8A8_SRGB, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
	copy_buffer_to_image(ctx, cmd_buffer, staging_buffer.handle, tex_image.handle, u32(image.width), u32(image.height))
	transition_image_layout(ctx, cmd_buffer, tex_image.handle, .R8G8B8A8_SRGB, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)

	end_single_time_command(ctx.device, ctx.queues.pools.graphics, ctx.queues.graphics_queue, &cmd_buffer)

	image_view := create_image_view(ctx.device, tex_image.handle)
	sampler := create_sampler(ctx.device, ctx.gpu)
	uniform := create_texture_uniform(ctx.device, render_state, allocator, image_view, sampler, binding)

	tex: Texture = {
		w = u32(image.width),
		h = u32(image.height),
		image = tex_image,
		view = image_view,
		sampler = sampler,
		uniform = uniform,
	}

	return tex
}


ImageInfo :: struct{
	w: u32,
	h: u32,
	size: vk.DeviceSize,
	format: vk.Format,
	usage: vk.ImageUsageFlags,
	properties: vk.MemoryPropertyFlags,
}

Image :: struct{
	handle: vk.Image,
	memory: vma.Allocation,
}

create_image :: proc(ci: ^ImageInfo, allocator: vma.Allocator) -> Image{
	image_info: vk.ImageCreateInfo = {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = { width = u32(ci.w), height = u32(ci.h), depth = 1 },
		mipLevels = 1,
		arrayLayers = 1,
		format = ci.format,
		tiling = .OPTIMAL,
		initialLayout = .UNDEFINED, //undefined means texels are discarded at first layout transition - whatever that means
		usage = ci.usage,
		sharingMode = .EXCLUSIVE,
		samples = {._1},
	}

	
	aci: vma.Allocation_Create_Info = {
		flags = {.Strategy_Min_Memory, .Strategy_Min_Time, .Strategy_Min_Offset},
		usage = .Auto,
		required_flags = ci.properties,
	}

	image: vk.Image
	mem: vma.Allocation
 

	if(vma.create_image(allocator, image_info, aci, &image, &mem, {}) != .SUCCESS){
		panic("failed to create image")
	}

	return {image, mem}
}

transition_image_layout :: proc(ctx: ^vk_context, cmd_buffer: vk.CommandBuffer, image: vk.Image, format: vk.Format, old_layout: vk.ImageLayout, new_layout: vk.ImageLayout){


	subresource_range: vk.ImageSubresourceRange = {
		aspectMask = {.COLOR},
		baseMipLevel = 0,
		levelCount = 1,
		baseArrayLayer = 0,
		layerCount = 1,
	}

	barrier: vk.ImageMemoryBarrier = {
		sType = .IMAGE_MEMORY_BARRIER,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		oldLayout = old_layout,
		newLayout = new_layout,
		image = image,
		subresourceRange = subresource_range,
	}

	src_stage: vk.PipelineStageFlags
	dst_stage: vk.PipelineStageFlags
	if(old_layout == .UNDEFINED && new_layout == .TRANSFER_DST_OPTIMAL){

		barrier.srcAccessMask = {}
		barrier.dstAccessMask = {.TRANSFER_WRITE}
		src_stage = {.TOP_OF_PIPE}
		dst_stage = {.TRANSFER}

	} else if (old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL){

		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.SHADER_READ}
		src_stage = {.TRANSFER}
		dst_stage = {.FRAGMENT_SHADER}
	} else {
		log.errorf("unsupported layout transition")
	}


	vk.CmdPipelineBarrier(cmd_buffer, src_stage, dst_stage, {}, 0, nil, 0, nil, 1, &barrier)

}

copy_buffer_to_image :: proc(ctx: ^vk_context, cmd_buffer: vk.CommandBuffer, buffer: vk.Buffer, image: vk.Image, w: u32, h: u32){
	region: vk.BufferImageCopy = {
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,

		imageSubresource = {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = 1,
		},

		imageOffset = {0,0,0},
		imageExtent = {w, h, 1},
	}

	vk.CmdCopyBufferToImage(cmd_buffer, buffer, image, .TRANSFER_DST_OPTIMAL, 1, &region)

}

create_image_view :: proc(device: vk.Device, image: vk.Image) -> (image_view: vk.ImageView){
	view_info: vk.ImageViewCreateInfo = {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image,
		viewType = .D2,
		format = .R8G8B8A8_SRGB,
		subresourceRange = {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		}
	}

	if(vk.CreateImageView(device, &view_info, nil, &image_view) != .SUCCESS){
		panic("failed to create image view")
	}

	return
}

create_sampler :: proc(device: vk.Device, gpu: vk.PhysicalDevice) -> (sampler: vk.Sampler){

	properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(gpu, &properties)

	sampler_info: vk.SamplerCreateInfo ={
		sType = .SAMPLER_CREATE_INFO,
		magFilter = .LINEAR,
		minFilter = .LINEAR,
		addressModeU = .REPEAT,
		addressModeV = .REPEAT,
		addressModeW = .REPEAT,
		anisotropyEnable = true,
		maxAnisotropy = properties.limits.maxSamplerAnisotropy,
		borderColor = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
		compareEnable = false, //comprison if for shadow map antialiasing percentage-closer filtering
		compareOp = .ALWAYS,
		mipmapMode = .LINEAR,
		mipLodBias = 0.0,
		minLod = 0.0,
		maxLod = 0.0,
	}

	if(vk.CreateSampler(device, &sampler_info, nil, &sampler) != .SUCCESS){
		panic("failed to create texture sampler")
	}

	return

}

create_texture_uniform :: proc(device: vk.Device, render_state: ^render_loop_state, allocator: vma.Allocator, view: vk.ImageView, sampler: vk.Sampler, binding: u32) -> Uniform{
	uniform: Uniform
	uniform.frames = make([]UniformBufferFrame, render_state.frames_in_flight)

	layout_binding: vk.DescriptorSetLayoutBinding = {
		binding = binding,
		descriptorType = .COMBINED_IMAGE_SAMPLER,
		descriptorCount = 1,
		stageFlags = {.FRAGMENT},
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


	pool_size: vk.DescriptorPoolSize = {
		type = .COMBINED_IMAGE_SAMPLER,
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
		
		ai: vk.DescriptorSetAllocateInfo = {
			sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool = uniform.pool,
			descriptorSetCount = 1,
			pSetLayouts = &uniform.layout,
		}

		if(vk.AllocateDescriptorSets(device, &ai, &uniform.frames[i].set) != .SUCCESS){
			panic("failed to allocate descriptor sets")
		}

		image_info: vk.DescriptorImageInfo = {
			imageLayout = .SHADER_READ_ONLY_OPTIMAL,
			imageView = view,
			sampler = sampler,
		}

		desc_write: vk.WriteDescriptorSet = {
			sType = .WRITE_DESCRIPTOR_SET,
			dstSet = uniform.frames[i].set,
			dstBinding = binding,
			dstArrayElement = 0,
			descriptorType = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			pImageInfo = &image_info,
		}

		vk.UpdateDescriptorSets(device, 1, &desc_write, 0, nil)
	}

	return uniform
}


destroy_texture :: proc(device: vk.Device, allocator: vma.Allocator, tex: ^Texture){
	vma.destroy_image(allocator, tex.image.handle, tex.image.memory)
	vk.DestroyImageView(device, tex.view, nil)
	vk.DestroySampler(device, tex.sampler, nil)
	destroy_uniform(device, allocator, &tex.uniform)
}






























