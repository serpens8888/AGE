package vulk

import "core:fmt"
import "core:log"
import "core:mem"
import "core:strings"
import vk "vendor:vulkan"



@(require_results)
choose_gpu :: proc(
    instance: vk.Instance,
    required_extensions: []cstring,
) -> (
    gpu: vk.PhysicalDevice,
    alloc_err: mem.Allocator_Error,
) {

    gpu_count: u32
    vk.EnumeratePhysicalDevices(instance, &gpu_count, nil)
    assert(gpu_count != 0)

    gpus := make([]vk.PhysicalDevice, gpu_count) or_return
    defer delete(gpus)

    vk.EnumeratePhysicalDevices(instance, &gpu_count, raw_data(gpus))

    gpu = best_gpu(&gpus, required_extensions) or_return

    return gpu, nil
}

@(require_results)
best_gpu :: proc(
    gpus: ^[]vk.PhysicalDevice,
    required_extensions: []cstring,
) -> (
    gpu: vk.PhysicalDevice,
    alloc_err: mem.Allocator_Error,
) {


    scores := make([]int, len(gpus)) or_return
    defer delete(scores)

    for &gpu, i in gpus {


        features: vk.PhysicalDeviceFeatures
        vk.GetPhysicalDeviceFeatures(gpu, &features)

        properties: vk.PhysicalDeviceProperties
        vk.GetPhysicalDeviceProperties(gpu, &properties)

        ok := validate_device_extensions(gpu, required_extensions) or_return

        queues := enumerate_queues(gpu) or_return
        defer delete(queues)

        gpq, found_general := get_general_purpose_queue(&queues)

        if (!ok || !found_general) {
            scores[i] = min(int)
            continue
        }



        if (properties.deviceType == .DISCRETE_GPU) {
            scores[i] += 1000000000
        }

    }

    top_score: int = -1

    for score, i in scores {
        if (score > top_score) {
            top_score = score
            gpu = gpus[i]
        }
    }

    if (uintptr(gpu) == 0x0) {
        panic("no viable devices found")
    }

    return
}

@(require_results)
validate_device_extensions :: proc(
    gpu: vk.PhysicalDevice,
    required_extensions: []cstring,
) -> (
    ok: bool,
    alloc_err: mem.Allocator_Error,
) {
    ext_count: u32
    vk.EnumerateDeviceExtensionProperties(gpu, nil, &ext_count, nil)

    exts := make([]vk.ExtensionProperties, ext_count) or_return
    defer delete(exts)

    vk.EnumerateDeviceExtensionProperties(gpu, nil, &ext_count, raw_data(exts))

    ext_map := make(map[cstring]bool)
    defer delete(ext_map)

    for ext in exts {
        ext_name := ext.extensionName
        ext_str := string(ext_name[0:256])
        ext_map[strings.clone_to_cstring(ext_str)] = true
    }

    defer {
        for key in ext_map {
            delete(key)
        }
    }

    for ext in required_extensions {
        if (ext_map[ext] != true) {
            fmt.println(ext, "NOT FOUND")
            return false, nil
        }
    }

    return true, nil
}

create_logical_device :: proc(
    gpu: vk.PhysicalDevice,
    queue: GPU_Queue,
    required_extensions: []cstring,
    device_features: ^vk.PhysicalDeviceFeatures2,
) -> (
    device: vk.Device,
    err: Error,
) {

    //get the queue create infos


    queue_create_info: vk.DeviceQueueCreateInfo

    priority: f32 = 1.0

    queue_create_info = make_device_queue_create_info(
        queue.family,
        1,
        &priority,
    )


    //create device

    device_create_info: vk.DeviceCreateInfo = {
        sType                   = .DEVICE_CREATE_INFO,
        pNext                   = device_features,
        pQueueCreateInfos       = &queue_create_info,
        queueCreateInfoCount    = 1,
        ppEnabledExtensionNames = raw_data(required_extensions),
        enabledExtensionCount   = u32(len(required_extensions)),
    }

    check_vk(vk.CreateDevice(gpu, &device_create_info, nil, &device)) or_return

    return
}


make_device_queue_create_info :: proc(
    family: u32,
    count: u32,
    priority: ^f32,
) -> vk.DeviceQueueCreateInfo {

    return {
        sType = .DEVICE_QUEUE_CREATE_INFO,
        queueFamilyIndex = family,
        queueCount = count,
        pQueuePriorities = priority,
    }

}

