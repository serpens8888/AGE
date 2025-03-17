package core

import vulk "vulkan"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"
import "core:fmt"


main :: proc(){

    vulk.load_vulkan()

    ctx: vulk.Context
    assert(vulk.init_context(&ctx, {}) == nil)
    defer vulk.destroy_context(&ctx)

    assert(sdl.Init({.VIDEO}))
    defer sdl.Quit()

    mod1, err1 := vulk.create_graphics_module(&ctx, "foo", 100, 100, {.RESIZABLE})
    defer vulk.destroy_graphics_module(&ctx, &mod1)

    mod2, err2:= vulk.create_graphics_module(&ctx, "bar", 100, 100, {.RESIZABLE})
    defer vulk.destroy_graphics_module(&ctx, &mod2)

    running := true
	event: sdl.Event
	for running {
		for sdl.PollEvent(&event){
			#partial switch event.type {

				case .QUIT: running = false

                case .KEY_DOWN: { 
                    if(event.key.key == sdl.K_ESCAPE){
                        running = false
                    }
                }

			}

		}
	}

}
