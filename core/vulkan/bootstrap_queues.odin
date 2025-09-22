package vulk

import "core:fmt"
import "core:mem"
import vk "vendor:vulkan"

GPU_Queue :: struct {
    family: u32, //the index of the queue family
    index:  u32, //the index of the queue in said family
    flags:  vk.QueueFlags, //the suported operations of the family
    handle: vk.Queue, //the handle to the created queue
}

@(require_results)
enumerate_queues :: proc(
    gpu: vk.PhysicalDevice,
) -> (
    queues: []GPU_Queue,
    alloc_err: mem.Allocator_Error,
) {


    queue_family_count: u32
    vk.GetPhysicalDeviceQueueFamilyProperties(gpu, &queue_family_count, nil)

    queue_families := make(
        []vk.QueueFamilyProperties,
        queue_family_count,
    ) or_return
    defer delete(queue_families)

    vk.GetPhysicalDeviceQueueFamilyProperties(
        gpu,
        &queue_family_count,
        raw_data(queue_families),
    )

    queue_count: u32
    for family in queue_families {
        queue_count += family.queueCount
    }


    queues = make([]GPU_Queue, queue_count)


    queue_iter: uint = 0
    for family, i in queue_families {
        for j in 0 ..< family.queueCount {
            queues[queue_iter] = {u32(i), u32(j), family.queueFlags, nil}
            queue_iter += 1
        }

    }

    return
}

@(require_results)
get_general_purpose_queue :: proc(
    queues: ^[]GPU_Queue,
) -> (
    general_purpose_queue: GPU_Queue,
    found: bool,
) {
    for &queue in queues {
        if (.GRAPHICS in queue.flags &&
               .COMPUTE in queue.flags &&
               .TRANSFER in queue.flags &&
               .SPARSE_BINDING in queue.flags) {
            queue.flags = {}
            return queue, true
        }
    }

    return {}, false
}

@(require_results)
get_separate_compute_queue :: proc(
    queues: ^[]GPU_Queue,
) -> (
    compute_queue: GPU_Queue,
    found: bool,
) {
    for &queue in queues {
        if (.COMPUTE in queue.flags) {
            queue.flags = {}
            return queue, true
        }
    }

    return {}, false
}

@(require_results)
get_separate_transfer_queue :: proc(
    queues: ^[]GPU_Queue,
) -> (
    compute_queue: GPU_Queue,
    found: bool,
) {
    for &queue in queues {
        if (.TRANSFER in queue.flags) {
            queue.flags = {}
            return queue, true
        }
    }

    return {}, false
}

@(require_results)
get_separate_sparse_binding_queue :: proc(
    queues: ^[]GPU_Queue,
) -> (
    compute_queue: GPU_Queue,
    found: bool,
) {
    for &queue in queues {
        if (.SPARSE_BINDING in queue.flags) {
            queue.flags = {}
            return queue, true
        }
    }

    return {}, false
}

@(require_results)
query_presentation_support :: proc(
    queue: GPU_Queue,
    gpu: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
) -> (
    present_support: b32,
    err: Error,
) {
    check_vk(
        vk.GetPhysicalDeviceSurfaceSupportKHR(
            gpu,
            u32(queue.family),
            surface,
            &present_support,
        ),
    ) or_return
    return
}


get_queue :: proc(
    device: vk.Device,
    gpu_queue: GPU_Queue,
) -> (
    queue: vk.Queue,
) {
    vk.GetDeviceQueue(device, gpu_queue.family, gpu_queue.index, &queue)
    return
}

create_command_pool :: proc(
    device: vk.Device,
    gpu_queue: GPU_Queue,
) -> (
    pool: vk.CommandPool,
    err: Error,
) {
    create_info: vk.CommandPoolCreateInfo = {
        sType            = .COMMAND_POOL_CREATE_INFO,
        flags            = {.RESET_COMMAND_BUFFER},
        queueFamilyIndex = gpu_queue.family,
    }

    check_vk(vk.CreateCommandPool(device, &create_info, nil, &pool)) or_return

    return
}

