/* ============================================================
   SilaFit: "Sila" flame-spirit mascot helpers
   The art mirrors frontend/assets/mascot/flame/{light,dark}/: burgundy
   and mustard on cream for light mode, soft lime on teal for dark mode.
   Every mascot ships both variants. css/base.css (.sila) shows the one
   that matches <html data-theme>, so toggling the theme never refetches
   or flashes. Both images are lazy, so the hidden one is never downloaded.

     window.Sila.html('sleepy', { size: 96, glow: true, alive: true })
     window.Sila.set(element, 'shocked')     // swap the pose in place
   ============================================================ */
(function () {
  'use strict';

  var ARTS = ['spark', 'flame', 'blaze', 'determined', 'laughing', 'smug', 'sleepy', 'shocked'];
  var BASE = 'assets/img/mascot/flame/';

  function normalise(art) {
    return ARTS.indexOf(art) >= 0 ? art : 'flame';
  }

  function src(theme, art) {
    return BASE + theme + '/' + normalise(art) + '.webp';
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
      '<img class="sila__art sila__art--dark" src="' + src('dark', art) + '" width="384" height="384" alt="" loading="lazy" decoding="async" />' +
      '<img class="sila__art sila__art--light" src="' + src('light', art) + '" width="384" height="384" alt="" loading="lazy" decoding="async" />' +
      '</span>';
  }

  function set(el, art) {
    if (!el) return;
    art = normalise(art);
    if (el.getAttribute('data-sila') === art) return;
    el.setAttribute('data-sila', art);
    var dark = el.querySelector('.sila__art--dark');
    var light = el.querySelector('.sila__art--light');
    if (dark) dark.src = src('dark', art);
    if (light) light.src = src('light', art);
    /* A little pop so the change of mood reads as a reaction. */
    el.classList.remove('sila--react');
    void el.offsetWidth;
    el.classList.add('sila--react');
  }

  window.Sila = { html: html, set: set, arts: ARTS.slice() };
})();
