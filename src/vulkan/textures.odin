package vulk

import vk "vendor:vulkan"
import vma "../vma"
import "core:image/png"
import img "core:image"
import "core:mem"
import "core:fmt"
import "core:log"



Texture :: struct{
	image: Image,
	view: vk.ImageView,
	layout: vk.ImageLayout,
	id: u32,
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


create_texture :: proc(ctx: ^vk_context, allocator: vma.Allocator, filename: string, sampler_id: u32) -> Texture{
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

	return {tex_image, image_view, .SHADER_READ_ONLY_OPTIMAL, 0}
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

	#partial switch old_layout{
		case .UNDEFINED: {barrier.srcAccessMask = {}; src_stage = {.TOP_OF_PIPE}}
		case .TRANSFER_DST_OPTIMAL: {barrier.srcAccessMask = {.TRANSFER_WRITE}; src_stage = {.TRANSFER}}
	}

	#partial switch new_layout{
		case .TRANSFER_DST_OPTIMAL: {barrier.dstAccessMask = {.TRANSFER_WRITE}; dst_stage = {.TRANSFER}}
		case .SHADER_READ_ONLY_OPTIMAL: {barrier.dstAccessMask = {.SHADER_READ}; dst_stage = {.FRAGMENT_SHADER}}
	}

	if((barrier.srcAccessMask == {} && src_stage == {}) || (barrier.dstAccessMask == {} && dst_stage == {})){
		panic("unsupported layout transition")
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

Sampler :: struct{
	handle: vk.Sampler,
	id: u32,
}

create_sampler :: proc(device: vk.Device, gpu: vk.PhysicalDevice) -> (sampler: Sampler){

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

	if(vk.CreateSampler(device, &sampler_info, nil, &sampler.handle) != .SUCCESS){
		panic("failed to create texture sampler")
	}

	return

}

Texture_Array :: struct{
	buffer: Buffer,
	address: vk.DeviceAddress,
	layout: vk.DescriptorSetLayout,
	image_offset: vk.DeviceSize,
	sampler_offset: vk.DeviceSize,
}

create_texture_array :: proc(ctx: ^vk_context, allocator: vma.Allocator, stage_flags: vk.ShaderStageFlags, textures: []^Texture, samplers: []^Sampler) -> Texture_Array{

	image_binding: vk.DescriptorSetLayoutBinding = {
		binding = 0,
		descriptorType = .SAMPLED_IMAGE,
		descriptorCount = u32(len(textures)),
		stageFlags = stage_flags,
	}

	sampler_binding: vk.DescriptorSetLayoutBinding = {
		binding = 1,
		descriptorType = .SAMPLER,
		descriptorCount = u32(len(samplers)),
		stageFlags = stage_flags,
	}

	bindings: []vk.DescriptorSetLayoutBinding = {image_binding, sampler_binding}
	layout_create_info: vk.DescriptorSetLayoutCreateInfo = {
		sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		flags = {.DESCRIPTOR_BUFFER_EXT},
		bindingCount = u32(len(bindings)),
		pBindings = raw_data(bindings),
	}
	
	layout: vk.DescriptorSetLayout
	result := vk.CreateDescriptorSetLayout(ctx.device, &layout_create_info, nil, &layout)
	if(result != .SUCCESS){
		fmt.println(result)
		panic("failed to create descriptor set layout")
	}

	size: vk.DeviceSize
	vk.GetDescriptorSetLayoutSizeEXT(ctx.device, layout, &size)
	size = align_size(size, ctx.gpu_properties.descriptor_buffer.descriptorBufferOffsetAlignment)

	image_offset: vk.DeviceSize
	sampler_offset: vk.DeviceSize
	vk.GetDescriptorSetLayoutBindingOffsetEXT(ctx.device, layout, 0, &image_offset)
	vk.GetDescriptorSetLayoutBindingOffsetEXT(ctx.device, layout, 1, &sampler_offset)

	buffer := create_buffer(allocator, size, {.SAMPLER_DESCRIPTOR_BUFFER_EXT, .RESOURCE_DESCRIPTOR_BUFFER_EXT, .SHADER_DEVICE_ADDRESS}, {.HOST_VISIBLE, .HOST_COHERENT})

	info: vk.BufferDeviceAddressInfo = {
		sType = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = buffer.handle,
	}

	buffer_address := vk.GetBufferDeviceAddress(ctx.device, &info)

	mapped_ptr: rawptr
	vma.map_memory(allocator, buffer.memory, &mapped_ptr)
	defer vma.unmap_memory(allocator, buffer.memory)

	for &image, i in textures{
		image_info: vk.DescriptorImageInfo = { {}, image.view, image.layout}
		textures[i].id = u32(i+5)


		descriptor_info: vk.DescriptorGetInfoEXT = {
			sType = .DESCRIPTOR_GET_INFO_EXT,
			type = .SAMPLED_IMAGE,
			data = {pSampledImage = &image_info},
		}

		offset := vk.DeviceSize(i * ctx.gpu_properties.descriptor_buffer.sampledImageDescriptorSize) + image_offset
		dst := rawptr(uintptr(mapped_ptr) + uintptr(offset))
		vk.GetDescriptorEXT(ctx.device, &descriptor_info, ctx.gpu_properties.descriptor_buffer.sampledImageDescriptorSize, dst)

	}

	for &sampler, i in samplers{
		sampler_info: vk.DescriptorImageInfo = {sampler.handle, {}, {}}
		sampler.id = u32(i)

		descriptor_info: vk.DescriptorGetInfoEXT = {
			sType = .DESCRIPTOR_GET_INFO_EXT,
			type = .SAMPLER,
			data = {pSampledImage = &sampler_info},
		}

		offset := vk.DeviceSize(i * ctx.gpu_properties.descriptor_buffer.samplerDescriptorSize) + sampler_offset
		dst := rawptr(uintptr(mapped_ptr) + uintptr(offset))
		vk.GetDescriptorEXT(ctx.device, &descriptor_info, ctx.gpu_properties.descriptor_buffer.samplerDescriptorSize, dst)

	}




	return {buffer, buffer_address, layout, image_offset, sampler_offset}
}


destroy_texture :: proc(device: vk.Device, allocator: vma.Allocator, tex: ^Texture){
	vma.destroy_image(allocator, tex.image.handle, tex.image.memory)
	vk.DestroyImageView(device, tex.view, nil)
}






























