/* ============================================================
   SilaFit: "Sila" the ram mascot helpers
   The art mirrors frontend/assets/mascot/ram/. Its dark ink outline is
   the edge (no sticker border), so one image reads on both the light
   and the dark site theme.

     window.Sila.html('sleepy', { size: 96, glow: true, alive: true })
     window.Sila.set(element, 'shocked')     // swap the pose in place
     window.Sila.celebrate(element, { onLand: fn })  // the big moment

   celebrate() is the same routine as the app's CelebratingRam: a crouch,
   a leap with a full turn in the air (the back view shows while Sila faces
   away), a squash landing into a fist pump with rays and a shock ring,
   then back to the resting pose. Head-only art hops and laughs instead.
   ============================================================ */
(function () {
  'use strict';

  var ARTS = ['standing', 'charging', 'back', 'emblem', 'determined', 'laughing', 'smug', 'sleepy', 'shocked'];
  /* Names from the old flame set, so stale callers still get sensible art. */
  var LEGACY = { flame: 'standing', blaze: 'charging', spark: 'smug' };
  var BASE = 'assets/img/mascot/ram/';
  var VERSION = '20261103-real';

  function normalise(art) {
    art = LEGACY[art] || art;
    return ARTS.indexOf(art) >= 0 ? art : 'standing';
  }

  function src(art) {
    return BASE + normalise(art) + '.webp?v=' + VERSION;
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

  var FULL_BODY = ['standing', 'charging'];
  var DURATION = 2600;
  var preloaded = {};
  function preload(arts) {
    arts.forEach(function (art) {
      if (preloaded[art]) return;
      preloaded[art] = new Image();
      preloaded[art].src = src(art);
    });
  }

  /* Rays and the shock ring live in one decorative layer behind the art. */
  function fxLayer(el) {
    var fx = el.querySelector('.sila__fx');
    if (!fx) {
      fx = document.createElement('span');
      fx.className = 'sila__fx';
      fx.setAttribute('aria-hidden', 'true');
      fx.innerHTML = '<span class="sila__rays"></span><span class="sila__ring"></span>';
      el.insertBefore(fx, el.firstChild);
    }
    return fx;
  }

  function celebrate(el, opts) {
    opts = opts || {};
    if (!el) return;
    var img = el.querySelector('.sila__art');
    if (!img) return;
    var rest = el.getAttribute('data-sila-rest') || el.getAttribute('data-sila') || 'standing';
    el.setAttribute('data-sila-rest', rest);
    var full = FULL_BODY.indexOf(rest) >= 0;
    var cheerArt = full ? (rest === 'charging' ? 'standing' : 'charging') : 'laughing';
    var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    preload(full ? ['back', cheerArt, rest] : [cheerArt, rest]);

    clearTimeout(el._silaRest);
    (el._silaTimers || []).forEach(clearTimeout);
    el._silaTimers = [];
    (el._silaAnims || []).forEach(function (a) { a.cancel(); });
    el._silaAnims = [];

    function show(art) { img.src = src(art); }
    function at(fraction, fn) { el._silaTimers.push(setTimeout(fn, fraction * DURATION)); }

    /* Without motion (or the Web Animations API) Sila just changes face. */
    if (reduce || !img.animate) {
      show(cheerArt);
      if (opts.onLand) opts.onLand();
      el._silaRest = setTimeout(function () { show(rest); }, 1800);
      return;
    }

    el.classList.add('sila--celebrating');
    var anims = el._silaAnims;
    function play(target, frames) {
      var a = target.animate(frames, { duration: DURATION, fill: 'none' });
      anims.push(a);
      return a;
    }
    var up = 'cubic-bezier(0.33, 1, 0.68, 1)', down = 'cubic-bezier(0.32, 0, 0.67, 0)';
    var height = full ? '-34%' : '-20%';

    /* translate, rotate and scale are separate properties, so the jump,
       the spin and the squash-and-stretch each get their own easing and
       still stack with the resting breath on transform. */
    play(img, [
      { offset: 0, translate: '0 0' },
      { offset: 0.10, translate: '0 0', easing: up },
      { offset: 0.25, translate: '0 ' + height, easing: down },
      { offset: 0.40, translate: '0 0' },
      { offset: 1, translate: '0 0' }
    ]);
    play(img, [
      { offset: 0, scale: '1 1', easing: 'cubic-bezier(0.22, 1, 0.36, 1)' },
      { offset: 0.10, scale: '1.10 0.86' },
      { offset: 0.105, scale: '0.93 1.13', easing: up },
      { offset: 0.25, scale: '1 1', easing: down },
      { offset: 0.39, scale: '0.96 1.07' },
      { offset: 0.41, scale: '1.13 0.83', easing: 'ease-out' },
      { offset: 0.47, scale: '0.95 1.06', easing: 'ease-in-out' },
      { offset: 0.53, scale: '1.03 0.98', easing: 'ease-in-out' },
      { offset: 0.60, scale: '1 1' },
      { offset: 0.84, scale: '1 1', easing: 'ease-out' },
      { offset: 0.88, scale: '0.95 1.07', easing: 'ease-in-out' },
      { offset: 0.93, scale: '1.02 0.98', easing: 'ease-in-out' },
      { offset: 1, scale: '1 1' }
    ]);
    if (full) {
      /* One whip-fast turn; the back view shows between 90 and 270 deg. */
      play(img, [
        { offset: 0, rotate: 'y 0deg' },
        { offset: 0.13, rotate: 'y 0deg', easing: 'cubic-bezier(0.65, 0, 0.35, 1)' },
        { offset: 0.37, rotate: 'y 360deg' },
        { offset: 0.40, rotate: 'z 0deg' },
        { offset: 0.43, rotate: 'z -3deg' },
        { offset: 0.46, rotate: 'z 2.5deg' },
        { offset: 0.50, rotate: 'z -1deg' },
        { offset: 0.54, rotate: 'z 0deg' },
        { offset: 1, rotate: 'z 0deg' }
      ]);
      /* easeInOutCubic reaches a quarter and three quarters of the turn
         at ~40% and ~60% of the spin window. */
      at(0.13 + 0.24 * 0.397, function () { show('back'); });
      at(0.13 + 0.24 * 0.603, function () { show(rest); });
    } else {
      /* A head can't spin convincingly, so it laughs and shakes instead. */
      play(img, [
        { offset: 0, rotate: 'z 0deg' },
        { offset: 0.42, rotate: 'z 0deg' },
        { offset: 0.48, rotate: 'z -7deg' },
        { offset: 0.55, rotate: 'z 6deg' },
        { offset: 0.62, rotate: 'z -3deg' },
        { offset: 0.70, rotate: 'z 0deg' },
        { offset: 1, rotate: 'z 0deg' }
      ]);
      at(0.22, function () { show(cheerArt); });
    }

    var fx = fxLayer(el);
    play(fx.querySelector('.sila__rays'), [
      { offset: 0, opacity: 0, rotate: '0deg', scale: 0.6 },
      { offset: 0.38, opacity: 0, rotate: '10deg', scale: 0.6, easing: 'cubic-bezier(0.22, 1, 0.36, 1)' },
      { offset: 0.50, opacity: 1, rotate: '22deg', scale: 1 },
      { offset: 0.80, opacity: 0.85, rotate: '45deg', scale: 1.02 },
      { offset: 1, opacity: 0, rotate: '60deg', scale: 1.05 }
    ]);
    play(fx.querySelector('.sila__ring'), [
      { offset: 0, opacity: 0, scale: 0.3 },
      { offset: 0.399, opacity: 0, scale: 0.3 },
      { offset: 0.40, opacity: 0.9, scale: 0.3, easing: 'cubic-bezier(0.22, 1, 0.36, 1)' },
      { offset: 0.64, opacity: 0, scale: 2.1 },
      { offset: 1, opacity: 0, scale: 2.1 }
    ]);

    at(0.40, function () {
      if (full) show(cheerArt);
      if (opts.onLand) opts.onLand();
    });
    at(0.84, function () { show(rest); });
    at(1, function () { el.classList.remove('sila--celebrating'); });
  }

  window.Sila = { html: html, set: set, celebrate: celebrate, arts: ARTS.slice() };
})();
