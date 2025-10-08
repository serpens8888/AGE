package vulk


import "core:fmt"
import "core:mem"
import vk "vendor:vulkan"
import "vma"

Allocated_Buffer :: struct {
    handle:     vk.Buffer, //vulkan handle for the image
    allocation: vma.Allocation, //vma allocation on the gpu
    alloc_info: vma.Allocation_Info, //info about the VMA allocation
    mapped_ptr: rawptr, //pointer for mapping
    address:    vk.DeviceAddress, //pointer to buffer
}

@(require_results)
allocate_buffer :: proc(
    allocator: vma.Allocator,
    buffer_info: ^vk.BufferCreateInfo,
    usage: vk.BufferUsageFlags,
    mem_properties: vk.MemoryPropertyFlags,
    alloc_flags: vma.Allocation_Create_Flags = {
        .Strategy_Min_Memory,
        .Strategy_Min_Time,
        .Strategy_Min_Offset,
    },
) -> (
    buffer: Allocated_Buffer,
    err: Error,
) {

    buffer_info.usage = usage

    allocation_create_info: vma.Allocation_Create_Info = {
        flags          = alloc_flags,
        usage          = .Auto,
        required_flags = mem_properties,
    }

    check_vk(
        vma.create_buffer(
            allocator,
            buffer_info^,
            allocation_create_info,
            &buffer.handle,
            &buffer.allocation,
            &buffer.alloc_info,
        ),
    ) or_return

    return
}

free_buffer :: proc(allocator: vma.Allocator, buffer: Allocated_Buffer) {
    vma.unmap_memory(allocator, buffer.allocation)
    vma.destroy_buffer(allocator, buffer.handle, buffer.allocation)
}

copy_buffer :: proc(
    device: vk.Device,
    queue: vk.Queue,
    pool: vk.CommandPool,
    src, dst: Allocated_Buffer,
    size: vk.DeviceSize,
) -> (
    err: Error,
) {
    cmd := begin_single_time_cmd(device, pool) or_return

    assert(src.alloc_info.size >= size, "bounds check")
    assert(src.alloc_info.size >= size, "bounds check")

    copy_region: vk.BufferCopy2 = {
        sType     = .BUFFER_COPY_2,
        srcOffset = 0,
        dstOffset = 0,
        size      = size,
    }

    copy_info: vk.CopyBufferInfo2 = {
        sType       = .COPY_BUFFER_INFO_2,
        srcBuffer   = src.handle,
        dstBuffer   = dst.handle,
        regionCount = 1,
        pRegions    = &copy_region,
    }


    vk.CmdCopyBuffer2(cmd, &copy_info)

    submit_single_time_cmd(device, pool, queue, &cmd) or_return

    return
}


@(require_results)
create_uniform_buffer :: proc(
    device: vk.Device,
    allocator: vma.Allocator,
    size: vk.DeviceSize,
) -> (
    buffer: Allocated_Buffer,
    err: Error,
) {
    buffer_info := make_buffer_create_info(size, {})
    buffer = allocate_buffer(
        allocator,
        &buffer_info,
        {.UNIFORM_BUFFER, .SHADER_DEVICE_ADDRESS},
        {.HOST_VISIBLE, .HOST_COHERENT},
    ) or_return

    check_vk(
        vma.map_memory(allocator, buffer.allocation, &buffer.mapped_ptr),
    ) or_return

    address_info: vk.BufferDeviceAddressInfo = {
        sType  = .BUFFER_DEVICE_ADDRESS_INFO,
        buffer = buffer.handle,
    }

    buffer.address = vk.GetBufferDeviceAddress(device, &address_info)

    return
}

@(require_results)
create_storage_buffer :: proc(
    device: vk.Device,
    allocator: vma.Allocator,
    size: vk.DeviceSize,
) -> (
    buffer: Allocated_Buffer,
    err: Error,
) {
    buffer_info := make_buffer_create_info(size, {})
    buffer = allocate_buffer(
        allocator,
        &buffer_info,
        {.STORAGE_BUFFER, .SHADER_DEVICE_ADDRESS},
        {.HOST_VISIBLE, .HOST_COHERENT},
    ) or_return

    check_vk(
        vma.map_memory(allocator, buffer.allocation, &buffer.mapped_ptr),
    ) or_return

    address_info: vk.BufferDeviceAddressInfo = {
        sType  = .BUFFER_DEVICE_ADDRESS_INFO,
        buffer = buffer.handle,
    }

    buffer.address = vk.GetBufferDeviceAddress(device, &address_info)
    return buffer, nil
}

@(require_results)
create_staging_buffer :: #force_inline proc(
    allocator: vma.Allocator,
    size: vk.DeviceSize,
) -> (
    buffer: Allocated_Buffer,
    err: Error,
) {
    info := make_buffer_create_info(size, {})
    buffer = allocate_buffer(
        allocator,
        &info,
        {.TRANSFER_SRC},
        {.HOST_VISIBLE, .HOST_COHERENT},
    ) or_return

    //we can map the pointer here and never call unmap because the staging buffer is temperary
    //so it will be deleted which unmaps the pointer anyways (not 100% sure)
    vma.map_memory(allocator, buffer.allocation, &buffer.mapped_ptr) or_return

    return buffer, nil
}

