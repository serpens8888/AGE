package vulk

import "core:fmt"
import "core:mem"
import "core:slice"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"
import "vma"

Swapchain :: struct {
    handle: vk.SwapchainKHR, //handle to swapchain
    images: []vk.Image, //the swapchains images
    views:  []vk.ImageView, //images views of the swapchains images
    format: vk.Format, //the formap of the swapchain images
    extent: vk.Extent2D, //the extent of the swapchain images
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
    swapchain.images = make([]vk.Image, image_count) or_return
    vk.GetSwapchainImagesKHR(
        device,
        swapchain.handle,
        &image_count,
        raw_data(swapchain.images),
    )


    swapchain.views = make([]vk.ImageView, image_count) or_return

    for &view, i in swapchain.views {
        view = create_image_view(
            device,
            swapchain.images[i],
            format.format,
        ) or_return
    }

    swapchain.extent = extent
    swapchain.format = format.format



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
    vk.DestroySwapchainKHR(device, swapchain.handle, nil)
    for view in swapchain.views {
        vk.DestroyImageView(device, view, nil)
    }
    delete(swapchain.views)
    delete(swapchain.images)
}


@(require_results)
recreate_swapchain :: proc(ctx: Context, mod: ^Graphics_Module) -> Error {
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

    return nil

}

