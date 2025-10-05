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

    descriptors, desc_err := vulk.create_descriptors(ctx.device)
    fmt.println(desc_err)
    defer vulk.destroy_descriptors(ctx.device, descriptors)

    pool: vk.CommandPool
    pool_info: vk.CommandPoolCreateInfo = {
        sType            = .COMMAND_POOL_CREATE_INFO,
        queueFamilyIndex = ctx.queue.family,
        flags            = {.RESET_COMMAND_BUFFER},
    }
    vk.CreateCommandPool(ctx.device, &pool_info, nil, &pool)
    defer vk.DestroyCommandPool(ctx.device, pool, nil)

    mod, gfx_err := vulk.create_graphics_module(
        ctx,
        pool,
        "foo",
        1280,
        720,
        {.RESIZABLE, .VULKAN},
    )

    defer vulk.destroy_graphics_module(ctx, &mod)

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
    defer vulk.free_buffer(ctx.allocator, uniform_buffer)

    layout, layout_err := vulk.create_pipeline_layout(
        ctx.device,
        {descriptors.layout},
        {range},
    )
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


    image, image_err := vulk.create_texture(
        "assets/images/monkey_think.png",
        ctx,
        pool,
    )
    defer vulk.destroy_image(ctx, image)

    sampler, sampler_err := vulk.create_sampler(ctx)
    defer vk.DestroySampler(ctx.device, sampler, nil)

    vulk.add_sampled_image(ctx.device, &descriptors, state, image.view)
    vulk.add_sampler(ctx.device, &descriptors, state, sampler)

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
        cos := math.cos(tick)



        col: vulk.Color = {sin, 0.2, 0.5, 1.0}

        mem.copy(uniform_buffer.mapped_ptr, &col, size_of(vulk.Color))

        cmd := vulk.begin_rendering(ctx, &mod, &state, pool)

        vk.CmdPushConstants(
            cmd,
            layout,
            {.FRAGMENT, .VERTEX},
            0,
            size_of(vk.DeviceAddress),
            &uniform_buffer.address,
        )

        vk.CmdBindDescriptorSets(
            cmd,
            .GRAPHICS,
            layout,
            0,
            1,
            &descriptors.sets[state.current_frame],
            0,
            nil,
        )

        vk.CmdBindPipeline(cmd, .GRAPHICS, pipeline)

        vulk.draw_rectangle(
            -abs(sin) / 2,
            -abs(sin) / 2,
            0.8,
            abs(sin),
            abs(sin),
            &state,
        )
        vulk.draw_rectangle(
            -abs(sin) / 4,
            -abs(sin) / 4,
            0.5,
            abs(sin) / 2,
            abs(sin) / 2,
            &state,
        )
        vulk.draw_rectangle(
            -abs(sin) / 8,
            -abs(sin) / 8,
            0.3,
            abs(sin) / 4,
            abs(sin) / 4,
            &state,
        )
        vulk.draw_batch(&state)

        vulk.end_rendering(ctx, &mod, &state, pool)

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

