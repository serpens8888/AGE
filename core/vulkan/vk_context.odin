package vulk

import vk "vendor:vulkan"
import "vma"
import sdl "vendor:sdl3"
import "core:mem"
import "core:fmt"




Context :: struct{
    allocator: vma.Allocator, //the vma allocator
    instance: vk.Instance, //the vulkan instance
    debug_messenger: vk.DebugUtilsMessengerEXT, //the debug messenger for validation layers
    gpu: vk.PhysicalDevice, //the handle to the auto selected gpu
    gpu_queues: []GPU_Queue, //enumerated queues of the gpu
    device: vk.Device, //the vulkan logical device

    general_queue: vk.Queue,
    general_pool: vk.CommandPool,

    //these queues can be enabled via context flags
    compute_queue: vk.Queue,
    compute_pool: vk.CommandPool,
    transfer_queue: vk.Queue,
    transfer_pool: vk.CommandPool,
    sparse_queue: vk.Queue,
    sparse_pool: vk.CommandPool,


}

Graphics_Module :: struct{
    window: ^sdl.Window,
    surface: vk.SurfaceKHR,
    swapchain: Swapchain,
}

Context_Flag :: enum{
    //GRAPHICS,
    SEPARATE_COMPUTE,
    SEPARATE_TRANSFER,
    SEPARATE_SPARSE,
}

Context_Flags :: bit_set[Context_Flag]

device_extensions: []cstring : {
    "VK_KHR_swapchain",
    "VK_KHR_dynamic_rendering",
    "VK_KHR_buffer_device_address",
    "VK_KHR_synchronization2",
    "VK_KHR_maintenance5",

    "VK_EXT_shader_object",
    "VK_EXT_descriptor_buffer", //THIS ONE CRASHES RENDERDOC
    "VK_EXT_descriptor_indexing",

    "VK_AMD_device_coherent_memory",
}

//ORDER IS VERY IMPORTANT
@(require_results)
init_context :: proc(ctx: ^Context, flags: Context_Flags) -> (alloc_err: mem.Allocator_Error){
    ctx.instance = create_instance() or_return

	vk.load_proc_addresses(ctx.instance)

	when ODIN_DEBUG {ctx.debug_messenger = create_debug_messenger(ctx.instance)}

	
    ctx.gpu = choose_gpu(ctx.instance, device_extensions) or_return

	ctx.gpu_queues = enumerate_queues(ctx.gpu) or_return

    selected_queues := make([dynamic]GPU_Queue) or_return
    defer delete(selected_queues)

    select_context_queues(&selected_queues, &ctx.gpu_queues, flags)


    create_context_device(ctx, selected_queues[:]) or_return


	vk.load_proc_addresses(ctx.device)


    create_context_queues(ctx, selected_queues, flags)

    create_context_allocator(ctx)

    return
}

//ORDER IS VERY IMPORTANT
destroy_context :: proc(ctx: ^Context){
    vk.DestroyCommandPool(ctx.device, ctx.general_pool, nil)
    if(ctx.compute_pool != 0){ vk.DestroyCommandPool(ctx.device, ctx.compute_pool, nil) }
    if(ctx.transfer_pool != 0){ vk.DestroyCommandPool(ctx.device, ctx.transfer_pool, nil) }
    if(ctx.sparse_pool != 0){ vk.DestroyCommandPool(ctx.device, ctx.sparse_pool, nil) }

	vma.destroy_allocator(ctx.allocator)
    vk.DestroyDevice(ctx.device, nil)

	when ODIN_DEBUG {vk.DestroyDebugUtilsMessengerEXT(ctx.instance, ctx.debug_messenger, nil)}
	vk.DestroyInstance(ctx.instance, nil)

    delete(ctx.gpu_queues)
}

@(private="file")
select_context_queues :: proc(selected_queues: ^[dynamic]GPU_Queue, gpu_queues: ^[]GPU_Queue, flags: Context_Flags){
    general_purpose_queue, general_queue_found := get_general_purpose_queue(gpu_queues) 
    assert(general_queue_found == true)

    append(selected_queues, general_purpose_queue)


    compute_queue, transfer_queue, sparse_queue: GPU_Queue

    if .SEPARATE_COMPUTE in flags{
        compute_queue_found: bool = false
        compute_queue, compute_queue_found = get_separate_compute_queue(gpu_queues)
        assert(compute_queue_found == true)
        append(selected_queues, compute_queue)
    }
    
    if .SEPARATE_TRANSFER in flags{
        transfer_queue_found: bool = false
        transfer_queue, transfer_queue_found = get_separate_transfer_queue(gpu_queues)
        assert(transfer_queue_found == true)
        append(selected_queues, transfer_queue)
    }

    if .SEPARATE_SPARSE in flags{
        sparse_queue_found: bool = false
        sparse_queue, sparse_queue_found = get_separate_sparse_binding_queue(gpu_queues)
        assert(sparse_queue_found == true)
        append(selected_queues, sparse_queue)
    }
}

