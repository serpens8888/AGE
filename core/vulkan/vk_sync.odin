package vulk

import vk "vendor:vulkan"
import "vma"
import "../utils"


create_fence :: proc(device: vk.Device, flags: vk.FenceCreateFlags) -> (fence: vk.Fence){
    create_info: vk.FenceCreateInfo = {
        sType = .FENCE_CREATE_INFO,
        flags = flags,
    }

    utils.check_vk(vk.CreateFence(device, &create_info, nil, &fence))

    return

}

create_semaphore :: proc(device: vk.Device) -> (sem: vk.Semaphore){
    create_info: vk.SemaphoreCreateInfo = {
        sType = .SEMAPHORE_CREATE_INFO,
    }

    utils.check_vk(vk.CreateSemaphore(device, &create_info, nil, &sem))

    return
}

create_tpyed_semaphore :: proc(device: vk.Device, type: vk.SemaphoreType, initial_value: u64 = 0) -> (sem: vk.Semaphore){
    type_create_info: vk.SemaphoreTypeCreateInfo = {
        sType = .SEMAPHORE_TYPE_CREATE_INFO,
        semaphoreType = type,
        initialValue = initial_value
    }

    create_info: vk.SemaphoreCreateInfo = {
        sType = .SEMAPHORE_CREATE_INFO,
        pNext = &type_create_info,
    }

    utils.check_vk(vk.CreateSemaphore(device, &create_info, nil, &sem))

    return
}
