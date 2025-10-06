package vulk

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
    vp_matrix:    vk.DeviceAddress, //8 bytes, updated per frame
    per_obj_data: vk.DeviceAddress, //8 bytes, updated per opject
}

Per_Object_Data :: struct {
    model_matrix: Mat4,
}

Mesh :: struct {
    vertex_buffer: Allocated_Buffer,
    index_buffer:  Allocated_Buffer,
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
    calculate_view(&c)
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
    calculate_view(c)
    calculate_perspective(c)

    vp := c.proj * c.view
    mem.copy(c.vp_buffer.mapped_ptr, &vp, size_of(Mat4))
}

calculate_view :: proc(c: ^Camera) {
    up: Vec3 = {0, 1, 0}
    f := linalg.normalize(c.direction - c.position) //forward
    s := linalg.normalize(linalg.cross(f, up)) //side
    u := linalg.cross(s, f) //true up
    
    //odinfmt: disable
    c.view = {
        s.x, s.y, s.z, -linalg.dot(s, c.position),
        u.x, u.y, u.z, -linalg.dot(u, c.position),
        -f.x, -f.y, -f.z, linalg.dot(f, c.position),
        0, 0, 0, 1
    }
    //odinfmt: enable
}

calculate_perspective :: proc(c: ^Camera) {
    f := 1.0 / math.tan(c.fovy / 2.0)

    
    //odinfmt: disable
    c.proj ={
        f/c.aspect, 0, 0, 0,
        0, f, 0, 0,
        0, 0, c.far / (c.far - c.near), (-c.near * c.far) / (c.far - c.near),
        0, 0, 1, 0,
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

