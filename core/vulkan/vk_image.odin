package vulk


import "core:fmt"
import "core:image"
import "core:image/png"
import "core:mem"
import vk "vendor:vulkan"
import "vma"

Allocated_Image :: struct {
    //images need to be put into descriptor buffers before being passed
    handle:     vk.Image, //vulkan handle for image
    allocation: vma.Allocation, //vma allocation on gpu
    alloc_info: vma.Allocation_Info,
    view:       vk.ImageView, //image view of the allocated image
    extent:     vk.Extent3D, //image extent
    format:     vk.Format, //format of the image
    layout:     vk.ImageLayout,
}

fallback_image: image.Image = {
    width    = 4,
    height   = 4,
    channels = 4,
    depth    = 8,
}

// odinfmt: disable
fallback_pixels: []u8 = {
    255,0,255,255,   0,0,0,255,       255,0,255,255,   0,0,0,255,
    0,0,0,255,       255,0,255,255,   0,0,0,255,       255,0,255,255,
    255,0,255,255,   0,0,0,255,       255,0,255,255,   0,0,0,255,
    0,0,0,255,       255,0,255,255,   0,0,0,255,       255,0,255,255,
}
// odinfmt: enable

@(require_results)
create_image :: proc(
    file: string,
    ctx: Context,
    pool: vk.CommandPool,
) -> (
    img: Allocated_Image,
    err: Error,
) {
    decoded_image, image_err := image.load_from_file(
        file,
        {.alpha_add_if_missing},
    )
    pixels: []u8
    if image_err == nil {
        pixels = decoded_image.pixels.buf[:]
    } else {
        pixels = fallback_pixels
        decoded_image = &fallback_image
    }

    defer {
        if image_err == nil do image.destroy(decoded_image)
    }

    size := vk.DeviceSize(len(pixels)) //multiplying by size_of(u8) is redundant
    staging := create_staging_buffer(ctx.allocator, size) or_return
    defer free_buffer(ctx.allocator, staging)

    mem.copy(staging.mapped_ptr, &pixels[0], len(pixels))

    ici: vk.ImageCreateInfo = {
        sType = .IMAGE_CREATE_INFO,
        imageType = .D2,
        extent = {
            width = u32(decoded_image.width),
            height = u32(decoded_image.height),
            depth = 1,
        },
        mipLevels = 1,
        arrayLayers = 1,
        format = find_format(decoded_image^),
        tiling = .OPTIMAL,
        initialLayout = .UNDEFINED,
        usage = {.SAMPLED, .TRANSFER_DST},
        sharingMode = .EXCLUSIVE,
        samples = {._1}, //texture images have 1 sample per pixel
    }

    aci: vma.Allocation_Create_Info = {
        flags          = {
            .Strategy_Min_Time,
            .Strategy_Min_Memory,
            .Strategy_Min_Offset,
        },
        usage          = .Auto,
        required_flags = {.DEVICE_LOCAL},
    }

    handle: vk.Image
    allocation: vma.Allocation
    alloc_info: vma.Allocation_Info

    vma.create_image(
        ctx.allocator,
        ici,
        aci,
        &handle,
        &allocation,
        &alloc_info,
    )
    cmd := begin_single_time_cmd(ctx.device, pool) or_return

    transition_image_layout(
        cmd,
        handle,
        ici.format,
        .UNDEFINED,
        .TRANSFER_DST_OPTIMAL,
    )

    copy_buffer_to_image(
        cmd,
        staging,
        handle,
        ici.extent.width,
        ici.extent.height,
    )

    transition_image_layout(
        cmd,
        handle,
        ici.format,
        .TRANSFER_DST_OPTIMAL,
        .SHADER_READ_ONLY_OPTIMAL,
    )

    submit_single_time_cmd(ctx.device, pool, ctx.queue.handle, &cmd) or_return

    view := create_image_view(ctx.device, handle, ici.format) or_return



    return {
            handle,
            allocation,
            alloc_info,
            view,
            ici.extent,
            ici.format,
            .SHADER_READ_ONLY_OPTIMAL,
        },
        nil

}

destroy_image :: proc(ctx: Context, img: Allocated_Image) {
    vk.DestroyImageView(ctx.device, img.view, nil)
    vma.destroy_image(ctx.allocator, img.handle, img.allocation)
}

find_format :: proc(img: image.Image) -> vk.Format {
    switch {
    case img.depth == 8 && img.channels == 1:
        return .R8_SRGB
    case img.depth == 8 && img.channels == 2:
        return .R8G8_SRGB
    case img.depth == 8 && img.channels == 3:
        return .R8G8B8_SRGB
    case img.depth == 8 && img.channels == 4:
        return .R8G8B8A8_SRGB
    case:
        fmt.panicf(
            "unsupported image format depth: %d, channels: %d",
            img.depth,
            img.channels,
        )
    }

    return .UNDEFINED
}

