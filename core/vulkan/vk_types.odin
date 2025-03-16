package vulk

import vk "vendor:vulkan"
import vma "vma"



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
	flags: vk.QueueFlags //the suported operations of the family
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
 * Swapchain: 
 *
 *
 *
*/

Swapchain :: struct{
    handle: vk.SwapchainKHR,
    images: []vk.Image,
    image_views: []vk.ImageView,
    format: vk.Format,
    extent: vk.Extent2D,
}



