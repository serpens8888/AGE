package vulk

import vk "vendor:vulkan"
import vma "vma"
import "base:runtime"
import "core:os"




Error :: union #shared_nil{
    vk.Result,
    runtime.Allocator_Error,
    os.Error,
    Vulk_Error,
}

Vulk_Error :: enum{
    SDL_FAILURE
}



/*
 * Vertex: a point in 3d space
*/

Vertex ::  struct{ 
    pos: [3]f32,
    normal: [3]f32,
    col: [3]f32,
    texcoord: [2]f32,
}

get_binding_desc :: proc() -> vk.VertexInputBindingDescription{
    return{
        binding = 0,
        stride = size_of(Vertex),
        inputRate = .VERTEX,
    }
}

get_pos_attr_desc :: proc() -> vk.VertexInputAttributeDescription{
    return {
        binding = 0,
        location = 0,
        format = .R32G32B32_SFLOAT,
        offset = u32(offset_of(Vertex, pos))
    }
}

get_norm_attr_desc :: proc() -> vk.VertexInputAttributeDescription{
    return {
        binding = 0,
        location = 1,
        format = .R32G32B32_SFLOAT,
        offset = u32(offset_of(Vertex, normal))
    }
}

get_col_attr_desc :: proc() -> vk.VertexInputAttributeDescription{
    return {
        binding = 0,
        location = 2,
        format = .R32G32B32_SFLOAT,
        offset = u32(offset_of(Vertex, col))
    }
}

get_texcoord_attr_desc :: proc() -> vk.VertexInputAttributeDescription{
    return {
        binding = 0,
        location = 3,
        format = .R32G32_SFLOAT,
        offset = u32(offset_of(Vertex, texcoord))
    }
}


/*
 * GPU_Queue: Represents a Vulkan queue with its family, index, and capabilities
 *
 * Queues are exposed by the Vulkan driver and we submit work via command buffers.
 * Different queue families support different operations:
 * - Graphics: Rendering operations
 * - Compute: General purpose computation
 * - Transfer: Memory operations (optimal for copies)
 * - Sparse Binding: Memory management for large resources
 * - Video Decode: Decoding video formats
 * - Video Encode: Encoding video formats
 * - Protected: Operations on protected memory
 * - Optical Flow: Computer vision tasks
 *
 * Note: Vulkan guarantees at least one queue family supporting graphics,
 * compute, transfer, and sparse binding operations.
*/

GPU_Queue :: struct{
	family: u32, //the index of the queue family
	index: u32, //the index of the queue in said family
	flags: vk.QueueFlags, //the suported operations of the family
    handle: vk.Queue //the handle to the created queue
}

/*
  * Allocated_Buffer: Represents a buffer allocated on the GPU
  *
  * Contains a mapped pointer for writing, and the GPU pointer to the buffer.
  * the GPU pointer can be passed via push constants, and can be a pointer to
  * a struct of structs of structs of..., allowing us to avoid binding buffer types.
*/

Allocated_Buffer :: struct{
	handle: vk.Buffer, //vulkan handle for the image
	allocation: vma.Allocation, //vma allocation on the gpu
	alloc_info: vma.Allocation_Info, //info about the VMA allocation
    mapped_ptr: rawptr, //pointer for mapping
	address: vk.DeviceAddress, //pointer to buffer

}

/*
 * Allocated_Image: Represents an image allocated on the GPU
 *
 * Contains some metadata about the image.
 * Images cannot be passed via a GPU pointer, 
 * we must put them into a descriptor set or descriptor buffer.
*/

Allocated_Image :: struct{ //images need to be put into descriptor buffers before being passed
	handle: vk.Image, //vulkan handle for image
	allocation: vma.Allocation, //vma allocation on gpu
    alloc_info: vma.Allocation_Info,
	view: vk.ImageView, //image view of the allocated image
	extent: vk.Extent3D, //image extent
	format: vk.Format //format of the image
}

/*
 * Swapchain: the vulkan structure responsible for image presentation
*/

Swapchain :: struct{
    handle: vk.SwapchainKHR, //handle to swapchain
    images: []vk.Image, //the swapchains images
    views: []vk.ImageView, //images views of the swapchains images
    format: vk.Format, //the formap of the swapchain images
    extent: vk.Extent2D, //the extent of the swapchain images
}


