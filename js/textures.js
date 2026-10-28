import * as THREE from 'three';

// Texturas procedurais geradas em canvas (sem baixar imagens).

function rng(seed) {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}

function makeCanvas(size, draw) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d');
  draw(g, size);
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  return tex;
}

function speckle(g, size, rand, count, colors, minR, maxR, alpha = 0.5) {
  for (let i = 0; i < count; i++) {
    g.globalAlpha = alpha * rand();
    g.fillStyle = colors[(rand() * colors.length) | 0];
    const r = minR + rand() * (maxR - minR);
    g.fillRect(rand() * size, rand() * size, r, r);
  }
  g.globalAlpha = 1;
}

export function grassTexture() {
  return makeCanvas(256, (g, s) => {
    const r = rng(11);
    g.fillStyle = '#4a5530';
    g.fillRect(0, 0, s, s);
    speckle(g, s, r, 4000, ['#3b4526', '#5b6438', '#6b6a40', '#45402a', '#2f3820'], 1, 3, 0.8);
    // manchas de terra seca
    for (let i = 0; i < 14; i++) {
      g.globalAlpha = 0.18;
      g.fillStyle = '#6e5e3e';
      g.beginPath();
      g.arc(r() * s, r() * s, 8 + r() * 26, 0, Math.PI * 2);
      g.fill();
    }
    g.globalAlpha = 1;
  });
}

export function concreteTexture() {
  return makeCanvas(256, (g, s) => {
    const r = rng(22);
    g.fillStyle = '#8a8780';
    g.fillRect(0, 0, s, s);
    speckle(g, s, r, 3000, ['#77746d', '#9a978e', '#6a675f', '#5b5a52'], 1, 3, 0.6);
    // rachaduras e sujeira
    g.strokeStyle = 'rgba(40,38,34,0.5)';
    for (let i = 0; i < 6; i++) {
      g.beginPath();
      let x = r() * s, y = r() * s;
      g.moveTo(x, y);
      for (let j = 0; j < 6; j++) { x += (r() - 0.5) * 40; y += (r() - 0.5) * 40; g.lineTo(x, y); }
      g.stroke();
    }
    const grad = g.createLinearGradient(0, s, 0, s * 0.6);
    grad.addColorStop(0, 'rgba(50,45,30,0.35)');
    grad.addColorStop(1, 'rgba(50,45,30,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, s, s);
  });
}

export function brickTexture() {
  return makeCanvas(256, (g, s) => {
    const r = rng(33);
    g.fillStyle = '#5c544b';
    g.fillRect(0, 0, s, s);
    const bh = 16, bw = 42;
    for (let row = 0; row < s / bh; row++) {
      const off = (row % 2) * bw * 0.5;
      for (let x = -bw; x < s + bw; x += bw) {
        const v = 0.75 + r() * 0.35;
        g.fillStyle = `rgb(${(128 * v) | 0},${(70 * v) | 0},${(52 * v) | 0})`;
        g.fillRect(x + off + 1, row * bh + 1, bw - 3, bh - 3);
      }
    }
    speckle(g, s, r, 1500, ['#2a2520', '#7a7060'], 1, 2, 0.4);
  });
}

export function woodTexture() {
  return makeCanvas(128, (g, s) => {
    const r = rng(44);
    g.fillStyle = '#6b4f30';
    g.fillRect(0, 0, s, s);
    for (let i = 0; i < 40; i++) {
      g.strokeStyle = `rgba(${40 + r() * 40},${25 + r() * 25},10,${0.3 + r() * 0.3})`;
      g.beginPath();
      const y = r() * s;
      g.moveTo(0, y);
      g.bezierCurveTo(s * 0.3, y + (r() - 0.5) * 8, s * 0.6, y + (r() - 0.5) * 8, s, y);
      g.stroke();
    }
    g.fillStyle = 'rgba(20,12,5,0.6)';
    g.fillRect(0, 0, s, 2);
    g.fillRect(0, s / 2, s, 2);
  });
}

export function rustTexture() {
  return makeCanvas(128, (g, s) => {
    const r = rng(55);
    g.fillStyle = '#6a3a24';
    g.fillRect(0, 0, s, s);
    speckle(g, s, r, 1800, ['#4a2616', '#8a5030', '#3a2a20', '#7a6a50'], 1, 4, 0.7);
    // ondulação do contêiner
    for (let x = 0; x < s; x += 8) {
      g.fillStyle = 'rgba(0,0,0,0.22)';
      g.fillRect(x, 0, 3, s);
    }
  });
}

export function barkTexture() {
  return makeCanvas(64, (g, s) => {
    const r = rng(66);
    g.fillStyle = '#3d2f22';
    g.fillRect(0, 0, s, s);
    for (let i = 0; i < 30; i++) {
      g.fillStyle = `rgba(20,14,8,${0.3 + r() * 0.4})`;
      g.fillRect(r() * s, 0, 1 + r() * 2, s);
    }
  });
}
