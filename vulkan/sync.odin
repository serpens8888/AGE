package vulk

import "core:fmt"
import vk "vendor:vulkan"

get_semaphore :: proc(device: vk.Device) -> vk.Semaphore{
	ci: vk.SemaphoreCreateInfo = { sType = .SEMAPHORE_CREATE_INFO }	
	semaphore: vk.Semaphore
	vk.CreateSemaphore(device, &ci, nil, &semaphore)
	return semaphore
}

get_fence :: proc(device: vk.Device, signaled: bool) -> vk.Fence{
	ci: vk.FenceCreateInfo 
	ci.sType = .FENCE_CREATE_INFO
	if(signaled == true){
		ci.flags = {.SIGNALED}
	}
	fence: vk.Fence
	vk.CreateFence(device, &ci, nil, &fence)
	return fence
}
