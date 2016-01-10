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

#version 430

#define USE_MAIN_SCENE_DATA
#define USE_TIME_OF_DAY
#pragma include "Includes/Configuration.inc.glsl"


uniform writeonly imageCube RESTRICT DestCubemap;
uniform sampler2D DefaultSkydome;

#pragma include "../ScatteringMethod.inc.glsl"

out vec4 result;

void main() {

    // Get cubemap coordinate
    int texsize = imageSize(DestCubemap).x;
    ivec2 coord = ivec2(gl_FragCoord.xy);

    // Get cubemap direction
    ivec2 clamped_coord; int face;
    vec3 direction = texcoord_to_cubemap(texsize, coord, clamped_coord, face);

    // Store horizon
    float horizon = direction.z;
    direction.z = abs(direction.z);
    float fog_factor = 0.0;

    // Get inscattered light
    vec3 inscattered_light = DoScattering(direction * 1e10, direction, fog_factor);

    if (horizon > 0.0) {
        // Clouds
        vec3 cloud_color = textureLod(DefaultSkydome, get_skydome_coord(direction), 0).xyz;
         inscattered_light += pow(cloud_color.y, 4.5) * TimeOfDay.Scattering.sun_intensity * 0.2;
    } else {
        // Ground reflectance
        inscattered_light *= saturate(1+0.9*horizon) * 0.1;
        inscattered_light += pow(vec3(102, 82, 50) * (1.0 / 255.0), vec3(1.0 / 1.2)) * saturate(-horizon + 0.4) * 0.1 * TimeOfDay.Scattering.sun_intensity;
    }

    // No physical background, but looks better
    inscattered_light *= HALF_PI;

    imageStore(DestCubemap, ivec3(clamped_coord, face), vec4(inscattered_light, 1.0) );
    result.xyz = inscattered_light;
}