transition_image_layout :: proc(
    cmd: vk.CommandBuffer,
    image: vk.Image,
    format: vk.Format,
    old_layout, new_layout: vk.ImageLayout,
) {

    subresource_range: vk.ImageSubresourceRange = {
        aspectMask     = {.COLOR},
        baseMipLevel   = 0,
        levelCount     = 1,
        baseArrayLayer = 0,
        layerCount     = 1,
    }

    barrier: vk.ImageMemoryBarrier = {
        sType               = .IMAGE_MEMORY_BARRIER,
        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        oldLayout           = old_layout,
        newLayout           = new_layout,
        image               = image,
        subresourceRange    = subresource_range,
    }

    src_stage: vk.PipelineStageFlags
    src_access: vk.AccessFlags
    dst_stage: vk.PipelineStageFlags
    dst_access: vk.AccessFlags

    // Source layout transitions (what the image was last used for)
    #partial switch old_layout {
    case .UNDEFINED:
        src_access = {}
        src_stage = {.TOP_OF_PIPE}
    case .TRANSFER_SRC_OPTIMAL:
        src_access = {.TRANSFER_READ}
        src_stage = {.TRANSFER}
    case .TRANSFER_DST_OPTIMAL:
        src_access = {.TRANSFER_WRITE}
        src_stage = {.TRANSFER}
    case .SHADER_READ_ONLY_OPTIMAL:
        src_access = {.SHADER_READ}
        src_stage = {.FRAGMENT_SHADER, .COMPUTE_SHADER}
    case .COLOR_ATTACHMENT_OPTIMAL:
        src_access = {.COLOR_ATTACHMENT_WRITE}
        src_stage = {.COLOR_ATTACHMENT_OUTPUT}
    case .DEPTH_STENCIL_ATTACHMENT_OPTIMAL:
        src_access = {.DEPTH_STENCIL_ATTACHMENT_WRITE}
        src_stage = {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}
    case .DEPTH_STENCIL_READ_ONLY_OPTIMAL:
        src_access = {.DEPTH_STENCIL_ATTACHMENT_READ}
        src_stage = {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}
    }

    // Destination layout transitions (what the image will be used for next)
    #partial switch new_layout {
    case .UNDEFINED:
        // Should never happen, but just in case
        dst_access = {}
        dst_stage = {.TOP_OF_PIPE}
    case .TRANSFER_SRC_OPTIMAL:
        dst_access = {.TRANSFER_READ}
        dst_stage = {.TRANSFER}
    case .TRANSFER_DST_OPTIMAL:
        dst_access = {.TRANSFER_WRITE}
        dst_stage = {.TRANSFER}
    case .SHADER_READ_ONLY_OPTIMAL:
        dst_access = {.SHADER_READ}
        dst_stage = {.FRAGMENT_SHADER, .COMPUTE_SHADER}
    case .COLOR_ATTACHMENT_OPTIMAL:
        dst_access = {.COLOR_ATTACHMENT_WRITE}
        dst_stage = {.COLOR_ATTACHMENT_OUTPUT}
    case .DEPTH_STENCIL_ATTACHMENT_OPTIMAL:
        dst_access = {.DEPTH_STENCIL_ATTACHMENT_WRITE}
        dst_stage = {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}
    case .DEPTH_STENCIL_READ_ONLY_OPTIMAL:
        dst_access = {.DEPTH_STENCIL_ATTACHMENT_READ}
        dst_stage = {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}
    }

    barrier.srcAccessMask = src_access
    barrier.dstAccessMask = dst_access

    if (src_stage == {} || dst_stage == {}) {
        panic("unsupported layout transition")
    }
    vk.CmdPipelineBarrier(
        cmd,
        src_stage,
        dst_stage,
        {},
        0,
        nil,
        0,
        nil,
        1,
        &barrier,
    )
}

copy_buffer_to_image :: proc(
    cmd: vk.CommandBuffer,
    buffer: Allocated_Buffer,
    image: vk.Image,
    width, height: u32,
) {
    region: vk.BufferImageCopy = {
        bufferOffset = 0,
        bufferRowLength = 0, //assuming they are tightly packed
        bufferImageHeight = 0, //assuming they are tightly packed
        imageSubresource = {
            aspectMask = {.COLOR},
            mipLevel = 0,
            baseArrayLayer = 0,
            layerCount = 1,
        },
        imageOffset = {0, 0, 0},
        imageExtent = {width, height, 1},
    }

    vk.CmdCopyBufferToImage(
        cmd,
        buffer.handle,
        image,
        .TRANSFER_DST_OPTIMAL,
        1,
        &region,
    )

}

@(require_results)
create_image_view :: proc(
    device: vk.Device,
    image: vk.Image,
    format: vk.Format,
    view_type: vk.ImageViewType = .D2,
    components: vk.ComponentMapping = {
        .IDENTITY,
        .IDENTITY,
        .IDENTITY,
        .IDENTITY,
    },
    subresource_range: vk.ImageSubresourceRange = {{.COLOR}, 0, 1, 0, 1},
) -> (
    view: vk.ImageView,
    err: Error,
) {

    create_info: vk.ImageViewCreateInfo = {
        sType            = .IMAGE_VIEW_CREATE_INFO,
        image            = image,
        viewType         = view_type,
        format           = format,
        components       = components,
        subresourceRange = subresource_range,
    }

    check_vk(vk.CreateImageView(device, &create_info, nil, &view)) or_return

    return
}

