package vulk

import vk "vendor:vulkan"
import sdl "vendor:sdl3"
import "core:log"


queue_family_indices :: struct{
	present_family: u32,
	present_idx: u32,

	graphics_family: u32,
	graphics_idx: u32,

	compute_family: u32,
	compute_idx: u32,

	transfer_family: u32,
	transfer_idx: u32,

	sparse_family: u32,
	sparse_idx: u32,
}

cmd_pools :: struct{
	graphics: vk.CommandPool,
	compute: vk.CommandPool,
	transfer: vk.CommandPool,
	sparse: vk.CommandPool,
}

queue_manager :: struct {
	present_queue: vk.Queue,
	graphics_queue: vk.Queue,
	compute_queue: vk.Queue,
	transfer_queue: vk.Queue,
	sparse_queue: vk.Queue,
	pools: cmd_pools,

}

display_objects :: struct {
	window: ^sdl.Window,
	surface: vk.SurfaceKHR,
	swapchain: vk.SwapchainKHR,
	swapchain_images: []vk.Image,
	swapchain_image_views: []vk.ImageView,
	swapchain_format: vk.Format,
	swapchain_extent: vk.Extent2D,
}

vk_context :: struct {
	instance: vk.Instance,
	debug_messenger: vk.DebugUtilsMessengerEXT,
	gpu: vk.PhysicalDevice,
	device: vk.Device,
	queues: queue_manager,
	display: display_objects

}

/*
resource_manager :: struct {

}

sync_manager :: struct {

}
*/

init_context :: proc(ctx: ^vk_context){
	result := sdl.Init({.VIDEO})
	assert(result != false)

	ctx.display.window = sdl.CreateWindow("window", 1920, 1080, {.VULKAN, .RESIZABLE} )
	min_w, min_h: i32 : 1, 1
	if( sdl.SetWindowMinimumSize(ctx.display.window, min_w, min_h) != true){
		log.error("failed to set minimum window size")
	}

	load_vulkan()
	create_instance(ctx)
	vk.load_proc_addresses(ctx.instance)

	sdl.Vulkan_CreateSurface(ctx.display.window, ctx.instance, nil, &ctx.display.surface)

	when ODIN_DEBUG{ create_debug_messenger(ctx) }

	select_gpu(ctx)
	create_device(ctx)
	vk.load_proc_addresses(ctx.device)

	create_swapchain(ctx)
}

deinit_context :: proc(ctx: ^vk_context){
	vk.DestroySwapchainKHR(ctx.device, ctx.display.swapchain, nil)
	for view in ctx.display.swapchain_image_views{ vk.DestroyImageView(ctx.device, view, nil) }
	delete(ctx.display.swapchain_image_views)
	delete(ctx.display.swapchain_images)


	vk.DestroyCommandPool(ctx.device, ctx.queues.pools.graphics, nil)
	vk.DestroyCommandPool(ctx.device, ctx.queues.pools.compute, nil)
	vk.DestroyCommandPool(ctx.device, ctx.queues.pools.transfer, nil)
	vk.DestroyCommandPool(ctx.device, ctx.queues.pools.sparse, nil)

	vk.DestroyDevice(ctx.device, nil)

	vk.DestroySurfaceKHR(ctx.instance, ctx.display.surface, nil)

	when ODIN_DEBUG{ vk.DestroyDebugUtilsMessengerEXT(ctx.instance, ctx.debug_messenger, nil) }
	vk.DestroyInstance(ctx.instance, nil)

	sdl.DestroyWindow(ctx.display.window)
	sdl.Quit()
}












