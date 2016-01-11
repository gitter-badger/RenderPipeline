/**
 * 
 * RenderPipeline
 * 
 * Copyright (c) 2014-2015 tobspr <tobias.springer1@gmail.com>
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */

#pragma once

#define saturate(v) clamp(v, 0, 1)

#define M_PI 3.1415926535897932384626433
#define HALF_PI 1.5707963267948966192313216
#define TWO_PI 6.2831853071795864769252867
#define ONE_BY_PI 0.3183098861837906715377675

// Fixes the cubemap direction
vec3 fix_cubemap_coord(vec3 coord) {
    return normalize(coord.xzy * vec3(1,-1,1));
}


// Converts a texture coodinate and face index to a direction vector
vec3 get_cubemap_coordinate(int face_index, vec2 coord) {
    vec3 baseDir = vec3(0);
    if (face_index == 0) baseDir = vec3(1.0, -coord.y, -coord.x);
    else if (face_index == 1) baseDir = vec3(-1.0, -coord.y, coord.x);
    else if (face_index == 2) baseDir = vec3(coord.x, 1.0, coord.y);
    else if (face_index == 3) baseDir = vec3(coord.x, -1.0, -coord.y);
    else if (face_index == 4) baseDir = vec3(coord.x, -coord.y, 1.0);
    else if (face_index == 5) baseDir = vec3(-coord.x, -coord.y, -1.0);
    return normalize(baseDir);
}

// Computes the skydome texcoord based on the pixels view direction
vec2 get_skydome_coord(vec3 view_dir) {
    float angle = (atan(view_dir.x, view_dir.y) + M_PI) / (2.0 * M_PI);
    return vec2(angle, view_dir.z);
}


// Converts a coordinate like "gl_FragCoord" to a cubemap direction, with a given
// cubemap size. Assumes the render target has a size of (6 * cubemap_size, cubemap_size).
// clamped_coord will contain a coordinate from (0 .. cubemap_size), this can be
// used for further processing or writing the result. 
// face will contain the selected cubemap face.
vec3 texcoord_to_cubemap(int cubemap_size, ivec2 coord, out ivec2 clamped_coord, out int face) {
    face = coord.x / cubemap_size;
    clamped_coord = coord % cubemap_size;
    vec2 local_coord = saturate( (clamped_coord+0.5) / float(cubemap_size)) * 2.0 - 1.0;
    return get_cubemap_coordinate(face, local_coord);
}


// Version of texcoord_to_cubemap without the out parameters
vec3 texcoord_to_cubemap(int cubemap_size, ivec2 coord) {
    ivec2 clamped_coord; int face;
    return texcoord_to_cubemap(cubemap_size, coord, clamped_coord, face);
}


// Rotate a vector by an angle
vec2 rotate(vec2 vector, float angle) {
    float cos_alpha = cos(angle);
    float sin_alpha = sin(angle);
    return vec2(
        vector.x * cos_alpha - vector.y * sin_alpha,
        vector.x * sin_alpha + vector.y * cos_alpha 
    );
}


// Returns a coordinate which can be used for bilateral upscaling
ivec2 get_bilateral_coord(ivec2 coord) {
    return (coord + 1) / 2 - 1;
}

// Checks if a coordinate exceeds the [0, 1] range
bool out_of_screen(vec2 tcoord) {
    return tcoord.x < 0.0 || tcoord.y < 0.0 || tcoord.x > 1.0 || tcoord.y > 1.0;    
}

// Finds a tangent and bitangent vector based on a given normal
void find_arbitrary_tangent(vec3 normal, out vec3 tangent, out vec3 bitangent) {
    vec3 v0 = abs(normal.z) < 0.99 ? vec3(0, 0, 1) : vec3(0, 1, 0);
    tangent = normalize(cross(v0, normal));
    bitangent = normalize(cross(tangent, normal));
}

// Transforms a given vector to tangent space
vec3 tangent_to_world(vec3 vec, vec3 tangent)
{
    vec3 v0 = abs(tangent.z) < 0.99 ? vec3(0, 0, 1) : vec3(1, 0, 0);
    vec3 tangent_x = normalize( cross( v0, tangent ) );
    vec3 tangent_y = cross( tangent, tangent_x );
    return tangent_x * vec.x + tangent_y * vec.y + tangent * vec.z;
}


