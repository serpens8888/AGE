package vulk

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import vk "vendor:vulkan"

Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32
Vec4 :: linalg.Vector4f32

Mat2 :: linalg.Matrix2f32
Mat3 :: linalg.Matrix3f32
Mat4 :: linalg.Matrix4f32

//128 byte max
Push_Constants :: struct #packed {
    vp_matrix: vk.DeviceAddress, //8 bytes, updated per frame
    m_matrix:  vk.DeviceAddress, //8 bytes, updated per opject
}

Mesh :: struct {
    vertex_buffer: Allocated_Buffer,
    index_buffer:  Allocated_Buffer,
    index_count:   u32,
}

Entity :: struct {
    name:         Maybe(string),
    mesh:         Mesh,
    translation:  Vec3,
    rotation:     quaternion128,
    scale:        Vec3,
    model:        Mat4,
    model_buffer: Allocated_Buffer,
}


Camera :: struct {
    position:  Vec3,
    direction: Vec3,
    fovy:      f32,
    aspect:    f32,
    near:      f32,
    far:       f32,
    view:      Mat4,
    proj:      Mat4,
    vp_buffer: Allocated_Buffer,
}

create_push_constants :: proc() -> (pcr: vk.PushConstantRange) {
    return {stageFlags = {.VERTEX}, size = size_of(Push_Constants), offset = 0}
}

push_camera :: proc(cmd: vk.CommandBuffer, pl: Pipeline, c: ^Camera) {
    vk.CmdPushConstants(
        cmd,
        pl.layout,
        {.VERTEX},
        u32(offset_of(Push_Constants, vp_matrix)),
        size_of(vk.DeviceAddress),
        &c.vp_buffer.address,
    )
}


push_entity :: proc(cmd: vk.CommandBuffer, pl: Pipeline, e: ^Entity) {
    vk.CmdPushConstants(
        cmd,
        pl.layout,
        {.VERTEX},
        u32(offset_of(Push_Constants, m_matrix)),
        size_of(vk.DeviceAddress),
        &e.model_buffer.address,
    )

}

render_entity :: proc(cmd: vk.CommandBuffer, pl: Pipeline, e: ^Entity) {

    push_entity(cmd, pl, e)

    offsets: []vk.DeviceSize = {0}
    vk.CmdBindVertexBuffers(
        cmd,
        0,
        1,
        &e.mesh.vertex_buffer.handle,
        raw_data(offsets),
    )
    vk.CmdBindIndexBuffer(cmd, e.mesh.index_buffer.handle, 0, .UINT32)
    vk.CmdDrawIndexed(cmd, e.mesh.index_count, 1, 0, 0, 0)

}

create_camera :: proc(
    ctx: Context,
    pos, dir: Vec3,
    fovy, aspect, near, far: f32,
) -> (
    c: Camera,
    err: Error,
) {
    c = {
        position  = pos,
        direction = dir,
        fovy      = fovy,
        aspect    = aspect,
        near      = near,
        far       = far,
    }

    c.view = linalg.matrix4_look_at(c.position, c.direction, [3]f32{0, 1, 0})
    calculate_perspective(&c)


    c.vp_buffer = create_uniform_buffer(
        ctx.device,
        ctx.allocator,
        size_of(Mat4),
    ) or_return

    vp := c.proj * c.view

    mem.copy(c.vp_buffer.mapped_ptr, &vp, size_of(Mat4))

    return
}

destroy_camera :: proc(ctx: Context, c: Camera) {
    free_buffer(ctx.allocator, c.vp_buffer)
}

update_camera :: proc(c: ^Camera) {

    c.view = linalg.matrix4_look_at(c.position, c.direction, [3]f32{0, 1, 0})
    calculate_perspective(c)

    vp := c.proj * c.view
    mem.copy(c.vp_buffer.mapped_ptr, &vp, size_of(Mat4))
}

calculate_perspective :: proc(c: ^Camera) {
    f := 1.0 / math.tan(c.fovy * math.PI / 180 * 0.5) // fovy in degrees
    near := c.near
    far := c.far
    //odinfmt: disable
    c.proj = {
        f / c.aspect, 0, 0, 0,
        0, -f, 0, 0, // Negative for Vulkan’s y-down NDC
        0, 0, -far / (far - near), -(far * near) / (far - near),
        0, 0, -1, 0,
    }
    //odinfmt: enable
}


