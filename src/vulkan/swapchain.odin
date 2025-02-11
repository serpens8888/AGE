 package vulk

import "core:fmt"
import vk "vendor:vulkan"
import sdl "vendor:sdl3"


create_swapchain :: proc(ctx: ^vk_context){
	//create swapchain and all the things that go with it

	format_count: u32 = 0
	vk.GetPhysicalDeviceSurfaceFormatsKHR(ctx.gpu, ctx.display.surface, &format_count, nil)
	formats := make([]vk.SurfaceFormatKHR, format_count); defer delete(formats)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(ctx.gpu, ctx.display.surface, &format_count, raw_data(formats))

	surface_format: vk.SurfaceFormatKHR
	for format in formats{
		if(format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR){
			surface_format = format
		}
	}
	if(surface_format.format == .UNDEFINED){
		surface_format = formats[0]
	}


	present_mode_count: u32 = 0
	vk.GetPhysicalDeviceSurfacePresentModesKHR(ctx.gpu, ctx.display.surface, &present_mode_count, nil)
	present_modes := make([]vk.PresentModeKHR, present_mode_count); defer delete(present_modes)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(ctx.gpu, ctx.display.surface, &present_mode_count, raw_data(present_modes))

	present_mode: vk.PresentModeKHR
	for mode in present_modes{
		if(mode == .MAILBOX){
			present_mode = mode
		}
	}
	if(present_mode != .MAILBOX){
		present_mode = .FIFO
	}


	capabilities: vk.SurfaceCapabilitiesKHR
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(ctx.gpu, ctx.display.surface, &capabilities)

	extent: vk.Extent2D
	if(capabilities.currentExtent.width != max(u32)){
		extent = capabilities.currentExtent
	} else {
		height: i32 = ---
		width: i32 = ---
		sdl.GetWindowSizeInPixels(ctx.display.window, &width, &height)

		real_extent: vk.Extent2D = {
			u32(width),
			u32(height),
		}

		real_extent.width = clamp(real_extent.width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width)
		real_extent.height = clamp(real_extent.height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height)

		extent = real_extent
	}
	
	image_count := capabilities.minImageCount + 1 //using the min can cause delays while the driver does internal operations
	
	if(capabilities.maxImageCount > 0 && image_count > capabilities.maxImageCount){
		image_count = capabilities.maxImageCount
	}

	swapchain_ci: vk.SwapchainCreateInfoKHR
	swapchain_ci.sType = .SWAPCHAIN_CREATE_INFO_KHR
	swapchain_ci.surface = ctx.display.surface
	swapchain_ci.minImageCount = image_count
	swapchain_ci.imageFormat = surface_format.format
	swapchain_ci.imageColorSpace = surface_format.colorSpace
	swapchain_ci.imageExtent = extent
	swapchain_ci.imageArrayLayers = 1
	swapchain_ci.imageUsage = {.COLOR_ATTACHMENT}


	indices := select_queues(ctx.gpu, ctx.display.surface)
	present_n_graphics := []u32{indices.graphics_family, indices.present_family}
	if(indices.graphics_family != indices.present_family){
		swapchain_ci.imageSharingMode = .CONCURRENT
		swapchain_ci.queueFamilyIndexCount = 2
		swapchain_ci.pQueueFamilyIndices = raw_data(present_n_graphics)
	} else {
		swapchain_ci.imageSharingMode = .EXCLUSIVE
	}
	
	swapchain_ci.preTransform = capabilities.currentTransform
	swapchain_ci.compositeAlpha = {.OPAQUE}
	swapchain_ci.presentMode = present_mode
	swapchain_ci.clipped = true
	swapchain_ci.oldSwapchain = 0x0 //will set later when swapchain recreation is enabled
	
	vk.CreateSwapchainKHR(ctx.device, &swapchain_ci, nil, &ctx.display.swapchain)

	vk.GetSwapchainImagesKHR(ctx.device, ctx.display.swapchain, &image_count, nil)
	images := make([]vk.Image, image_count)
	vk.GetSwapchainImagesKHR(ctx.device, ctx.display.swapchain, &image_count, raw_data(images))

	image_views := make([]vk.ImageView, image_count)

	for i in 0..<image_count{
		image_view_ci: vk.ImageViewCreateInfo = {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = images[i],
			viewType = .D2,
			format = surface_format.format,
			components = { r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY },
			subresourceRange = {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			}
		}

		vk.CreateImageView(ctx.device, &image_view_ci, nil, &image_views[i])
	}

	ctx.display.swapchain_extent = extent
	ctx.display.swapchain_format = surface_format.format
	ctx.display.swapchain_images = images
	ctx.display.swapchain_image_views = image_views

	return
}

recreate_swapchain :: proc(ctx: ^vk_context){
	event: sdl.Event
	w: i32 = 0
	h: i32 = 0

	sdl.GetWindowSize(ctx.display.window, &w, &h)

	for{
		flags := sdl.GetWindowFlags(ctx.display.window)

		if(.MINIMIZED in flags){
			if(!sdl.WaitEvent(&event)){
				panic("failed to wait on event")
			}

			fmt.println(flags)
			if(event.type == .WINDOW_RESTORED){
				break
			}
		} else{
			 break
		}
	 }

		 
		

	vk.DeviceWaitIdle(ctx.device)


	vk.DestroySwapchainKHR(ctx.device, ctx.display.swapchain, nil)
	for view in ctx.display.swapchain_image_views{ vk.DestroyImageView(ctx.device, view, nil) }
	delete(ctx.display.swapchain_image_views)
	delete(ctx.display.swapchain_images)
	
	create_swapchain(ctx)
}































