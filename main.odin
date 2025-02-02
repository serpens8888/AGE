package main

import "core:fmt"
import "core:mem"
import "core:time"

import sdl "vendor:sdl2"
import vk "vendor:vulkan"
import vulk "vulkan"


main :: proc() {

	when ODIN_DEBUG {

		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}



	ctx: vulk.vk_context
	vulk.init_context(&ctx)
	defer vulk.deinit_context(&ctx)

	render_state: vulk.render_loop_state
	vulk.init_render_state(&render_state, ctx.device)
	defer vulk.deinit_render_state(&render_state, ctx.device)

	vulk.compile_shader("foo.slang")

	vbuf := vulk.create_vertex_buffer(&ctx)
	ibuf := vulk.create_index_buffer(&ctx)
	desc_layout := vulk.create_shader_descriptor_layout(ctx.device)
	vert := vulk.create_tri_vert(ctx.device, &desc_layout)
	frag := vulk.create_tri_frag(ctx.device, &desc_layout)
	cmd_buffers: []vk.CommandBuffer = vulk.create_command_buffers(ctx.device, ctx.queues.pools.graphics, 2)

	stopwatch: time.Stopwatch

	running := true
	event: sdl.Event
	for running {
		for sdl.PollEvent(&event){
			#partial switch event.type {

				case .QUIT: running = false

			}
		}
		time.stopwatch_start(&stopwatch)
		//////RENDER HERE//////

		vulk.render_tri(&ctx, &render_state, cmd_buffers, vert, frag, &vbuf.handle, &ibuf.handle)

		////FINISH RENDER/////
		time.stopwatch_stop(&stopwatch)
		duration_ns := time.duration_nanoseconds(stopwatch._accumulation)
		//fmt.println(1_000_000_000/duration_ns)
		time.stopwatch_reset(&stopwatch)

	}
	
	vk.DeviceWaitIdle(ctx.device)

	vk.DestroyBuffer(ctx.device, vbuf.handle, nil)
	vk.FreeMemory(ctx.device, vbuf.memory, nil)

	vk.DestroyBuffer(ctx.device, ibuf.handle, nil)
	vk.FreeMemory(ctx.device, ibuf.memory, nil)

	vk.DestroyDescriptorSetLayout(ctx.device, desc_layout, nil)

	vk.DestroyShaderEXT(ctx.device, vert, nil)
	vk.DestroyShaderEXT(ctx.device, frag, nil)

	delete(cmd_buffers)

}

















































