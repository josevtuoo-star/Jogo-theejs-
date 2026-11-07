// Atmosfera: hora do dia + clima -> ambiente que alimenta o renderer (sol, céu, névoa, vento).
import { clamp, lerp, smoothstep, v3 } from './math.js';

const KEYS = [
  // e (sin elevação do sol), zênite, horizonte
  { e: -0.30, z: [0.0035, 0.0065, 0.018], h: [0.010, 0.016, 0.040] },
  { e: -0.10, z: [0.012, 0.020, 0.050], h: [0.055, 0.050, 0.085] },
  { e: 0.00, z: [0.050, 0.075, 0.190], h: [0.95, 0.40, 0.20] },
  { e: 0.08, z: [0.085, 0.160, 0.400], h: [0.90, 0.58, 0.40] },
  { e: 0.22, z: [0.100, 0.220, 0.560], h: [0.52, 0.64, 0.84] },
  { e: 0.60, z: [0.115, 0.265, 0.650], h: [0.46, 0.62, 0.88] },
];
const mixv = (a, b, t) => [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];

export const WEATHER = {
  clear: { cloud: 0.12, rain: 0, fog: 0.0, wind: 0.25 },
  cloudy: { cloud: 0.6, rain: 0, fog: 0.15, wind: 0.45 },
  overcast: { cloud: 0.95, rain: 0, fog: 0.3, wind: 0.5 },
  rain: { cloud: 1.0, rain: 0.8, fog: 0.5, wind: 0.65 },
  storm: { cloud: 1.0, rain: 1.0, fog: 0.65, wind: 1.0 },
  fog: { cloud: 0.7, rain: 0, fog: 1.0, wind: 0.1 },
};