@(private="file")
create_context_queues :: proc(ctx: ^Context, selected_queues: [dynamic]GPU_Queue, flags: Context_Flags){
    queue_iter := 0

    ctx.general_pool = create_command_pool(ctx.device, selected_queues[queue_iter])
    ctx.general_queue = get_queue(ctx.device, selected_queues[queue_iter])
        queue_iter+=1

    if .SEPARATE_COMPUTE in flags {
        ctx.compute_pool = create_command_pool(ctx.device, selected_queues[queue_iter])
        ctx.compute_queue = get_queue(ctx.device, selected_queues[queue_iter])
        queue_iter+=1
    }

    if .SEPARATE_TRANSFER in flags {
        ctx.transfer_pool = create_command_pool(ctx.device, selected_queues[queue_iter])
        ctx.transfer_queue = get_queue(ctx.device, selected_queues[queue_iter])
        queue_iter+=1
    }

    if .SEPARATE_SPARSE in flags {
        ctx.sparse_pool = create_command_pool(ctx.device, selected_queues[queue_iter])
        ctx.sparse_queue = get_queue(ctx.device, selected_queues[queue_iter])
        queue_iter+=1
    }

}

@(private="file")
create_context_device :: proc(ctx: ^Context, selected_queues: []GPU_Queue) -> (err: mem.Allocator_Error){
	features: vk.PhysicalDeviceFeatures2 = {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		features = {
			samplerAnisotropy = true,
		}
	}

	vulkan_features11: vk.PhysicalDeviceVulkan11Features = {
		sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
	};

	vulkan_features12: vk.PhysicalDeviceVulkan12Features = {
		sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		runtimeDescriptorArray = true,
		bufferDeviceAddress = true,
		descriptorIndexing = true,
	};

	vulkan_features13: vk.PhysicalDeviceVulkan13Features = {
		sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		dynamicRendering = true,
        synchronization2 = true,
	};

	shader_obj: vk.PhysicalDeviceShaderObjectFeaturesEXT = {
		sType = .PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT,
		shaderObject = true,
	}
	desc_buf: vk.PhysicalDeviceDescriptorBufferFeaturesEXT = {
		sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT,
		descriptorBuffer = true,
	}
	coherent_memory: vk.PhysicalDeviceCoherentMemoryFeaturesAMD = {
		sType = .PHYSICAL_DEVICE_COHERENT_MEMORY_FEATURES_AMD,
		deviceCoherentMemory = true,
	}
    maintenance5: vk.PhysicalDeviceMaintenance5FeaturesKHR = {
        sType = .PHYSICAL_DEVICE_MAINTENANCE_5_FEATURES_KHR,
        maintenance5 = true,
    }

	features.pNext = &vulkan_features11
	vulkan_features11.pNext = &vulkan_features12
	vulkan_features12.pNext = &vulkan_features13
	vulkan_features13.pNext = &shader_obj
	shader_obj.pNext = &desc_buf
	desc_buf.pNext = &coherent_memory
    coherent_memory.pNext = &maintenance5



    ctx.device = create_logical_device(ctx.gpu, selected_queues, device_extensions, &features) or_return

    return
}

@(private="file")
create_context_allocator :: proc(ctx: ^Context){
    vma_vk_functions := vma.create_vulkan_functions()

    allocator_create_info: vma.Allocator_Create_Info = {
        flags = {.Buffer_Device_Address, .Amd_Device_Coherent_Memory, .Khr_Maintenance5},
        instance = ctx.instance,
        vulkan_api_version = 1004000, // 1.4
        physical_device = ctx.gpu,
        device = ctx.device,
        vulkan_functions = &vma_vk_functions,
    }


    check_vk(vma.create_allocator(allocator_create_info, &ctx.allocator))

}

create_graphics_module :: proc(ctx: ^Context, window_name: cstring, w,h: i32, flags: sdl.WindowFlags) -> (mod: Graphics_Module, err: mem.Allocator_Error){
    mod.window =  create_window("foo", w, h, {.RESIZABLE})
    mod.surface = create_surface(mod.window, ctx.instance)
    mod.swapchain = create_swapchain(ctx.device, ctx.gpu, mod.surface, mod.window) or_return

    return
}

destroy_graphics_module :: proc(ctx: ^Context, mod: ^Graphics_Module){
    destroy_swapchain(ctx.device, &mod.swapchain)
    vk.DestroySurfaceKHR(ctx.instance, mod.surface, nil)
    sdl.DestroyWindow(mod.window)
}






