// Ícones dos botões touch (SVG em linha: ficam iguais em qualquer celular, ao contrário dos
// emojis, que mudam de desenho conforme o aparelho — o 🔫 vira pistola d'água em vários Androids).

const svg = (body, extra = '') =>
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" ${extra}>${body}</svg>`;

export const ICONS = {
  fist: svg('<path d="M7 11V7.5a1.5 1.5 0 0 1 3 0V10m0-3.5a1.5 1.5 0 0 1 3 0V10m0-3a1.5 1.5 0 0 1 3 0v3.5m0-1.5a1.5 1.5 0 0 1 3 0v4.5c0 3.6-2.6 6.5-6.2 6.5H11c-2.8 0-5-2.2-5-5v-1.6c0-1 .6-1.9 1.5-2.3L10 11"/>'),
  knife: svg('<path d="M3.5 20.5l4.2-4.2"/><path d="M6.3 14.9l2.8 2.8"/><path d="M8.4 15.6L20.5 3.5c.6 2.7-.2 6.7-3.6 10.1l-3.2 3.2"/><path d="M2.8 17.8l3.4 3.4"/>'),
  gun: svg('<path d="M2.5 8.5h15.5l1.5-1.5h2v4h-8.5l-1 1.5H9.6l-1.2 1.8-.9 4.2H3.8l1.7-6.5H2.5z"/><circle cx="12.3" cy="10.2" r="1.3"/><path d="M10.2 13.5c.4 1.2 1.6 1.6 2.6 1.2"/>'),
  reload: svg('<path d="M20 11a8 8 0 0 0-14.6-4.5L4 8"/><path d="M4 3.5V8h4.5"/><path d="M4 13a8 8 0 0 0 14.6 4.5L20 16"/><path d="M20 20.5V16h-4.5"/>'),
  aim: svg('<circle cx="12" cy="12" r="7.5"/><circle cx="12" cy="12" r="1.2" fill="currentColor"/><path d="M12 1.5v4M12 18.5v4M1.5 12h4M18.5 12h4"/>'),
  jump: svg('<path d="M12 19V5"/><path d="M6 11l6-6 6 6"/><path d="M5 21h14"/>'),
  crouch: svg('<path d="M6 7l6 6 6-6"/><path d="M6 13l6 6 6-6"/>'),
  sprint: svg('<circle cx="14.5" cy="4.5" r="1.8"/><path d="M9 21l2.5-5 3 2.5V22"/><path d="M5 12.5l3-3.5h4.5l2.5 3.5 3.5 1"/><path d="M11.5 9l-1 5.5"/>'),
  light: svg('<path d="M9.5 14.5l-5 5a1.8 1.8 0 0 0 2.5 2.5l5-5"/><path d="M8 11l5 5 7.5-4.5-8-8z"/><path d="M17 3l1.5-1.5M21 7l1.5-1.5M19.5 4.5l2-.5"/>'),
  view: svg('<path d="M1.5 12S5.5 4.5 12 4.5 22.5 12 22.5 12 18.5 19.5 12 19.5 1.5 12 1.5 12z"/><circle cx="12" cy="12" r="3.2"/>'),
  pause: svg('<path d="M8 5v14M16 5v14"/>', 'stroke-width="3"'),
  use: svg('<path d="M8 13V5.5a1.5 1.5 0 0 1 3 0V12m0-1.5V4a1.5 1.5 0 0 1 3 0v8m0-6.5a1.5 1.5 0 0 1 3 0V13m0-4.5a1.5 1.5 0 0 1 3 0V15c0 4-3 7-7 7h-1.4c-2.2 0-4.2-1.2-5.3-3.1L3 14.6a1.6 1.6 0 0 1 2.6-1.8L8 15.5"/>'),
  shotgun: svg('<path d="M1.5 9.2h13.8l.9-.9h6.3v2.6H11.4l-.9 1.3H8.3l-1.6 1.2-2.3 4.2H1.6l1.8-5.6H1.5z"/><path d="M14.5 10.9h8"/><path d="M8.6 12.2c.2 1.1 1 1.6 2 1.3"/>'),
  crossbow: svg('<path d="M12 21V8"/><path d="M3 9.5C5.5 6 9 4.5 12 4.5s6.5 1.5 9 5"/><path d="M3 9.5L12 15l9-5.5"/><path d="M12 4.5V2.5"/><path d="M10 17.5h4l-.8 3.5h-2.4z"/>'),
  bat: svg('<path d="M4.2 19.8l1.5 1.5"/><path d="M5 20.5L18 7.5c1.5-1.5 2.8-2.4 3.3-1.9s-.4 1.8-1.9 3.3L6.5 22"/><path d="M13.5 10.3l1.6 1.6M15.6 8.2l1.6 1.6M17.6 6.3l1.4 1.4"/>'),
  bandage: svg('<rect x="2.5" y="8" width="19" height="8" rx="4" transform="rotate(-35 12 12)"/><path d="M9.5 9.5l5 5M11 11h.01M13 13h.01M11 13h.01M13 11h.01"/>'),
  food: svg('<path d="M5 9h14v9.5a2.5 2.5 0 0 1-2.5 2.5h-9A2.5 2.5 0 0 1 5 18.5z"/><ellipse cx="12" cy="9" rx="7" ry="2.2"/><path d="M8 14h8"/>'),
  water: svg('<path d="M10 2.5h4v2.5l1.5 2v13a1.5 1.5 0 0 1-1.5 1.5h-4A1.5 1.5 0 0 1 8.5 20V7L10 5z"/><path d="M8.5 11h7M8.5 16h7"/>'),
  swap: svg('<path d="M4 8h14l-3.5-3.5"/><path d="M20 16H6l3.5 3.5"/>'),
};

/** Monta o conteúdo de um botão: ícone grande + legenda curta. */
export function buttonHTML(icon, label = '') {
  return `<span class="ico">${ICONS[icon] ?? ''}</span>${label ? `<span class="lbl">${label}</span>` : ''}`;
}