export class Atmosphere {
  constructor() {
    this.hour = 15.5;
    this.timeScale = 30;     // 1 s real = 30 s de jogo (dia de 48 min)
    this.paused = false;
    this.weatherName = 'clear';
    this.cur = { cloud: 0.12, rain: 0, fog: 0, wind: 0.25 };
    this.tgt = { cloud: 0.12, rain: 0, fog: 0, wind: 0.25 };
    this.windAngle = 0.8;
    this.lat = 48 * Math.PI / 180;
    this.dec = 14 * Math.PI / 180;
    this.env = {
      sunDir: [0, 1, 0], moonDir: [0, -1, 0], sunColor: [3, 3, 3], wetness: 0,
      zenith: [0.1, 0.2, 0.5], horizon: [0.5, 0.6, 0.8], ground: [0.15, 0.13, 0.1], fog: [0.6, 0.7, 0.85],
      fogDensity: 0.0006, fogFalloff: 0.02, ambientScale: 1, cloud: 0.1, shadowStrength: 0.85,
      wind: [0.6, 0.3, 0.3, 0], lights: [null, null, null, null], moon: 0, night: 0, exposure: 1,
    };
    this.rainAmount = 0;
    this.update(0);
  }
  setWeather(name) { this.weatherName = name; Object.assign(this.tgt, WEATHER[name] || WEATHER.clear); }
  sunVector(hour) {
    const H = (hour - 12) / 24 * Math.PI * 2, sl = Math.sin(this.lat), cl = Math.cos(this.lat), sd = Math.sin(this.dec), cd = Math.cos(this.dec);
    const up = sl * sd + cl * cd * Math.cos(H);
    const north = sd * cl - cd * sl * Math.cos(H);
    const east = -cd * Math.sin(H);
    const v = [east, up, -north];
    const l = Math.hypot(...v); return [v[0] / l, v[1] / l, v[2] / l];
  }
  update(dt) {
    if (!this.paused) { this.hour = (this.hour + dt * this.timeScale / 3600) % 24; }
    const k = 1 - Math.exp(-dt * 0.25);
    for (const key of Object.keys(this.tgt)) this.cur[key] += (this.tgt[key] - this.cur[key]) * (dt > 0 ? k : 1);
    const w = this.cur, e = this.env;
    const S = this.sunVector(this.hour);
    e.sunDir = S;
    const el = S[1];
    // céu
    let a = KEYS[0], b = KEYS[KEYS.length - 1], t = 0;
    if (el <= KEYS[0].e) { a = b = KEYS[0]; }
    else if (el >= KEYS[KEYS.length - 1].e) { a = b = KEYS[KEYS.length - 1]; }
    else for (let i = 0; i < KEYS.length - 1; i++) if (el >= KEYS[i].e && el < KEYS[i + 1].e) { a = KEYS[i]; b = KEYS[i + 1]; t = smoothstep(a.e, b.e, el); break; }
    let zen = mixv(a.z, b.z, t), hor = mixv(a.h, b.h, t);
    const lum = (c) => c[0] * 0.3 + c[1] * 0.55 + c[2] * 0.15;
    const oc = clamp(w.cloud, 0, 1) * 0.85 + w.rain * 0.1;
    zen = mixv(zen, [lum(zen) * 0.95, lum(zen) * 1.0, lum(zen) * 1.05], oc);
    hor = mixv(hor, [lum(hor) * 0.9, lum(hor) * 0.95, lum(hor) * 1.0], oc);
    const dark = 1 - w.rain * 0.35;
    e.zenith = [zen[0] * dark, zen[1] * dark, zen[2] * dark];
    e.horizon = [hor[0] * dark, hor[1] * dark, hor[2] * dark];
    e.cloud = clamp(w.cloud * 0.9 + w.rain * 0.1, 0, 1);
    // sol
    const air = 1 / Math.max(el, 0.035);
    const ext = [Math.exp(-0.085 * air * 0.33), Math.exp(-0.19 * air * 0.33), Math.exp(-0.42 * air * 0.33)];
    const horizonFade = smoothstep(-0.03, 0.05, el);
    const sunI = 3.5 * horizonFade * (1 - oc * 0.88);
    e.sunColor = [3.55 * ext[0] * (1 - oc * 0.88) * horizonFade, 3.25 * ext[1] * (1 - oc * 0.88) * horizonFade, 2.95 * ext[2] * (1 - oc * 0.88) * horizonFade];
    // lua
    e.moonDir = [-S[0] * 0.9 + 0.15, Math.max(-S[1], -0.2) * 0.9 + 0.1, -S[2] * 0.9 + 0.1];
    const ml = Math.hypot(...e.moonDir); e.moonDir = e.moonDir.map((x) => x / ml);
    e.night = smoothstep(0.06, -0.14, el);
    e.moon = e.night * 0.75 * (1 - oc * 0.7) * smoothstep(-0.1, 0.15, e.moonDir[1]);
    // névoa
    const dayLum = smoothstep(-0.15, 0.2, el);
    const baseFog = [lerp(hor[0], 0.62 * dayLum + 0.02, oc * 0.7), lerp(hor[1], 0.67 * dayLum + 0.025, oc * 0.7), lerp(hor[2], 0.72 * dayLum + 0.04, oc * 0.7)];
    e.fog = [baseFog[0] * dark, baseFog[1] * dark, baseFog[2] * dark];
    const morning = smoothstep(4.5, 6.5, this.hour) * smoothstep(10, 7.5, this.hour);
    e.fogDensity = 0.00042 + 0.0030 * w.fog + 0.0010 * oc + 0.0012 * w.rain + 0.0006 * morning;
    e.fogFalloff = 0.028 - 0.018 * w.fog;
    // ambiente
    e.ambientScale = (0.72 + 0.25 * dayLum) * (1 - 0.18 * oc);
    const gcol = [0.20, 0.17, 0.12];
    e.ground = [gcol[0] * (0.1 + dayLum), gcol[1] * (0.1 + dayLum), gcol[2] * (0.1 + dayLum)].map((x, i) => x * (1 - e.night * 0.6) + [0.004, 0.006, 0.012][i] * e.night);
    e.wetness += (w.rain * 0.9 - e.wetness) * (1 - Math.exp(-dt * (w.rain > e.wetness ? 0.25 : 0.03)));
    e.shadowStrength = 0.9 * (1 - oc * 0.85);
    e.exposure = lerp(2.6, 1.0, smoothstep(-0.22, 0.18, el)) * (1 + 0.15 * oc);
    // vento
    this.windAngle += dt * 0.01;
    const ws = 0.15 + w.wind * 0.85;
    e.wind = [Math.cos(this.windAngle), Math.sin(this.windAngle), ws, w.wind];
    this.rainAmount = w.rain;
  }
  get hourText() { const h = Math.floor(this.hour), m = Math.floor((this.hour % 1) * 60); return String(h).padStart(2, '0') + ':' + String(m).padStart(2, '0'); }
}