// Returns the number of mipmaps of a cubemap
int get_mipmap_count(samplerCube cubemap) {
    int cubemap_size = textureSize(cubemap, 0).x;
    return int(1 + floor(log2(cubemap_size)));
}

// Returns the number of mipmaps of a 2D Texture
int get_mipmap_count(sampler2D tex) {
    int tex_size = textureSize(tex, 0).x;
    return int(1 + floor(log2(tex_size)));
}

// Converts a normalized spherical coordinate (r = 1) to cartesian coordinates 
vec3 spherical_to_vector(float theta, float phi) {
    float sin_theta = sin(theta);
    return normalize(vec3(
        sin_theta * cos(phi),
        sin_theta * sin(phi),
        cos(theta)
    ));
}

// Converts a cartesian coordinate to spherical coordinates
void vector_to_spherical(vec3 v, out float theta, out float phi, out float radius) {
    radius = sqrt(dot(v, v));
    phi = acos(v.z / radius);
    theta = atan(v.y, v.x) + M_PI; 
}

// Converts a given sun azimuth and altitude to a direction vector
vec3 sun_azimuth_to_angle(float azimuth, float altitude) {
    float theta = (90-altitude) / 180.0 * M_PI;
    float phi = azimuth / 180.0 * M_PI;
    return spherical_to_vector(theta, phi);
}


// FROM: https://github.com/mattdesl/glsl-blend-soft-light/blob/master/index.glsl
// Licensed under the MIT License, see the github repo for more details.
// Blends a given color soft with the base color
vec3 blend_soft_light(vec3 base, vec3 blend) {
    return mix(
        sqrt(base) * (2.0 * blend - 1.0) + 2.0 * base * (1.0 - blend), 
        2.0 * base * blend + base * base * (1.0 - 2.0 * blend), 
        step(base, vec3(0.5))
    );
}

// Normalizes v without taking the w component into account
vec4 normalize_without_w(vec4 v) {
    return v / length(v.xyz);
}

// Unpacks a normal from 0 .. 1 range to the -1 .. 1 range
vec3 unpack_texture_normal(vec3 n) {
    return fma(n, vec3(2.0), vec3(-1.0));
}

// Converts a value from linear to logarithmic distribution, using a given factor
float make_logarithmic(float x, float factor) {
    // return (exp(factor * x)-1) / (exp(factor)-1);
    return log(factor * x + 1.0 + 1e-6) / log(1.0 + factor);
}

// Makes a 3 component vector logarithmic
vec3 make_logarithmic(vec3 v, float factor) {
    return log(factor * v + 1.0 + 1e-6) / log(1.0 + factor);
}

// Unpacks an integer from a float, packed by the GPUCommandQueue.
int gpu_cq_unpack_int_from_float(float v) {
    #if GPU_CMD_INT_AS_FLOAT
        return floatBitsToInt(v);
    #else
        return int(v);
    #endif
}

// Computes the diffuse antialiasing factor
// From: http://blog.selfshadow.com/sandbox/diffuse_aa.html
float get_diffuse_aa(float w, float NxL) {
    float x  = sqrt(1.0 - w);
    float x0 = 0.373837*NxL;
    float x1 = 0.66874*x;
    float n  = x0 + x1;
    return w*((abs(x0) <= x1) ? n*n/x : saturate(NxL));
}


// Blends a material
float blend_material(float material_factor, float detailmap, float add_factor, float pow_factor) {
    material_factor = max(0, material_factor);
    return saturate(
        mix( pow( max(0, detailmap + add_factor), pow_factor), 1.0, material_factor) * material_factor);
}

// Blends a specular IOR to make sure it never drops below 1.0
float blend_ior(float material_specular, float sampled_specular) {
    return 1.0 + max(0, material_specular - 1.0) * 2.0 * sampled_specular;
}

// We need to define them as macros instead of functions, since gl_FragCoord is
// not available in compute shaders

// Regular texcoord
#define get_texcoord() vec2( (ivec2(gl_FragCoord.xy) + 0.5) / SCREEN_SIZE )

// Texcoord for half-res targets sampling full-res targets
#define get_half_texcoord() vec2( (ivec2(gl_FragCoord.xy) * 2 + 0.5) / SCREEN_SIZE )

// Texcoord for half-res targets sampling half-res targets
#define get_half_native_texcoord() vec2( (ivec2(gl_FragCoord.xy) + 0.5) / ivec2(SCREEN_SIZE/2) )
