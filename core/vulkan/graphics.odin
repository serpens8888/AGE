package vulk

import "core:fmt"
import "core:mem"
import "core:slice"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"
import "vma"

Graphics_Module :: struct {
    window:              ^sdl.Window,
    surface:             vk.SurfaceKHR,
    swapchain:           Swapchain,
    depth_stencil_image: Allocated_Image,
}

Swapchain :: struct {
    handle: vk.SwapchainKHR, //handle to swapchain
    images: []Allocated_Image, //the swapchains images
    format: vk.Format, //the formap of the swapchain images
    extent: vk.Extent2D, //the extent of the swapchain images
}


create_graphics_module :: proc(
    ctx: Context,
    pool: vk.CommandPool,
    window_name: cstring,
    w, h: i32,
    flags: sdl.WindowFlags,
) -> (
    mod: Graphics_Module,
    err: Error,
) {
    mod.window = create_window("foo", w, h, flags + {.VULKAN}) or_return

    mod.surface = create_surface(mod.window, ctx.instance) or_return

    mod.swapchain = create_swapchain(
        ctx.device,
        ctx.gpu,
        mod.surface,
        mod.window,
    ) or_return

    mod.depth_stencil_image = create_depth_stencil_image(
        ctx,
        pool,
        mod.swapchain.extent,
    ) or_return

    return
}

destroy_graphics_module :: proc(ctx: Context, mod: ^Graphics_Module) {
    destroy_swapchain(ctx.device, &mod.swapchain)
    vk.DestroySurfaceKHR(ctx.instance, mod.surface, nil)
    sdl.DestroyWindow(mod.window)
    destroy_image(ctx, mod.depth_stencil_image)
}




create_window :: proc(
    name: cstring,
    w, h: i32,
    flags: sdl.WindowFlags,
) -> (
    window: ^sdl.Window,
    err: Error,
) {

    flags_vk := flags + {.VULKAN}

    window = sdl.CreateWindow(name, w, h, flags_vk)

    if (!sdl.SetWindowMinimumSize(window, 1, 1)) {
        return nil, .SDL_FAILURE
    }

    return

}

create_surface :: proc(
    window: ^sdl.Window,
    instance: vk.Instance,
) -> (
    surface: vk.SurfaceKHR,
    err: Error,
) {
    if (!sdl.Vulkan_CreateSurface(window, instance, nil, &surface)) {
        return {}, .SDL_FAILURE
    }
    return
}

create_swapchain :: proc(
    device: vk.Device,
    gpu: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
    window: ^sdl.Window,
    old_swapchain: vk.SwapchainKHR = 0x0,
    sharing_mode: vk.SharingMode = .EXCLUSIVE,
    sharing_queues: []GPU_Queue = {}, //graphics queue and present queue, if separate... or whatever you want
) -> (
    swapchain: Swapchain,
    err: Error,
) {

    format := select_swapchain_format(
        gpu,
        surface,
        {.B8G8R8A8_SRGB, .SRGB_NONLINEAR},
    ) or_return
    present_mode := select_swapchain_present_mode(
        gpu,
        surface,
        .FIFO,
    ) or_return

    capabilities: vk.SurfaceCapabilitiesKHR
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(gpu, surface, &capabilities)
    extent := get_swapchain_extent(capabilities, window)

    image_count: u32 = 2
    if (capabilities.minImageCount == capabilities.maxImageCount ||
           capabilities.minImageCount > image_count) {
        image_count = capabilities.minImageCount
    }

    create_info: vk.SwapchainCreateInfoKHR = {
        sType            = .SWAPCHAIN_CREATE_INFO_KHR,
        surface          = surface,
        minImageCount    = image_count,
        imageFormat      = format.format,
        imageColorSpace  = format.colorSpace,
        imageExtent      = extent,
        imageArrayLayers = 1,
        imageUsage       = {.COLOR_ATTACHMENT},
        imageSharingMode = .EXCLUSIVE,
        preTransform     = capabilities.currentTransform,
        compositeAlpha   = {.OPAQUE},
        presentMode      = present_mode,
        clipped          = true,
        oldSwapchain     = old_swapchain,
    }

    if (sharing_mode == .CONCURRENT) {
        sharing_families := make([]u32, len(sharing_queues)) or_return
        defer delete(sharing_families)

        for &family, i in sharing_families {
            family = sharing_queues[i].family
        }

        slice.sort(sharing_families)
        distinct_families := slice.unique(sharing_families)

        assert(
            len(distinct_families) > 0,
            "must pass GPU_Queues into create_swapchain if sharing_mode is set to .CONCURRENT",
        )

        if (len(distinct_families) > 1) {
            create_info.imageSharingMode = .CONCURRENT
            create_info.queueFamilyIndexCount = u32(len(distinct_families))
            create_info.pQueueFamilyIndices = raw_data(distinct_families)
        }
    }

    check_vk(
        vk.CreateSwapchainKHR(device, &create_info, nil, &swapchain.handle),
    ) or_return

    vk.GetSwapchainImagesKHR(device, swapchain.handle, &image_count, nil)

    swapchain_images := make([]vk.Image, image_count) or_return
    defer delete(swapchain_images)

    vk.GetSwapchainImagesKHR(
        device,
        swapchain.handle,
        &image_count,
        raw_data(swapchain_images),
    )


    swapchain_views := make([]vk.ImageView, image_count) or_return
    defer delete(swapchain_views)

    for &view, i in swapchain_views {
        view = create_image_view(
            device,
            swapchain_images[i],
            format.format,
        ) or_return
    }

    swapchain.extent = extent
    swapchain.format = format.format

    swapchain.images = make([]Allocated_Image, image_count)

    for &image, i in swapchain.images {
        image = {
            handle = swapchain_images[i],
            view   = swapchain_views[i],
            extent = {swapchain.extent.width, swapchain.extent.height, 0},
            format = swapchain.format,
            layout = .UNDEFINED,
            mips   = 1,
            aspect = {.COLOR},
        }
    }

    return
}


