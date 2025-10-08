package core

//main just for testing

import vulk "../core/vulkan"
import "../core/vulkan/vma"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import "core:reflect"
import "core:time"
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
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
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

    pcr := vulk.create_push_constants()
    pl, pl_err := vulk.create_pipeline(ctx, mod, {}, {pcr}, "examples/main.spv")
    defer {if pl_err == nil do vulk.destroy_pipeline(ctx, pl)}

    rs, rs_err := vulk.create_render_state(ctx, cmd_pool, ctx.allocator)
    defer {if rs_err == nil do vulk.destroy_render_state(ctx, &rs)}

    camera, camera_err := vulk.create_camera(ctx, {0, 0, -5}, {0, 0, 0}, 60, 16.0 / 9.0, 0.1, 1000)
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
        vulk.push_camera(cmd, pl, &camera)

        vk.CmdBindPipeline(cmd, .GRAPHICS, pl.handle)

        vulk.render_entity(cmd, pl, &cube)

        vulk.end_rendering(ctx, &mod, &rs, cmd_pool)

        vulk.update_entity(&cube, {0, 0, 0}, spin(0.0000000001), {1, 1, 1})


    }

    vk.DeviceWaitIdle(ctx.device)

}

import "core:math"
import "core:math/linalg"
start := time.tick_now()
spin :: proc(speed: f32) -> (q: quaternion128) {
    theta := speed * f32(time.tick_now()._nsec - start._nsec)

    @(static) x_mul: f32 = 0.0
    @(static) y_mul: f32 = 0.0
    @(static) z_mul: f32 = 0.0

    x_mul += rand.float32_range(-.2, .2)
    y_mul += rand.float32_range(-.2, .2)
    z_mul += rand.float32_range(-.2, .2)

    half_theta := theta / 2.0
    q.w = math.cos(half_theta)
    q.x = math.sin(half_theta * x_mul)
    q.y = math.sin(half_theta * y_mul)
    q.z = math.sin(half_theta * z_mul)

    q = linalg.normalize(q)

    return q
}

