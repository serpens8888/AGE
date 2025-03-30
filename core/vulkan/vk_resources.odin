package vulk

import vk "vendor:vulkan"
import "vma"
import "core:slice"
import "core:os"
import "core:fmt"
import "core:mem"


@(require_results)
allocate_buffer :: proc(
    allocator: vma.Allocator,
    buffer_info: ^vk.BufferCreateInfo,
    usage: vk.BufferUsageFlags2,
    mem_properties: vk.MemoryPropertyFlags,
    alloc_flags: vma.Allocation_Create_Flags = {.Strategy_Min_Memory, .Strategy_Min_Time, .Strategy_Min_Offset},
) -> (buffer: Allocated_Buffer){

    usage_info: vk.BufferUsageFlags2CreateInfo = {
        sType = .BUFFER_USAGE_FLAGS_2_CREATE_INFO,
        pNext = nil,
        usage = usage,
    }

    buffer_info.pNext = &usage_info
    
    allocation_create_info: vma.Allocation_Create_Info = {
        flags = alloc_flags,
        usage = .Auto,
        required_flags = mem_properties,
    }

    check_vk(vma.create_buffer(allocator,
        buffer_info^,
        allocation_create_info,
        &buffer.handle,
        &buffer.allocation,
        &buffer.alloc_info)
    )

    return
}

free_buffer :: proc(allocator: vma.Allocator, buffer: Allocated_Buffer){
    vma.unmap_memory(allocator, buffer.allocation)
    vma.destroy_buffer(allocator, buffer.handle, buffer.allocation)
}



@(require_results)
allocate_image :: proc(
    allocator: vma.Allocator,
    image_info: vk.ImageCreateInfo,
    mem_properties: vk.MemoryPropertyFlags,
    alloc_flags: vma.Allocation_Create_Flags = {.Strategy_Min_Memory, .Strategy_Min_Time, .Strategy_Min_Offset},
) -> (image: Allocated_Image){

    allocation_create_info: vma.Allocation_Create_Info = {
        flags = alloc_flags,
        usage = .Auto,
        required_flags = mem_properties
    }

    check_vk(vma.create_image(allocator, image_info, allocation_create_info, &image.handle, &image.allocation, &image.alloc_info))

    return
}

@(require_results)
create_uniform_buffer :: proc(device: vk.Device, allocator: vma.Allocator, size: vk.DeviceSize) -> (buffer: Allocated_Buffer){
    buffer_info := make_buffer_create_info(size, {})
    buffer = allocate_buffer(allocator, &buffer_info, {.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS}, {.HOST_VISIBLE, .HOST_COHERENT})

    check_vk(vma.map_memory(allocator, buffer.allocation, &buffer.mapped_ptr))

    address_info: vk.BufferDeviceAddressInfo = {
        sType = .BUFFER_DEVICE_ADDRESS_INFO,
        buffer = buffer.handle
    }

    buffer.address = vk.GetBufferDeviceAddress(device, &address_info)

    return
}

@(require_results)
create_storage_buffer :: proc(device: vk.Device, allocator: vma.Allocator, size: vk.DeviceSize) -> (buffer: Allocated_Buffer){
    buffer_info := make_buffer_create_info(size, {})
    buffer = allocate_buffer(allocator, &buffer_info, {.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS}, {.HOST_VISIBLE, .HOST_COHERENT})

    check_vk(vma.map_memory(allocator, buffer.allocation, &buffer.mapped_ptr))

    address_info: vk.BufferDeviceAddressInfo = {
        sType = .BUFFER_DEVICE_ADDRESS_INFO,
        buffer = buffer.handle
    }

    buffer.address = vk.GetBufferDeviceAddress(device, &address_info)
    return buffer
}

@(require_results)
create_staging_buffer :: #force_inline proc(allocator: vma.Allocator, size: vk.DeviceSize) -> Allocated_Buffer{
    info := make_buffer_create_info(size, {}) 
    return allocate_buffer(allocator, &info, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})
}