select_swapchain_format :: proc(
    gpu: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
    requested: vk.SurfaceFormatKHR,
) -> (
    surface_format: vk.SurfaceFormatKHR,
    err: mem.Allocator_Error,
) {

    format_count: u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(gpu, surface, &format_count, nil)

    formats := make([]vk.SurfaceFormatKHR, format_count) or_return
    defer delete(formats)

    vk.GetPhysicalDeviceSurfaceFormatsKHR(
        gpu,
        surface,
        &format_count,
        raw_data(formats),
    )
    for format in formats {
        if (format == requested) {
            return format, .None
        }
    }
    return formats[0], .None
}

select_swapchain_present_mode :: proc(
    gpu: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
    requested: vk.PresentModeKHR,
) -> (
    present_mode: vk.PresentModeKHR,
    err: mem.Allocator_Error,
) {

    present_mode_count: u32
    vk.GetPhysicalDeviceSurfacePresentModesKHR(
        gpu,
        surface,
        &present_mode_count,
        nil,
    )

    present_modes := make([]vk.PresentModeKHR, present_mode_count) or_return
    defer delete(present_modes)

    vk.GetPhysicalDeviceSurfacePresentModesKHR(
        gpu,
        surface,
        &present_mode_count,
        raw_data(present_modes),
    )

    for mode in present_modes {
        if (mode == requested) {
            return mode, nil
        }
    }

    return .FIFO, nil //guaranteed to be there
}


get_swapchain_extent :: proc(
    capabilities: vk.SurfaceCapabilitiesKHR,
    window: ^sdl.Window,
) -> vk.Extent2D {

    if (capabilities.currentExtent.width != max(u32)) {
        return capabilities.currentExtent
    }

    w, h: i32
    sdl.GetWindowSizeInPixels(window, &w, &h)

    extent: vk.Extent2D = {u32(w), u32(h)}

    //clamp window size in pixels to be within the min/max extent our surface is capable of
    extent.width = clamp(
        extent.width,
        capabilities.minImageExtent.width,
        capabilities.maxImageExtent.width,
    )
    extent.height = clamp(
        extent.height,
        capabilities.minImageExtent.height,
        capabilities.maxImageExtent.height,
    )

    return extent
}

destroy_swapchain :: proc(device: vk.Device, swapchain: ^Swapchain) {
    for image in swapchain.images {
        vk.DestroyImageView(device, image.view, nil)
    }
    vk.DestroySwapchainKHR(device, swapchain.handle, nil)
    delete(swapchain.images)
}


@(require_results)
recreate_swapchain :: proc(
    ctx: Context,
    mod: ^Graphics_Module,
    pool: vk.CommandPool,
) -> Error {
    event: sdl.Event
    w: i32 = 0
    h: i32 = 0

    sdl.GetWindowSize(mod.window, &w, &h)

    for {
        flags := sdl.GetWindowFlags(mod.window)

        if (.MINIMIZED in flags) {
            if (!sdl.WaitEvent(&event)) {
                panic("failed to wait on event")
            }

            if (event.type == .WINDOW_RESTORED) {
                break
            }
        } else {
            break
        }
    }

    old_swapchain := mod.swapchain

    mod.swapchain = create_swapchain(
        ctx.device,
        ctx.gpu,
        mod.surface,
        mod.window,
        old_swapchain.handle,
    ) or_return

    destroy_swapchain(ctx.device, &old_swapchain)

    destroy_image(ctx, mod.depth_stencil_image)

    mod.depth_stencil_image = create_depth_stencil_image(
        ctx,
        pool,
        {mod.swapchain.extent.width, mod.swapchain.extent.height},
    ) or_return

    return nil

}


create_depth_stencil_image :: proc(
    ctx: Context,
    pool: vk.CommandPool,
    extent: vk.Extent2D,
) -> (
    image: Allocated_Image,
    err: Error,
) {

    properties: vk.FormatProperties

    vk.GetPhysicalDeviceFormatProperties(
        ctx.gpu,
        vk.Format.D24_UNORM_S8_UINT,
        &properties,
    )

    d24s8 := .DEPTH_STENCIL_ATTACHMENT in properties.optimalTilingFeatures

    vk.GetPhysicalDeviceFormatProperties(
        ctx.gpu,
        vk.Format.D32_SFLOAT_S8_UINT,
        &properties,
    )

    d32s8 := .DEPTH_STENCIL_ATTACHMENT in properties.optimalTilingFeatures

    ensure(d32s8 | d24s8)

    format: vk.Format
    format = .D32_SFLOAT_S8_UINT if d32s8 else .D24_UNORM_S8_UINT

    image = allocate_image(
        ctx.allocator,
        extent.width,
        extent.height,
        format,
        {.DEPTH_STENCIL_ATTACHMENT, .TRANSFER_DST},
        1,
        {.DEPTH, .STENCIL},
    ) or_return

    image.view = create_image_view(
        ctx.device,
        image.handle,
        format,
        subresource_range = vk.ImageSubresourceRange {
            {.DEPTH, .STENCIL},
            0,
            1,
            0,
            1,
        },
    ) or_return

    cmd := begin_single_time_cmd(ctx.device, pool) or_return
    transition_image_layout(cmd, &image, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL)
    submit_single_time_cmd(ctx.device, pool, ctx.queue.handle, &cmd) or_return


    return
}

