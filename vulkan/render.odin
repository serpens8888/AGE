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
























