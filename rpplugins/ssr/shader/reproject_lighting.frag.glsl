/**
 *
 * RenderPipeline
 *
 * Copyright (c) 2014-2016 tobspr <tobias.springer1@gmail.com>
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

// Copies the previous scene color to the first mipmap.
// Also outputs the current frame intersection depth

#define USE_MAIN_SCENE_DATA
#define USE_GBUFFER_EXTENSIONS
#pragma include "render_pipeline_base.inc.glsl"
#pragma include "includes/color_spaces.inc.glsl"
#pragma include "includes/gbuffer.inc.glsl"
#pragma include "includes/transforms.inc.glsl"

uniform sampler2D CombinedVelocity;
uniform sampler2D Previous_PostAmbientScene;
uniform sampler2D Previous_SceneDepth;

out vec4 result;

void main() {
  vec2 texcoord = get_texcoord();
  vec2 velocity = texture(CombinedVelocity, texcoord).xy;
  vec2 last_coord = texcoord + velocity;

  // Out of screen, can early out
  if (out_of_screen(last_coord)) {
    result = vec4(0);
    return;
  }

  float fade = 1.0;

  // Check if reprojected position matches
  float curr_depth = get_depth_at(texcoord);

  #if GET_SETTING(ssr, skip_invalid_samples)
    // Skip samples which are invalid due to a position change or due to being
    // occluded in the last frame.

    // TODO: Should probably use the 3x3 AABB for this, but might be too
    // performance heavy. I think this should work out well.
    vec3 curr_pos = calculate_surface_pos(curr_depth, texcoord);
    float last_depth = textureLod(Previous_SceneDepth, last_coord, 0).x;

    vec3 last_pos = calculate_surface_pos(last_depth, last_coord,
      MainSceneData.last_inv_view_proj_mat_no_jitter);

    if (distance(curr_pos, last_pos) > 0.9) {
      // fade = 0.0;
    }
  #endif

  vec3 intersected_color = texture(Previous_PostAmbientScene, last_coord).xyz;

  // Prevent super bright spots by clamping to a reasonable high color.
  // Otherwise very bright dhighlights lead to artifacts
  intersected_color = clamp(intersected_color, 0.0, 250.0);

  // Tonemap so we don't get super bright spots
  // intersected_color = intersected_color / (1 + intersected_color);


  // Finally store the result in the mip-chian
  result = vec4(intersected_color, 1) * fade;
}
