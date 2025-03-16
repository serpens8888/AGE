package vulk

import "vma"
import vk "vendor:vulkan"
import "core:slice"
import "core:fmt"

@(require_results)
make_command_buffer_allocate_info :: proc(pool: vk.CommandPool, count: u32) -> vk.CommandBufferAllocateInfo{
    
    return {
        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        pNext = nil,
        commandPool = pool,
        commandBufferCount = count,
        level = .PRIMARY,
    }
}

@(require_results)
make_command_buffer_begin_info :: proc(flags: vk.CommandBufferUsageFlags) -> vk.CommandBufferBeginInfo{
    return{
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        pNext = nil,
        pInheritanceInfo = nil,
        flags = flags,
    }
}

@(require_results)
make_command_buffer_submit_info :: proc(cmd: vk.CommandBuffer) -> vk.CommandBufferSubmitInfo{
    return{
        sType = .COMMAND_BUFFER_SUBMIT_INFO,
        pNext = nil,
        commandBuffer = cmd,
        deviceMask = 0,
    }
}

@(require_results)
make_semaphore_submit_info :: proc(stage_mask: vk.PipelineStageFlags2, semaphore: vk.Semaphore, value: u64 = 1) -> vk.SemaphoreSubmitInfo{
    return{
        sType = .SEMAPHORE_SUBMIT_INFO,
        pNext = nil,
        semaphore = semaphore,
        stageMask = stage_mask,
        deviceIndex = 0,
        value = value,
    }
}

@(require_results)
make_submit_info :: proc(
    cmd_infos: []vk.CommandBufferSubmitInfo,
    signal_infos: []vk.SemaphoreSubmitInfo,
    wait_infos: []vk.SemaphoreSubmitInfo
) -> vk.SubmitInfo2{
    return{
        sType = .SUBMIT_INFO_2,

        commandBufferInfoCount = u32(len(cmd_infos)),
        pCommandBufferInfos = raw_data(cmd_infos),

        signalSemaphoreInfoCount = u32(len(signal_infos)),
        pSignalSemaphoreInfos = raw_data(wait_infos),

        waitSemaphoreInfoCount = u32(len(wait_infos)),
        pWaitSemaphoreInfos = raw_data(wait_infos),
    }
}

@(require_results)
make_image_create_info :: proc(format: vk.Format, usage: vk.ImageUsageFlags, extent: vk.Extent3D) -> vk.ImageCreateInfo{
    return{
        sType = .IMAGE_CREATE_INFO,
        imageType = .D2,
        format = format,
        extent = extent,
        mipLevels = 1,
        arrayLayers = 1,
        samples = {._1},
        tiling = .OPTIMAL,
        usage = usage,
        sharingMode = .EXCLUSIVE,
    }
}

@(require_results)
make_shared_image_create_info :: proc(format: vk.Format, usage: vk.ImageUsageFlags, extent: vk.Extent3D, families: []u32) -> vk.ImageCreateInfo{
    
    slice.sort(families)
    distinct_families := slice.unique(families)

    assert(len(distinct_families) > 0, "must pass in queue families to create_shared_buffer")

    if(len(distinct_families) == 1){
        return make_image_create_info(format, usage, extent)
    }

    return{
        sType = .IMAGE_CREATE_INFO,
        imageType = .D2,
        format = format,
        extent = extent,
        mipLevels = 1,
        arrayLayers = 1,
        samples = {._1},
        tiling = .OPTIMAL,
        usage = usage,
        sharingMode = .CONCURRENT,
        queueFamilyIndexCount = u32(len(distinct_families)),
        pQueueFamilyIndices = raw_data(distinct_families),
    }
}

@(require_results)
make_buffer_create_info :: proc(size: vk.DeviceSize, flags: vk.BufferCreateFlags) -> vk.BufferCreateInfo{

    return {
        sType = .BUFFER_CREATE_INFO,
        flags = flags,
        size = size,
        sharingMode = .EXCLUSIVE,
    }
}

@(require_results)
make_shared_buffer_create_info :: proc(size: vk.DeviceSize, flags: vk.BufferCreateFlags, families: []u32) -> vk.BufferCreateInfo{

    slice.sort(families)
    distinct_families := slice.unique(families)

    assert(len(distinct_families) > 0, "must pass in queue families to create_shared_buffer")

    if(len(distinct_families) == 1){
        return make_buffer_create_info(size, flags)
    }
        

    return {
        sType = .BUFFER_CREATE_INFO,
        flags = flags,
        size = size,
        sharingMode = .CONCURRENT,
        queueFamilyIndexCount = u32(len(distinct_families)),
        pQueueFamilyIndices = raw_data(distinct_families)
    }
}


















