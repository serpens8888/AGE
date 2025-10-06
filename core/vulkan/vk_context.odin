package vulk

import "core:fmt"
import "core:mem"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"
import "vma"




Context :: struct {
    allocator:       vma.Allocator, //the vma allocator
    instance:        vk.Instance, //the vulkan instance
    debug_messenger: vk.DebugUtilsMessengerEXT, //the debug messenger for validation layers
    gpu:             vk.PhysicalDevice, //the handle to the selected gpu
    gpu_properties:  vk.PhysicalDeviceProperties, //the properties of the physical gpu
    device:          vk.Device, //the vulkan logical device
    queue:           GPU_Queue, //the general purpose gpu_queue
}


device_extensions: []cstring : {"VK_KHR_swapchain"}

//ORDER IS VERY IMPORTANT
@(require_results)
create_context :: proc() -> (ctx: Context, err: Error) {
    ctx.instance = create_instance() or_return

    vk.load_proc_addresses(ctx.instance) //load in all the functions for creating the device

    when ODIN_DEBUG {
        ctx.debug_messenger = create_debug_messenger(ctx.instance) or_return
    }


    ctx.gpu = choose_gpu(ctx.instance, device_extensions) or_return
    vk.GetPhysicalDeviceProperties(ctx.gpu, &ctx.gpu_properties)

    gpu_queues := enumerate_queues(ctx.gpu) or_return
    defer delete(gpu_queues)

    select_context_queue(&gpu_queues)

    create_context_device(&ctx) or_return

    create_context_queue(&ctx, ctx.queue)


    vk.load_proc_addresses(ctx.device) //load in the rest of the functions

    create_context_allocator(&ctx)

    return
}

//ORDER IS VERY IMPORTANT
destroy_context :: proc(ctx: ^Context) {

    vma.destroy_allocator(ctx.allocator)
    vk.DestroyDevice(ctx.device, nil)

    when ODIN_DEBUG {vk.DestroyDebugUtilsMessengerEXT(
            ctx.instance,
            ctx.debug_messenger,
            nil,
        )}
    vk.DestroyInstance(ctx.instance, nil)

}

@(private = "file")
select_context_queue :: proc(gpu_queues: ^[]GPU_Queue) {
    queue, queue_found := get_general_purpose_queue(gpu_queues)
    assert(queue_found == true)


}

create_context_queue :: proc(ctx: ^Context, selected_queue: GPU_Queue) {

    ctx.queue = {
        family = selected_queue.family,
        index  = selected_queue.index,
        flags  = selected_queue.flags,
        handle = get_queue(ctx.device, selected_queue),
    }

}

@(private = "file")
create_context_device :: proc(ctx: ^Context) -> (err: Error) {
    features: vk.PhysicalDeviceFeatures2 = {
        sType = .PHYSICAL_DEVICE_FEATURES_2,
        features = {samplerAnisotropy = true},
    }

    vulkan_features11: vk.PhysicalDeviceVulkan11Features = {
        sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
    }

    vulkan_features12: vk.PhysicalDeviceVulkan12Features = {
        sType                                        = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        bufferDeviceAddress                          = true,
        descriptorIndexing                           = true,
        shaderSampledImageArrayNonUniformIndexing    = true,
        runtimeDescriptorArray                       = true,
        descriptorBindingVariableDescriptorCount     = true,
        descriptorBindingPartiallyBound              = true,
        descriptorBindingSampledImageUpdateAfterBind = true,
    }

    vulkan_features13: vk.PhysicalDeviceVulkan13Features = {
        sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        dynamicRendering = true,
        synchronization2 = true,
    }


    features.pNext = &vulkan_features11
    vulkan_features11.pNext = &vulkan_features12
    vulkan_features12.pNext = &vulkan_features13



    ctx.device = create_logical_device(
        ctx.gpu,
        ctx.queue,
        device_extensions,
        &features,
    ) or_return

    return
}

@(private = "file")
create_context_allocator :: proc(ctx: ^Context) -> Error {
    vma_vk_functions := vma.create_vulkan_functions()

    allocator_create_info: vma.Allocator_Create_Info = {
        flags              = {
            .Buffer_Device_Address,
            .Amd_Device_Coherent_Memory,
            .Khr_Maintenance5,
        },
        instance           = ctx.instance,
        vulkan_api_version = 1003000, // 1.3
        physical_device    = ctx.gpu,
        device             = ctx.device,
        vulkan_functions   = &vma_vk_functions,
    }


    check_vk(
        vma.create_allocator(allocator_create_info, &ctx.allocator),
    ) or_return

    return nil

}

