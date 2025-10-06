package vulk

import "base:runtime"
import "core:os"
import vk "vendor:vulkan"
import vma "vma"




Error :: union #shared_nil {
    vk.Result,
    runtime.Allocator_Error,
    os.Error,
    Vulk_Error,
}

Vulk_Error :: enum {
    SDL_FAILURE,
}



/*
 * Vertex: a point in 3d space
*/

Vertex :: struct {
    pos:      [3]f32,
    normal:   [3]f32,
    uv:       [2]f32,
    material: u32, //index
}

Index :: distinct u32

Color :: struct {
    r, g, b, a: f32,
}

get_binding_desc :: proc() -> vk.VertexInputBindingDescription {
    return {binding = 0, stride = size_of(Vertex), inputRate = .VERTEX}
}

get_pos_attr_desc :: proc() -> vk.VertexInputAttributeDescription {
    return {
        binding = 0,
        location = 0,
        format = .R32G32B32_SFLOAT,
        offset = u32(offset_of(Vertex, pos)),
    }
}

get_norm_attr_desc :: proc() -> vk.VertexInputAttributeDescription {
    return {
        binding = 0,
        location = 1,
        format = .R32G32B32_SFLOAT,
        offset = u32(offset_of(Vertex, normal)),
    }
}

get_uv_attr_desc :: proc() -> vk.VertexInputAttributeDescription {
    return {
        binding = 0,
        location = 2,
        format = .R32G32_SFLOAT,
        offset = u32(offset_of(Vertex, uv)),
    }
}

get_mat_attr_desc :: proc() -> vk.VertexInputAttributeDescription {
    return {
        binding = 0,
        location = 3,
        format = .R32G32B32_SFLOAT,
        offset = u32(offset_of(Vertex, material)),
    }
}

