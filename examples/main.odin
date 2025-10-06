package core

//main just for testing

import vulk "../core/vulkan"
import "../core/vulkan/vma"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import "core:reflect"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"




//main just to test procs
main :: proc() {
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf(
                    "=== %v allocations not freed: ===\n",
                    len(track.allocation_map),
                )
                for _, entry in track.allocation_map {
                    fmt.eprintf(
                        "- %v bytes @ %v\n",
                        entry.size,
                        entry.location,
                    )
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }

    vulk.compile_slang("examples/main.slang", "examples/main.spv")

    vulk.load_vulkan()

    ctx, ctx_err := vulk.create_context()
    defer {if ctx_err == nil do vulk.destroy_context(&ctx)}

    ensure(sdl.Init({.VIDEO, .AUDIO}))
    defer sdl.Quit()

    cmd_pool, pool_err := vulk.create_command_pool(ctx.device, ctx.queue)
    defer {if pool_err == nil do vk.DestroyCommandPool(ctx.device, cmd_pool, nil)}

    mod, mod_err := vulk.create_graphics_module(
        ctx,
        cmd_pool,
        "example",
        1280,
        720,
        {.RESIZABLE, .VULKAN},
    )
    defer {if mod_err == nil do vulk.destroy_graphics_module(ctx, &mod)}

    pl, pl_err := vulk.create_pipeline(ctx, mod, {}, {}, "examples/main.spv")
    defer {if pl_err == nil do vulk.destroy_pipeline(ctx, pl)}

    rs, rs_err := vulk.create_render_state(ctx, cmd_pool, ctx.allocator)
    defer {if rs_err == nil do vulk.destroy_render_state(ctx, &rs)}

    camera, camera_err := vulk.create_camera(
        ctx,
        {0, 0, 0},
        {0, 0, 0},
        60,
        16 / 9,
        0.1,
        1000,
    )
    defer {if camera_err == nil do vulk.destroy_camera(ctx, camera)}

    cube, cube_err := vulk.create_cube(ctx, cmd_pool, {0, 0, 0}, {}, {1, 1, 1})
    defer {if cube_err == nil do vulk.destroy_entity(ctx, cube)}

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

        cmd := vulk.begin_rendering(ctx, &mod, &rs, cmd_pool)

        vk.CmdBindPipeline(cmd, .GRAPHICS, pl.handle)

        vulk.draw_rectangle(-0.8, -0.8, 0.8, 0.5, 0.5, &rs)
        vulk.draw_batch(&rs)

        vulk.end_rendering(ctx, &mod, &rs, cmd_pool)

    }

    vk.DeviceWaitIdle(ctx.device)

}

