/* ============================================================
   SilaFit: "Sila" the ram mascot helpers
   The art mirrors frontend/assets/mascot/ram/. Its dark ink outline is
   the edge (no sticker border), so one image reads on both the light
   and the dark site theme.

     window.Sila.html('sleepy', { size: 96, glow: true, alive: true })
     window.Sila.set(element, 'shocked')     // swap the pose in place
   ============================================================ */
(function () {
  'use strict';

  var ARTS = ['standing', 'charging', 'emblem', 'determined', 'laughing', 'smug', 'sleepy', 'shocked'];
  /* Names from the old flame set, so stale callers still get sensible art. */
  var LEGACY = { flame: 'standing', blaze: 'charging', spark: 'smug' };
  var BASE = 'assets/img/mascot/ram/';

  function normalise(art) {
    art = LEGACY[art] || art;
    return ARTS.indexOf(art) >= 0 ? art : 'standing';
  }

  function src(art) {
    return BASE + normalise(art) + '.webp?v=20261102-ink';
  }

  function escAttr(value) {
    return String(value).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
  }

  /* opts: size (px), alt (omit for decorative), glow, alive, className */
  function html(art, opts) {
    opts = opts || {};
    art = normalise(art);
    var classes = ['sila'];
    if (opts.glow) classes.push('sila--glow');
    if (opts.alive) classes.push('sila--alive');
    if (opts.className) classes.push(opts.className);
    var style = opts.size ? ' style="--sila-size:' + Number(opts.size) + 'px"' : '';
    var label = opts.alt
      ? ' role="img" aria-label="' + escAttr(opts.alt) + '"'
      : ' aria-hidden="true"';
    return '<span class="' + classes.join(' ') + '" data-sila="' + art + '"' + style + label + '>' +
      '<img class="sila__art" src="' + src(art) + '" width="512" height="512" alt="" loading="lazy" decoding="async" />' +
      '</span>';
  }

  function set(el, art) {
    if (!el) return;
    art = normalise(art);
    if (el.getAttribute('data-sila') === art) return;
    el.setAttribute('data-sila', art);
    var img = el.querySelector('.sila__art');
    if (img) img.src = src(art);
    /* A little pop so the change of mood reads as a reaction. */
    el.classList.remove('sila--react');
    void el.offsetWidth;
    el.classList.add('sila--react');
  }

  window.Sila = { html: html, set: set, arts: ARTS.slice() };
})();
