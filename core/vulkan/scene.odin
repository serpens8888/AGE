package vulk

import "core:math/linalg"

Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32
Vec4 :: linalg.Vector4f32

Mat2 :: linalg.Matrix2f32
Mat3 :: linalg.Matrix3f32
Mat4 :: linalg.Matrix4f32


Mesh :: struct {
    vertex_buffer: Allocated_Buffer,
    index_buffer:  Allocated_Buffer,
}

Entity :: struct {
    name:        Maybe(string),
    mesh:        Mesh,
    translation: Vec3,
    rotation:    quaternion128,
    scale:       Vec3,
    model:       Mat4,
}



Camera :: struct {
    position:     Vec3,
    rotation:     quaternion128,
    fovy:         f32,
    aspect_ratio: f32,
    near:         f32,
    far:          f32,
    view:         Mat4,
    proj:         Mat4,
}

update_camera :: proc(c: ^Camera) {
}

