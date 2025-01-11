package main

import "core:fmt"
import "core:dynlib"

import sdl "vendor:sdl2"

import vulk "vulkan"



xorswap :: proc(x, y: ^$T){
	x^ ~= y^
	y^ ~= x^
	x^ ~= y^
}


main :: proc() {

	ctx: vulk.vk_context
	vulk.init_context(&ctx)
	defer vulk.deinit_context(&ctx)


	running := true
	event: sdl.Event
	for running {
		for sdl.PollEvent(&event){
			#partial switch event.type {

				case .QUIT: running = false
				
			}
		}

	}



}

















































