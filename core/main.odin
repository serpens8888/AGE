package core

import aud "audio"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:time"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"
import vulk "vulkan"

start_time := time.now()

main :: proc() {

    vulk.compile_slang("core/main.slang", "core/main.spv")

    vulk.load_vulkan()

    ctx: vulk.Context
    ensure(vulk.init_context(&ctx) == nil)
    defer vulk.destroy_context(&ctx)

    ensure(sdl.Init({.VIDEO, .AUDIO}))
    defer sdl.Quit()

    manager, _ := vulk.create_descriptors(ctx.device)
    defer vulk.destroy_desriptors(ctx.device, manager)

    pool: vk.CommandPool

    pool_info: vk.CommandPoolCreateInfo = {
        sType            = .COMMAND_POOL_CREATE_INFO,
        queueFamilyIndex = ctx.queue.family,
        flags            = {.RESET_COMMAND_BUFFER},
    }

    vk.CreateCommandPool(ctx.device, &pool_info, nil, &pool)
    defer vk.DestroyCommandPool(ctx.device, pool, nil)

    mod, gfx_err := vulk.create_graphics_module(
        &ctx,
        "foo",
        1280,
        720,
        {.RESIZABLE, .VULKAN},
    )

    defer vulk.destroy_graphics_module(&ctx, &mod)

    range: vk.PushConstantRange = {
        stageFlags = {.VERTEX, .FRAGMENT},
        offset     = 0,
        size       = size_of(vulk.Push_Constant_Data),
    }

    uniform_buffer, uniform_err := vulk.create_uniform_buffer(
        ctx.device,
        ctx.allocator,
        size_of(vulk.Color),
    )

    layout, layout_err := vulk.create_pipeline_layout(ctx.device, {}, {range})
    defer vk.DestroyPipelineLayout(ctx.device, layout, nil)

    shader_mod, shader_err := vulk.create_shader_module(
        ctx.device,
        "core/main.spv",
    )
    defer vk.DestroyShaderModule(ctx.device, shader_mod, nil)

    pipeline, pl_err := vulk.create_graphics_pipeline(
        ctx.device,
        mod,
        layout,
        shader_mod,
    )
    defer vk.DestroyPipeline(ctx.device, pipeline, nil)


    state, rs_err := vulk.create_render_state(ctx, pool, ctx.allocator)
    defer vulk.destroy_render_state(ctx, &state)

    running := true
    event: sdl.Event
    for running {
        for sdl.PollEvent(&event) {
            #partial switch event.type {

            case .QUIT: running = false


            case .KEY_DOWN:
                {
                    if (event.key.key == sdl.K_ESCAPE) {
                        running = false
                    }
                }

            }
        }

        tick := f32(time.duration_seconds(time.since(start_time)))
        sin := math.sin(tick)



        col: vulk.Color = {sin, 0.2, 0.5, 1.0}

        mem.copy(uniform_buffer.mapped_ptr, &col, size_of(vulk.Color))

        cmd := vulk.begin_rendering(ctx, &mod, &state)

        vk.CmdPushConstants(
            cmd,
            layout,
            {.FRAGMENT, .VERTEX},
            0,
            size_of(vk.DeviceAddress),
            &uniform_buffer.address,
        )

        vk.CmdBindPipeline(cmd, .GRAPHICS, pipeline)

        vulk.draw_rectangle(0, 0, .5, .5, &state)
        vulk.draw_rectangle(-1, -1, .1, .1, &state)
        vulk.draw_rectangle(.8, -.8, .2, .2, &state)
        vulk.draw_rectangle(-.4, .4, .18, .32, &state)
        vulk.draw_rectangle(0 + sin, 0 + sin, 0 + sin, 0 + sin, &state)
        vulk.draw_batch(&state)

        vulk.end_rendering(ctx, &mod, &state)

    }

    vk.DeviceWaitIdle(ctx.device)

}


/*
    device, stream, aud_err := aud.initialize_audio(2, 48000)
    assert(aud_err == nil)
    osc := aud.saw_oscillator(10, 48000)
    chunk := new([48000*10]f32)
    for i in 0..<48000*5{
        data := ((rand.float32_normal(-0.8, 0.1)) * 0.2) + aud.next(&osc) * 0.1
        chunk[i*2] = data/2
        chunk[i*2+1] = data/2
    }
    sdl.PutAudioStreamData(stream, chunk, 48000*10*4)
*/

