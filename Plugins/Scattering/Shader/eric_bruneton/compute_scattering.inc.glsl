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



// Include local scattering code
#define NO_COMPUTE_SHADER 1
#pragma include "scattering_common.glsl"

uniform sampler3D InscatterSampler;

vec3 sun_vector = sun_azimuth_to_angle(
        TimeOfDay.Scattering.sun_azimuth,
        TimeOfDay.Scattering.sun_altitude);


vec3 DoScattering(vec3 surfacePos, vec3 viewDir, out float fog_factor)
{

    // Move surface pos above ocean level
    // if (surfacePos.z < -0.01) {
    //     vec3 v2s = surfacePos - MainSceneData.camera_pos;
    //     float z_factor = abs(MainSceneData.camera_pos.z) / abs(v2s.z);
    //     surfacePos = MainSceneData.camera_pos + v2s * z_factor;
    //     viewDir = normalize(surfacePos - MainSceneData.camera_pos);
    // }

    vec3 inscatteredLight = vec3(0.0);
    float groundH = Rg + 2.0;
    float pathLength = distance(MainSceneData.camera_pos, surfacePos);
    vec3 startPos = MainSceneData.camera_pos; 

    float height_scale_factor = 0.01;

    float startPosHeight = MainSceneData.camera_pos.z * height_scale_factor + groundH;
    float surfacePosHeight = surfacePos.z * height_scale_factor + groundH;

    float muStartPos = viewDir.z;
    float nuStartPos = max(0, dot(viewDir, sun_vector));
    float musStartPos = sun_vector.z;

    vec4 inscatter = max(texture4D(InscatterSampler, startPosHeight,
        muStartPos, musStartPos, nuStartPos), 0.0);
        
    fog_factor = 1.0;
    float sun_factor = 1.0; 

    float phaseR = phaseFunctionR(nuStartPos);
    float phaseM = phaseFunctionM(nuStartPos);

    if(pathLength < 20000 || viewDir.z < 0.0)
    {

        // Exponential height fog
        float fog_ramp = TimeOfDay.Scattering.fog_ramp_size;
        float fog_start = TimeOfDay.Scattering.fog_start;

        // Exponential, I do not like the look
        // fog_factor = saturate((1.0 - exp( -pathLength * viewDir.z / fog_ramp )) / viewDir.z);

        // Looks better IMO
        fog_factor = smoothstep(0, 1, (pathLength-fog_start) / fog_ramp);

        // Produces a smoother transition, but the borders look weird then    
        // fog_factor = pow(fog_factor, 1.0 / 2.2);

        // Get atmospheric color, 2 or 3 samples should be enough
        const int num_samples = 2;
        const float height_decay = 400.0;

        float current_height = max(surfacePos.z, MainSceneData.camera_pos.z);
        current_height *= 1.0 - saturate(pathLength / 25000.0);
        float dest_height = surfacePos.z;
        float height_step = (dest_height - current_height) / num_samples;

        vec4 inscatter_sum = vec4(0);
        for (int i = 0; i < num_samples; ++i) {
            inscatter_sum += texture4D(InscatterSampler, 
                current_height * height_scale_factor + groundH, 
                current_height / height_decay + 0.001,
                musStartPos, nuStartPos);

            current_height += height_step;
        }

        inscatter_sum /= float(num_samples);
        inscatter_sum *= 0.5;

        // Exponential height fog
        fog_factor *= exp(- surfacePos.z / TimeOfDay.Scattering.ground_fog_factor);

        // Scale fog color
        vec4 fog_color = inscatter_sum * TimeOfDay.Scattering.fog_brightness;

        // Tint fog color a bit, and also desaturate it
        fog_color *= fog_factor * 3.0;
        fog_color += 0.0018;

        // Scale the fog factor after tinting the color, this reduces the ambient term
        // even more, this is a purely artistic choice
        // fog_factor = saturate(fog_factor * 1.6);

        // Reduce sun factor, we don't want to have a sun disk shown trough objects
        float mix_factor = smoothstep(0, 1, (pathLength-10000.0) / 10000.0);
        inscatter = mix(fog_color, inscatter, mix_factor);
        sun_factor = 0;
    }

    // Apply inscattered light
    inscatteredLight = max(inscatter.rgb * phaseR + getMie(inscatter) * phaseM, 0.0f);
    inscatteredLight *= 70.0;

    // Don't show sun below horizon, and also don't show scattering below horizon
    inscatteredLight *= saturate( (sun_vector.z+0.1) * 40.0);

    return inscatteredLight;
}

