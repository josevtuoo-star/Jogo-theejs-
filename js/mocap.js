import * as THREE from 'three';

// Locomoção com captura de movimento real (CMU Graphics Lab Motion Capture Database, convertida
// e adaptada ao esqueleto do personagem — ver assets/CREDITS.md). Cada clipe é um ciclo de
// passada (pisada do calcanhar esquerdo até a próxima) amostrado em K pontos, com:
// quadril (rotação + balanço lateral e altura), tronco, coxas/canelas/tornozelos e braços.
// O ciclo é tocado pela fase de passo do próprio jogo (o som da pisada cai na pisada) e os
// clipes se misturam pela velocidade.

const QKEYS = ['hips', 'torso', 'thighL', 'thighR', 'upperL', 'upperR'];
const SKEYS = ['kneeL', 'kneeR', 'ankleL', 'ankleR', 'elbowL', 'elbowR'];

export function makePose() {
  const p = { hipsPos: [0, 0] };
  for (const k of QKEYS) p[k] = new THREE.Quaternion();
  for (const k of SKEYS) p[k] = 0;
  return p;
}

const _q = new THREE.Quaternion(), _q2 = new THREE.Quaternion();

export class MocapLibrary {
  constructor() {
    this.clips = {};
  }

  async load(base = 'assets/anim/', names = ['walk', 'jog', 'run', 'crouch', 'zombie']) {
    await Promise.all(names.map(async (n) => {
      try {
        const r = await fetch(base + n + '.json');
        if (r.ok) this.clips[n] = await r.json();
      } catch { /* sem o clipe: a animação procedural continua */ }
    }));
    return this;
  }

  has(name) { return !!this.clips[name]; }

  /** Pose do clipe na fase u (0..1, repete), interpolando entre as amostras. */
  sample(name, u, out) {
    const c = this.clips[name];
    const K = c.frames;
    const x = (((u % 1) + 1) % 1) * K;
    const i0 = Math.floor(x) % K, i1 = (i0 + 1) % K, t = x - Math.floor(x);
    for (const k of QKEYS) {
      const a = c[k];
      _q.set(a[i0 * 4], a[i0 * 4 + 1], a[i0 * 4 + 2], a[i0 * 4 + 3]);
      _q2.set(a[i1 * 4], a[i1 * 4 + 1], a[i1 * 4 + 2], a[i1 * 4 + 3]);
      out[k].slerpQuaternions(_q, _q2, t);
    }
    for (const k of SKEYS) out[k] = c[k][i0] * (1 - t) + c[k][i1] * t;
    out.hipsPos[0] = c.hipsPos[i0 * 2] * (1 - t) + c.hipsPos[i1 * 2] * t;
    out.hipsPos[1] = c.hipsPos[i0 * 2 + 1] * (1 - t) + c.hipsPos[i1 * 2 + 1] * t;
    return out;
  }
}

/** a = mistura de a e b (t de b). Resultado em a. */
export function blendPose(a, b, t) {
  if (t <= 0) return a;
  for (const k of QKEYS) a[k].slerp(b[k], t);
  for (const k of SKEYS) a[k] += (b[k] - a[k]) * t;
  a.hipsPos[0] += (b.hipsPos[0] - a.hipsPos[0]) * t;
  a.hipsPos[1] += (b.hipsPos[1] - a.hipsPos[1]) * t;
  return a;
}