//odinfmt: disable
cube_vertices: []Vertex = {
    // Front (+Z)
    {{-1, -1,  1}, {0, 0, 1}, {0, 0}, 0},
    {{ 1, -1,  1}, {0, 0, 1}, {1, 0}, 0},
    {{ 1,  1,  1}, {0, 0, 1}, {1, 1}, 0},
    {{-1,  1,  1}, {0, 0, 1}, {0, 1}, 0},

    // Back (-Z)
    {{ 1, -1, -1}, {0, 0, -1}, {0, 0}, 0},
    {{-1, -1, -1}, {0, 0, -1}, {1, 0}, 0},
    {{-1,  1, -1}, {0, 0, -1}, {1, 1}, 0},
    {{ 1,  1, -1}, {0, 0, -1}, {0, 1}, 0},

    // Left (-X)
    {{-1, -1, -1}, {-1, 0, 0}, {0, 0}, 0},
    {{-1, -1,  1}, {-1, 0, 0}, {1, 0}, 0},
    {{-1,  1,  1}, {-1, 0, 0}, {1, 1}, 0},
    {{-1,  1, -1}, {-1, 0, 0}, {0, 1}, 0},

    // Right (+X)
    {{ 1, -1,  1}, {1, 0, 0}, {0, 0}, 0},
    {{ 1, -1, -1}, {1, 0, 0}, {1, 0}, 0},
    {{ 1,  1, -1}, {1, 0, 0}, {1, 1}, 0},
    {{ 1,  1,  1}, {1, 0, 0}, {0, 1}, 0},

    // Top (+Y)
    {{-1,  1,  1}, {0, 1, 0}, {0, 0}, 0},
    {{ 1,  1,  1}, {0, 1, 0}, {1, 0}, 0},
    {{ 1,  1, -1}, {0, 1, 0}, {1, 1}, 0},
    {{-1,  1, -1}, {0, 1, 0}, {0, 1}, 0},

    // Bottom (-Y)
    {{-1, -1, -1}, {0, -1, 0}, {0, 0}, 0},
    {{ 1, -1, -1}, {0, -1, 0}, {1, 0}, 0},
    {{ 1, -1,  1}, {0, -1, 0}, {1, 1}, 0},
    {{-1, -1,  1}, {0, -1, 0}, {0, 1}, 0},
}

cube_indices: []Index = {
    // front
    0, 1, 2,  2, 3, 0,
    // back
    4, 5, 6,  6, 7, 4,
    // left
    8, 9,10, 10,11, 8,
    // right
    12,13,14, 14,15,12,
    // top
    16,17,18, 18,19,16,
    // bottom
    20,21,22, 22,23,20,
}
//odinfmt: enable

create_cube :: proc(
    ctx: Context,
    pool: vk.CommandPool,
    pos: Vec3,
    rot: quaternion128,
    scale: Vec3,
) -> (
    e: Entity,
    err: Error,
) {
    e.name = "cube"
    e.translation = pos
    e.rotation = rot
    e.scale = scale

    e.model = calculate_model(pos, rot, scale)
    e.mesh = {
        vertex_buffer = create_vertex_buffer(
            ctx.device,
            ctx.queue.handle,
            pool,
            ctx.allocator,
            cube_vertices,
        ) or_return,
        index_buffer  = create_index_buffer(
            ctx.device,
            ctx.queue.handle,
            pool,
            ctx.allocator,
            cube_indices,
        ) or_return,
        index_count   = u32(len(cube_indices)),
    }

    e.model_buffer = create_uniform_buffer(
        ctx.device,
        ctx.allocator,
        size_of(Mat4),
    ) or_return

    mem.copy(e.model_buffer.mapped_ptr, &e.model, size_of(Mat4))

    return
}

update_entity :: proc(e: ^Entity, pos: Vec3, rot: quaternion128, scale: Vec3) {
    e.translation = pos
    e.rotation = rot
    e.scale = scale

    e.model = calculate_model(pos, rot, scale)

    mem.copy(e.model_buffer.mapped_ptr, &e.model, size_of(Mat4))
}

destroy_entity :: proc(ctx: Context, e: Entity) {
    free_buffer(ctx.allocator, e.mesh.vertex_buffer)
    free_buffer(ctx.allocator, e.mesh.index_buffer)
    free_buffer(ctx.allocator, e.model_buffer)
}


calculate_model :: proc(pos: Vec3, rot: quaternion128, scale: Vec3) -> Mat4 {
    t := linalg.matrix4_translate(pos)
    r := linalg.matrix4_from_quaternion(rot)
    s := linalg.matrix4_scale(scale)

    return t * r * s
}

