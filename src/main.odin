package main

import "core:fmt"
import "core:mem"
import "core:time"
import "core:log"

import sdl "vendor:sdl3"
import vk "vendor:vulkan"
import vulk "vulkan"
import vma "vma"


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

	verts: []vulk.Vertex = {
		{pos = {-0.5, -0.5, 0.0}, uv = {0,0}},
		{pos = {0.5, -0.5, 0.0}, uv = {1,0}},
		{pos = {0.5, 0.5, 0.0}, uv = {1,1}},
		{pos = {-0.5, 0.5, 0.0}, uv = {0,1}},
	}

	indices :[]u32 = {0,1,2,2,3,0}

 
	vma_vk_functions := vma.create_vulkan_functions()

	allocator_create_info: vma.Allocator_Create_Info = {
		flags = {.Buffer_Device_Address},
		instance = ctx.instance,
		vulkan_api_version = 1004000, // 1.4
		physical_device = ctx.gpu,
		device = ctx.device,
		vulkan_functions = &vma_vk_functions,
	}

	allocator: vma.Allocator = ---
	if res := vma.create_allocator(allocator_create_info, &allocator); res != .SUCCESS {
		log.errorf("Failed to Create Vulkan Memory Allocator: [%v]", res)
		return
	}
	defer vma.destroy_allocator(allocator)

	vbuf := vulk.create_vertex_buffer(&ctx, allocator, verts)
	ibuf := vulk.create_index_buffer(&ctx, allocator, indices)

	ubufs := make([]vulk.uniform_buffer, render_state.frames_in_flight)
	vulk.create_uniform_buffer(ubufs , allocator)
	desc_layout := vulk.create_descriptor_layout(ctx.device)
	desc_pool := vulk.create_descriptor_pool(ctx.device, &render_state)
	desc_sets := vulk.create_descriptor_sets(ctx.device, desc_layout, desc_pool, &render_state)
	vulk.write_desc_sets(ctx.device, desc_sets, ubufs)
	pipeline_layout := vulk.create_pipeline_layout(ctx.device, &desc_layout)


	vert := vulk.create_tri_vert(ctx.device, &desc_layout)
	frag := vulk.create_tri_frag(ctx.device, &desc_layout)
	cmd_buffers: []vk.CommandBuffer = vulk.create_command_buffers(ctx.device, ctx.queues.pools.graphics, u32(render_state.frames_in_flight))

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

		vulk.render_tri(&ctx, &render_state, cmd_buffers, vert, frag, &vbuf.handle, &ibuf.handle, ubufs, pipeline_layout, desc_sets)

		////FINISH RENDER/////
		time.stopwatch_stop(&stopwatch)
		duration_ns := time.duration_nanoseconds(stopwatch._accumulation)
		//fmt.println(1_000_000_000/duration_ns)
		time.stopwatch_reset(&stopwatch)

	}
	
	vk.DeviceWaitIdle(ctx.device)
	
	for i in 0..<len(ubufs){ vma.destroy_buffer(allocator, ubufs[i].buffer.handle, ubufs[i].buffer.memory) }
	delete(ubufs)

	vma.destroy_buffer(allocator, vbuf.handle, vbuf.memory)
	vma.destroy_buffer(allocator, ibuf.handle, ibuf.memory)

	vk.DestroyPipelineLayout(ctx.device, pipeline_layout, nil)
	vk.DestroyDescriptorPool(ctx.device, desc_pool, nil)
	delete(desc_sets)

	vk.DestroyDescriptorSetLayout(ctx.device, desc_layout, nil)

	vk.DestroyShaderEXT(ctx.device, vert, nil)
	vk.DestroyShaderEXT(ctx.device, frag, nil)

	delete(cmd_buffers)

}

















