@(require_results)
create_vertex_buffer :: proc(device: vk.Device, allocator: vma.Allocator, verts: []Vertex) -> (buffer: Allocated_Buffer){
    size:= len(verts) * size_of(Vertex)
    staging_buffer := create_staging_buffer(allocator, vk.DeviceSize(size))

	data: rawptr
	vma.map_memory(allocator, staging_buffer.allocation, &data)
	mem.copy(data, raw_data(verts), int(size))
	vma.unmap_memory(allocator, staging_buffer.allocation)

    buffer_info := make_buffer_create_info(vk.DeviceSize(size), {})
    buffer = allocate_buffer(allocator, &buffer_info, {.VERTEX_BUFFER, .TRANSFER_DST, .SHADER_DEVICE_ADDRESS}, {.HOST_VISIBLE, .HOST_COHERENT})


    //TODO: finish this fn and do the index buffer one too

    return 
}

@(require_results)
create_index_buffer :: proc(device: vk.Device, allocator: vma.Allocator, indices: []u32) -> (buffer: Allocated_Buffer){
   return 
}


@(require_results)
create_pipeline_layout :: proc(device: vk.Device, layouts: []vk.DescriptorSetLayout, ranges: []vk.PushConstantRange) -> (layout: vk.PipelineLayout){
    
    create_info: vk.PipelineLayoutCreateInfo = {
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = u32(len(layouts)),
        pSetLayouts = raw_data(layouts),
        pushConstantRangeCount = u32(len(ranges)),
        pPushConstantRanges = raw_data(ranges),
    }

    check_vk(vk.CreatePipelineLayout(device, &create_info, nil, &layout))

    return
}
@(require_results)
create_shader_object :: proc(
    device: vk.Device,
    filepath: string,
    entrypoint: cstring,
    stage, next_stage: vk.ShaderStageFlags, 
    layouts: []vk.DescriptorSetLayout,
    ranges: []vk.PushConstantRange,
    specialization: ^vk.SpecializationInfo = {},
    flags: vk.ShaderCreateFlagsEXT = {},
) -> (shader: vk.ShaderEXT){

    spirv, err := os.read_entire_file_from_filename_or_err(filepath)
    defer delete(spirv)
    if(err != nil){
        fmt.eprintln("error reading in spirv file: ", err)
        panic("file read failed")
    }

    shader_info: vk.ShaderCreateInfoEXT = {
        sType = .SHADER_CREATE_INFO_EXT,
        flags = flags,
        stage = stage,
        nextStage = next_stage,
        codeType = .SPIRV,
        codeSize = len(spirv),
        pCode = raw_data(spirv),
        pName = entrypoint,
        setLayoutCount = u32(len(layouts)),
        pSetLayouts = raw_data(layouts),
        pushConstantRangeCount = u32(len(ranges)),
        pPushConstantRanges = raw_data(ranges),
        pSpecializationInfo = specialization,
    }

    check_vk(vk.CreateShadersEXT(device, 1, &shader_info, nil, &shader))

    return


}

//specialize_shader_object(device: vk.Device, base: vk.ShaderEXT, specialization: ^vk.SpecializationInfo) -> vk.ShaderEXT

create_image_view :: proc(
    device: vk.Device,
    image: vk.Image,
    format: vk.Format,
    view_type: vk.ImageViewType = .D2,
    components: vk.ComponentMapping = {.IDENTITY, .IDENTITY, .IDENTITY, .IDENTITY},
    subresource_range: vk.ImageSubresourceRange = {{.COLOR}, 0, 1, 0, 1}
) -> (view: vk.ImageView){
    
    create_info: vk.ImageViewCreateInfo = {
        sType = .IMAGE_VIEW_CREATE_INFO,
        image = image,
        viewType = view_type,
        format = format,
        components = components,
        subresourceRange = subresource_range,
    }

    check_vk(vk.CreateImageView(device, &create_info, nil, &view))

    return
}










