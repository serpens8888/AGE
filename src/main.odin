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
    // Back face (z = -0.5)
    {pos = {-0.5, -0.5, -0.5}, uv = {0, 1}},
    {pos = { 0.5, -0.5, -0.5}, uv = {1, 1}},
    {pos = { 0.5,  0.5, -0.5}, uv = {1, 0}},
    {pos = {-0.5,  0.5, -0.5}, uv = {0, 0}},
    
    // Front face (z = 0.5)
    {pos = {-0.5, -0.5, 0.5}, uv = {0, 1}},
    {pos = { 0.5, -0.5, 0.5}, uv = {1, 1}},
    {pos = { 0.5,  0.5, 0.5}, uv = {1, 0}},
    {pos = {-0.5,  0.5, 0.5}, uv = {0, 0}},
    
    // Left face (x = -0.5)
    {pos = {-0.5, -0.5, -0.5}, uv = {0, 1}},
    {pos = {-0.5, -0.5,  0.5}, uv = {1, 1}},
    {pos = {-0.5,  0.5,  0.5}, uv = {1, 0}},
    {pos = {-0.5,  0.5, -0.5}, uv = {0, 0}},
    
    // Right face (x = 0.5)
    {pos = {0.5, -0.5, 0.5}, uv = {0, 1}},
    {pos = {0.5, -0.5, -0.5}, uv = {1, 1}},
    {pos = {0.5,  0.5, -0.5}, uv = {1, 0}},
    {pos = {0.5,  0.5, 0.5}, uv = {0, 0}},
    
    // Top face (y = 0.5)
    {pos = {-0.5, 0.5, 0.5}, uv = {0, 0}},
    {pos = { 0.5, 0.5, 0.5}, uv = {1, 0}},
    {pos = { 0.5, 0.5, -0.5}, uv = {1, 1}},
    {pos = {-0.5, 0.5, -0.5}, uv = {0, 1}},
    
    // Bottom face (y = -0.5)
    {pos = {-0.5, -0.5, -0.5}, uv = {0, 1}},
    {pos = { 0.5, -0.5, -0.5}, uv = {1, 1}},
    {pos = { 0.5, -0.5,  0.5}, uv = {1, 0}},
    {pos = {-0.5, -0.5,  0.5}, uv = {0, 0}},
}

indices: []u32 = {
    // Back face
    0, 1, 2,  0, 2, 3,
    // Front face
    4, 5, 6,  4, 6, 7,
    // Left face
    8, 9, 10, 8, 10, 11,
    // Right face
    12, 13, 14, 12, 14, 15,
    // Top face
    16, 17, 18, 16, 18, 19,
    // Bottom face
    20, 21, 22, 20, 22, 23,
}
 
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

	uniform := vulk.create_uniform(ctx.device, &render_state, allocator, vulk.ubo, 0)
	defer vulk.destroy_uniform(ctx.device, allocator, &uniform)

	texture := vulk.create_texture(&ctx, &render_state, allocator, "assets/images/electronics.png", 1)
	defer vulk.destroy_texture(ctx.device, allocator, &texture)

	pipeline_layout := vulk.create_pipeline_layout(ctx.device, {uniform.layout, texture.uniform.layout}, {})
	defer vk.DestroyPipelineLayout(ctx.device, pipeline_layout, nil)

	vert := vulk.create_tri_vert(ctx.device, {uniform.layout, texture.uniform.layout})
	frag := vulk.create_tri_frag(ctx.device, {uniform.layout, texture.uniform.layout})

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

		vulk.render_tri(&ctx, &render_state, cmd_buffers, vert, frag, &vbuf.handle, &ibuf.handle, &uniform, &texture, pipeline_layout)

		////FINISH RENDER/////
		time.stopwatch_stop(&stopwatch)
		duration_ns := time.duration_nanoseconds(stopwatch._accumulation)
		//fmt.println(1_000_000_000/duration_ns)
		time.stopwatch_reset(&stopwatch)

	}
	
	vk.DeviceWaitIdle(ctx.device)
	
	vma.destroy_buffer(allocator, vbuf.handle, vbuf.memory)
	vma.destroy_buffer(allocator, ibuf.handle, ibuf.memory)

	vk.DestroyShaderEXT(ctx.device, vert, nil)
	vk.DestroyShaderEXT(ctx.device, frag, nil)

	delete(cmd_buffers)

}

















































