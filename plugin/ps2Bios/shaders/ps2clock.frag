#version 440

// Crystal clock: twelve radial prisms (hours) around a ring of drifting light orbs.
// The prism at the current hour lights up, its glow filling with the minutes.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float iTime;
    float hourValue;
    float minuteFrac;
    float glowStrength;
    float grain;
    float orbCount;
    float spinSpeed;
    float shiftX;
    float introT;
    vec2 resolution;
    vec4 colA;
    vec4 colB;
    vec4 colOrb;
    vec4 colBg;
};

const float PI = 3.14159265;
const float TAU = 6.28318531;
const float SECTOR = TAU / 12.0;
const float R_IN = 1.05;
const float PRISM_R = 0.11;

float hash11(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float hash21(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743); }

float noise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise2(p);
        p = p * 2.03 + vec2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

float sdHexPrism(vec3 p, vec2 h) {
    const vec3 k = vec3(-0.8660254, 0.5, 0.57735);
    p = abs(p);
    p.xy -= 2.0 * min(dot(k.xy, p.xy), 0.0) * k.xy;
    vec2 d = vec2(length(p.xy - vec2(clamp(p.x, -k.z * h.x, k.z * h.x), h.x)) * sign(p.y - h.x), p.z - h.y);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

// Per-hour shape: length and a slow breathing offset along the radius.
float prismLen(float k) { return 0.95 + 0.55 * hash11(k + 3.0); }
float prismOffset(float k) { return 0.06 * sin(iTime * 0.35 + k * 1.7); }

// Boot sequence: prisms grow out one after another once the orbs have gathered.
float growOf(float k) { return smoothstep(2.7 + k * 0.08, 4.1 + k * 0.08, introT); }

// Clock angle measured clockwise from 12 o'clock.
float clockAngle(vec2 p) { return atan(p.x, p.y); }

// Prism local frame: x/y = cross-section, z = along the radius (0 at its middle).
vec3 prismLocal(vec3 p, float k, out float along01) {
    float a = k * SECTOR;
    vec2 dir = vec2(sin(a), cos(a));
    vec2 side = vec2(dir.y, -dir.x);
    float len = prismLen(k) * max(growOf(k), 0.02);
    float r0 = R_IN + prismOffset(k);
    float along = dot(p.xy, dir) - (r0 + len * 0.5);
    float u = dot(p.xy, side);
    float w = p.z;
    float s = iTime * spinSpeed + k * 0.6;
    float cs = cos(s), sn = sin(s);
    vec2 uw = vec2(cs * u - sn * w, sn * u + cs * w);
    along01 = clamp((along + len * 0.5) / len, 0.0, 1.0);
    return vec3(uw, along);
}

float prismDist(vec3 p, float k) {
    float g = growOf(k);
    if (g < 0.01)
        return 1.0;
    float t;
    vec3 q = prismLocal(p, k, t);
    return sdHexPrism(q, vec2(PRISM_R * (0.35 + 0.65 * g), prismLen(k) * g * 0.5)) - 0.012;
}

float nearestSector(vec3 p) {
    float a = clockAngle(p.xy);
    return mod(floor(a / SECTOR + 0.5), 12.0);
}

float map(vec3 p, out float id) {
    // Only the prism in this clock sector, but never step past the sector edge
    // (where a neighbour could be closer than the bound says).
    float a = clockAngle(p.xy);
    float k = mod(floor(a / SECTOR + 0.5), 12.0);
    float local = a - floor(a / SECTOR + 0.5) * SECTOR;
    float edge = length(p.xy) * sin(SECTOR * 0.5 - abs(local)) + 0.02;
    id = k;
    return min(prismDist(p, k), edge);
}

float mapOnly(vec3 p) {
    float id;
    return map(p, id);
}

vec3 calcNormal(vec3 p) {
    const vec2 e = vec2(1.0, -1.0) * 0.0015;
    return normalize(e.xyy * mapOnly(p + e.xyy) + e.yyx * mapOnly(p + e.yyx) + e.yxy * mapOnly(p + e.yxy) + e.xxx * mapOnly(p + e.xxx));
}

vec3 orbPos(float i, float t) {
    float n = max(orbCount, 1.0);
    float a = i / n * TAU + t * 0.45 + 0.4 * sin(t * 0.21 + i * 2.3);
    float r = 0.62 + 0.12 * sin(t * 0.7 + i * 1.9);
    return vec3(sin(a) * r, cos(a) * r, 0.18 * sin(t * 0.9 + i * 2.7));
}

// During the boot sequence the orbs streak in from far out and gather into the ring.
vec3 orbPosIntro(float i, float t, float it) {
    vec3 o = orbPos(i, t);
    float e = smoothstep(0.3, 3.0, it);
    e = 1.0 - pow(1.0 - e, 3.0);
    float spin = (1.0 - e) * (2.5 + i * 0.3);
    float cs = cos(spin), sn = sin(spin);
    o.xy = vec2(cs * o.x - sn * o.y, sn * o.x + cs * o.y);
    return o * (1.0 + (1.0 - e) * 7.0) + vec3(0.0, 0.0, (1.0 - e) * 2.5);
}

void main() {
    vec2 frag = qt_TexCoord0 * resolution;
    vec2 uv = (frag - 0.5 * resolution) / resolution.y;
    uv.y = -uv.y;

    // Slow drifting camera, looking slightly down onto the ring.
    float t = iTime;
    vec3 target = vec3(0.0, 0.05, 0.0);
    vec3 ro = vec3(0.35 * sin(t * 0.05), -2.6 + 0.15 * sin(t * 0.07), 5.4);
    vec3 fw = normalize(target - ro);
    vec3 rt = normalize(cross(fw, vec3(0.0, 0.0, 1.0)));
    vec3 up = cross(rt, fw);
    float roll = 0.08 * sin(t * 0.03);
    vec3 rtR = rt * cos(roll) + up * sin(roll);
    vec3 upR = up * cos(roll) - rt * sin(roll);
    vec3 rd = normalize(fw * 1.95 + (uv.x - shiftX) * rtR + uv.y * upR);

    // Background: deep indigo fog.
    vec2 fogUv = uv * 1.6 + vec2(t * 0.012, -t * 0.008);
    float fog = fbm(fogUv + fbm(fogUv * 0.7 + t * 0.01));
    vec3 col = colBg.rgb * (0.45 + 1.3 * fog);
    col += colA.rgb * 0.16 * smoothstep(0.4, 0.95, fog);
    col += colB.rgb * 0.06 * smoothstep(0.55, 1.0, fbm(fogUv * 1.7 - t * 0.02));
    col *= 1.0 - 0.35 * length(uv);
    col *= smoothstep(1.2, 4.5, introT);

    // March only inside the slab that can hold prisms.
    float hitT = 1e9;
    float id = -1.0;
    float minLit = 1e9;
    float hourIdx = hourValue < 0.0 ? -10.0 : mod(floor(hourValue), 12.0);
    if (abs(rd.z) > 1e-4) {
        float slab = 0.45;
        float t0 = (slab - ro.z) / rd.z;
        float t1 = (-slab - ro.z) / rd.z;
        float tn = max(min(t0, t1), 0.0);
        float tf = max(t0, t1);
        float tt = tn;
        for (int i = 0; i < 64; i++) {
            if (tt > tf)
                break;
            vec3 p = ro + rd * tt;
            float pid;
            float d = map(p, pid);
            if (abs(pid - hourIdx) < 0.5 || abs(abs(pid - hourIdx) - 11.0) < 0.5 || abs(abs(pid - hourIdx) - 1.0) < 0.5)
                minLit = min(minLit, prismDist(p, hourIdx));
            if (d < 0.0015) {
                hitT = tt;
                id = pid;
                break;
            }
            tt += d * 0.9;
        }
    }

    if (id >= 0.0) {
        vec3 p = ro + rd * hitT;
        vec3 n = calcNormal(p);
        float along01;
        prismLocal(p, id, along01);
        vec3 base = mix(colA.rgb, colB.rgb, smoothstep(0.0, 1.0, along01 * 0.8 + 0.1 * sin(id * 2.0 + t * 0.2)));
        vec3 l = normalize(vec3(-0.4, 0.6, 0.8));
        float diff = clamp(dot(n, l), 0.0, 1.0);
        float fres = pow(1.0 - clamp(dot(n, -rd), 0.0, 1.0), 3.0);
        float spec = pow(clamp(dot(reflect(rd, n), l), 0.0, 1.0), 24.0);
        // Fake translucency: brighter toward the centre where the orbs are.
        float inner = smoothstep(2.4, R_IN, length(p.xy));
        float back = pow(clamp(dot(n, normalize(vec3(-p.xy, 0.3))), 0.0, 1.0), 2.0);
        vec3 crystal = base * (0.18 + 0.42 * diff + 0.55 * inner + 0.35 * back) + vec3(0.85, 0.95, 1.0) * (fres * 0.8 + spec * 0.7);
        if (abs(id - hourIdx) < 0.5) {
            float filled = 1.0 - smoothstep(minuteFrac - 0.02, minuteFrac + 0.02, along01);
            vec3 hot = mix(base, vec3(1.0), 0.55);
            crystal = mix(crystal, hot * (1.2 + 0.25 * sin(t * 2.0)), filled * 0.85);
            crystal += hot * 0.18;
        }
        col = mix(col, crystal, 0.8) + base * fres * 0.25;
    }

    // Halo around the lit hour prism.
    vec3 litCol = mix(colA.rgb, vec3(1.0), 0.4);
    col += litCol * glowStrength * 0.16 * exp(-minLit * 7.0);

    // Orbs with short comet trails, plus the faint ring they ride on.
    vec3 orbAcc = vec3(0.0);
    int count = int(clamp(orbCount, 0.0, 12.0));
    for (int i = 0; i < 12; i++) {
        if (i >= count)
            break;
        for (int s = 0; s < 10; s++) {
            float ts = t - float(s) * 0.03;
            vec3 o = orbPosIntro(float(i), ts, introT - float(s) * 0.03);
            vec3 oc = o - ro;
            float tp = dot(oc, rd);
            if (tp < 0.0)
                continue;
            float dist = length(oc - rd * tp);
            float occl = tp > hitT ? 0.15 : 1.0;
            float w = s == 0 ? 1.0 : 0.45 * (1.0 - float(s) / 10.0);
            float core = exp(-dist * dist * 2600.0);
            float halo = s == 0 ? exp(-dist * 20.0) : 0.0;
            orbAcc += colOrb.rgb * occl * (w * core * 1.8 + halo * 0.9 * glowStrength);
        }
    }
    col += orbAcc;

    // The flash when the orbs lock into the ring.
    float flash = exp(-pow((introT - 3.0) * 2.6, 2.0));
    col += colOrb.rgb * flash * (1.1 * exp(-length(uv) * 3.2) + 0.05);

    if (abs(rd.z) > 1e-4) {
        float tp = -ro.z / rd.z;
        if (tp > 0.0 && tp < hitT) {
            vec3 pp = ro + rd * tp;
            float ring = abs(length(pp.xy) - 0.62);
            col += colOrb.rgb * 0.14 * exp(-ring * 60.0) * glowStrength * smoothstep(2.8, 3.8, introT);
        }
    }

    // Grain and tone.
    float g = hash21(frag + fract(t * 7.13) * 431.0) - 0.5;
    col += g * grain * 0.08;
    col = col / (1.0 + col * 0.35);
    col = pow(max(col, 0.0), vec3(0.95));

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
