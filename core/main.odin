package core

import vulk "vulkan"
import aud "audio"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"
import "core:fmt" 
import "core:math" 
import "core:math/rand" 
 
//this function has a period of 2, which makes it much nicer for looping
main :: proc(){

    vulk.load_vulkan()

    ctx: vulk.Context
    assert(vulk.init_context(&ctx, {}) == nil)
    defer vulk.destroy_context(&ctx)

    assert(sdl.Init({.VIDEO, .AUDIO}))
    defer sdl.Quit()

    mod, err := vulk.create_graphics_module(&ctx, "foo", 300, 300, {})
    defer vulk.destroy_graphics_module(&ctx, &mod)



    device, stream, err2 := aud.initialize_audio(2, 48000)
    assert(err2 == nil)




    //osc := aud.tri_oscillator(100, 48000)



    chunk := new([48000*10]f32)

    for i in 0..<48000*5{
        data := (rand.float32_normal(-0.8, 0.1)) * 0.1
        chunk[i*2] = data
        chunk[i*2+1] = data
    }

    sdl.PutAudioStreamData(stream, chunk, 48000*10*4)

    //fmt.println(chunk)



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

            //work here


		}
	}

}