@(require_results)
create_vertex_buffer :: proc(
    device: vk.Device,
    transfer_queue: vk.Queue,
    transfer_pool: vk.CommandPool,
    allocator: vma.Allocator,
    verts: []Vertex,
) -> (
    vertex_buffer: Allocated_Buffer,
    err: Error,
) {
    size := len(verts) * size_of(Vertex)
    staging_buffer := create_staging_buffer(
        allocator,
        vk.DeviceSize(size),
    ) or_return

    mem.copy(staging_buffer.mapped_ptr, raw_data(verts), int(size))

    buffer_info := make_buffer_create_info(vk.DeviceSize(size), {})
    vertex_buffer = allocate_buffer(
        allocator,
        &buffer_info,
        {.VERTEX_BUFFER, .TRANSFER_DST},
        {.DEVICE_LOCAL},
    ) or_return

    copy_buffer(
        device,
        transfer_queue,
        transfer_pool,
        staging_buffer,
        vertex_buffer,
        vk.DeviceSize(size),
    ) or_return

    vma.destroy_buffer(
        allocator,
        staging_buffer.handle,
        staging_buffer.allocation,
    )


    return
}

create_vertex_buffer_empty :: proc(
    device: vk.Device,
    allocator: vma.Allocator,
    vert_count: uint,
) -> (
    vertex_buffer: Allocated_Buffer,
    err: Error,
) {
    size := vert_count * size_of(Vertex)

    buffer_info := make_buffer_create_info(vk.DeviceSize(size), {})
    vertex_buffer = allocate_buffer(
        allocator,
        &buffer_info,
        {.VERTEX_BUFFER, .TRANSFER_DST},
        {.HOST_VISIBLE, .HOST_COHERENT, .HOST_CACHED},
    ) or_return

    return
}

@(require_results)
write_verts :: proc(
    vertex_buffer: Allocated_Buffer,
    allocator: vma.Allocator,
    offset: uintptr,
    verts: []Vertex,
) -> Error {
    size := len(verts) * size_of(Vertex)
    dst := uintptr(vertex_buffer.mapped_ptr) + offset

    when ODIN_DEBUG {
        if (offset + uintptr(size) > uintptr(vertex_buffer.alloc_info.size)) {
            fmt.panicf(
                "vertex buffer overflow: buffer size = %n, attempted to write to: %n",
                vertex_buffer.alloc_info.size,
                uint(offset) + uint(size),
            )
        }
    }




    mem.copy(rawptr(dst), raw_data(verts), size)

    check_vk(
        vma.flush_allocation(
            allocator,
            vertex_buffer.allocation,
            vertex_buffer.alloc_info.offset + vk.DeviceSize(offset),
            vk.DeviceSize(size),
        ),
    ) or_return

    return nil
}

@(require_results)
create_index_buffer :: proc(
    device: vk.Device,
    transfer_queue: vk.Queue,
    transfer_pool: vk.CommandPool,
    allocator: vma.Allocator,
    indices: []Index,
) -> (
    index_buffer: Allocated_Buffer,
    err: Error,
) {

    size := len(indices) * size_of(u32)
    staging_buffer := create_staging_buffer(
        allocator,
        vk.DeviceSize(size),
    ) or_return

    mem.copy(staging_buffer.mapped_ptr, raw_data(indices), int(size))
    vma.unmap_memory(allocator, staging_buffer.allocation)

    buffer_info := make_buffer_create_info(vk.DeviceSize(size), {})
    index_buffer = allocate_buffer(
        allocator,
        &buffer_info,
        {.INDEX_BUFFER, .TRANSFER_DST},
        {.DEVICE_LOCAL},
    ) or_return

    copy_buffer(
        device,
        transfer_queue,
        transfer_pool,
        staging_buffer,
        index_buffer,
        vk.DeviceSize(size),
    ) or_return

    vma.destroy_buffer(
        allocator,
        staging_buffer.handle,
        staging_buffer.allocation,
    )

    return
}

create_index_buffer_empty :: proc(
    device: vk.Device,
    allocator: vma.Allocator,
    count: uint,
) -> (
    index_buffer: Allocated_Buffer,
    err: Error,
) {
    size := count * size_of(Index)

    buffer_info := make_buffer_create_info(vk.DeviceSize(size), {})
    index_buffer = allocate_buffer(
        allocator,
        &buffer_info,
        {.INDEX_BUFFER, .TRANSFER_DST},
        {.HOST_VISIBLE, .HOST_COHERENT, .HOST_CACHED},
    ) or_return


    return
}

@(require_results)
write_indices :: proc(
    buffer: Allocated_Buffer,
    allocator: vma.Allocator,
    offset: uintptr,
    indices: []Index,
) -> Error {

    size := len(indices) * size_of(Index)
    dst := uintptr(buffer.mapped_ptr) + offset

    when ODIN_DEBUG {

        if (offset + uintptr(size) > uintptr(buffer.alloc_info.size)) {
            fmt.panicf(
                "vertex buffer overflow: buffer size = %n, attempted to write to: %n",
                buffer.alloc_info.size,
                uint(offset) + uint(size),
            )
        }
    }

    mem.copy(rawptr(dst), raw_data(indices), size)

    check_vk(
        vma.flush_allocation(
            allocator,
            buffer.allocation,
            buffer.alloc_info.offset + vk.DeviceSize(offset),
            vk.DeviceSize(size),
        ),
    ) or_return

    return nil

}

