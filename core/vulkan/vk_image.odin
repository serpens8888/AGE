package vulk


import vk "vendor:vulkan"
import "vma"


@(require_results)
allocate_image :: proc(
    allocator: vma.Allocator,
    image_info: vk.ImageCreateInfo,
    mem_properties: vk.MemoryPropertyFlags,
    alloc_flags: vma.Allocation_Create_Flags = {.Strategy_Min_Memory, .Strategy_Min_Time, .Strategy_Min_Offset},
) -> (image: Allocated_Image, err: Error){

    allocation_create_info: vma.Allocation_Create_Info = {
        flags = alloc_flags,
        usage = .Auto,
        required_flags = mem_properties
    }

    check_vk(vma.create_image(allocator, image_info, allocation_create_info, &image.handle, &image.allocation, &image.alloc_info)) or_return

    return
}




create_image_view :: proc(
    device: vk.Device,
    image: vk.Image,
    format: vk.Format,
    view_type: vk.ImageViewType = .D2,
    components: vk.ComponentMapping = {.IDENTITY, .IDENTITY, .IDENTITY, .IDENTITY},
    subresource_range: vk.ImageSubresourceRange = {{.COLOR}, 0, 1, 0, 1}
) -> (view: vk.ImageView, err: Error){
    
    create_info: vk.ImageViewCreateInfo = {
        sType = .IMAGE_VIEW_CREATE_INFO,
        image = image,
        viewType = view_type,
        format = format,
        components = components,
        subresourceRange = subresource_range,
    }

    check_vk(vk.CreateImageView(device, &create_info, nil, &view)) or_return

    return
}




