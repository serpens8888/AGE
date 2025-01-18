package vulk

import "core:fmt"
import vk "vendor:vulkan"


render_loop_state :: struct{
	current_frame: uint,
	frames_in_flight: uint,
	in_flight_fences: []vk.Fence,
	image_available_semaphores: []vk.Semaphore,
	render_finished_semaphores: []vk.Semaphore,
}

init_render_state :: proc(render_state: ^render_loop_state, device: vk.Device){
	render_state.current_frame = 0
	render_state.frames_in_flight = 2
	render_state.in_flight_fences = make([]vk.Fence, render_state.frames_in_flight)
	render_state.image_available_semaphores = make([]vk.Semaphore, render_state.frames_in_flight)
	render_state.render_finished_semaphores = make([]vk.Semaphore, render_state.frames_in_flight)

	for i in 0..<render_state.frames_in_flight{
		render_state.in_flight_fences[i] = get_fence(device, true)
		render_state.image_available_semaphores[i] = get_semaphore(device)
		render_state.render_finished_semaphores[i] = get_semaphore(device)

	}
}

deinit_render_state :: proc(render_state: ^render_loop_state, device: vk.Device){
	for i in 0..<render_state.frames_in_flight{
		vk.DestroyFence(device, render_state.in_flight_fences[i], nil)
		vk.DestroySemaphore(device, render_state.image_available_semaphores[i], nil)
		vk.DestroySemaphore(device, render_state.render_finished_semaphores[i], nil)
	}

	delete(render_state.in_flight_fences)
	delete(render_state.image_available_semaphores)
	delete(render_state.render_finished_semaphores)
}


render_frame :: proc(ctx: ^vk_context, state: ^render_loop_state){
	vk.WaitForFences(ctx.device, 1, &state.in_flight_fences[state.current_frame], true, max(u64))
	vk.ResetFences(ctx.device, 1, &state.in_flight_fences[state.current_frame])

	/*
	image_index: u32
	result := vk.AcquireNextImageKHR(ctx.device, ctx.display.swapchain, max(u64),
	   								 state.image_available_semaphores[state.current_frame],
									 {}, &image_index);

	assert(result != .ERROR_OUT_OF_DATE_KHR)
	
	//submit info and queue submission, presentation failes unless something is submitted to a queue

	present_info: vk.PresentInfoKHR = {
		sType = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores = &state.render_finished_semaphores[state.current_frame],
		swapchainCount = 1,
		pSwapchains = &ctx.display.swapchain,
		pImageIndices = &image_index,
		pResults = nil
	}

	result = vk.QueuePresentKHR(ctx.queues.present_queue, &present_info)

	state.current_frame = (state.current_frame + 1) % state.frames_in_flight
*/

}
























