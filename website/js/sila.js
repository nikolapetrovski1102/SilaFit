/* ============================================================
   SilaFit: "Sila" the ram mascot helpers
   The art mirrors frontend/assets/mascot/ram/. Its dark ink outline is
   the edge (no sticker border), so one image reads on both the light
   and the dark site theme.

     window.Sila.html('sleepy', { size: 96, glow: true, alive: true })
     window.Sila.set(element, 'shocked')       // swap the pose, scrubbed in
     window.Sila.scribble(element, { delay })  // play the reveal
     window.Sila.celebrate(element, { onLand: fn })  // the big moment

   Sila arrives the way the app's ScribbleReveal does it: a fat marker
   zigzags back and forth across the box from top to bottom, and the art
   shows only where the marker has been. Then Sila stays still: no hops,
   bobs or bounces. `sila--alive` mascots scrub in the first time they
   scroll into view (after the page loader has lifted).

   celebrate() follows the app's celebration dialog: Sila is scrubbed in
   in a cheering pose and the confetti (onLand) goes off once the scrub is
   done, then Sila is scrubbed back into the resting pose.
   ============================================================ */
(function () {
  'use strict';

  var ARTS = ['standing', 'charging', 'back', 'emblem', 'determined', 'laughing', 'smug', 'sleepy', 'shocked'];
  /* Names from the old flame set, so stale callers still get sensible art. */
  var LEGACY = { flame: 'standing', blaze: 'charging', spark: 'smug' };
  /* Pages in a subfolder (the Macedonian /mk/) set data-root="../". */
  var BASE = (document.documentElement.getAttribute('data-root') || '') + 'assets/img/mascot/ram/';
  var VERSION = '20261112-ram';
  var SVG_NS = 'http://www.w3.org/2000/svg';

  /* The app's ScribbleReveal: 620ms, five passes, easeInOut. */
  var SCRUB_MS = 620;
  var PASSES = 5;

  function reduceMotion() {
    return !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  }

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

  var preloaded = {};
  function preload(arts) {
    arts.forEach(function (art) {
      if (preloaded[art]) return;
      preloaded[art] = new Image();
      preloaded[art].src = src(art);
    });
  }

  /* ---------- The scrub ----------
     The art is drawn into an inline SVG over the <img>, masked by one
     zigzag stroke (pathLength 1) whose dash offset runs from 1 to 0. Each
     pass drops a fifth of the box; the brush is 1.7 steps wide so
     neighbouring passes overlap and leave no gaps. Once it has covered
     everything the overlay goes and the plain <img> is back. */
  var uid = 0;

  function stopScrub(el) {
    if (el._silaScrub) {
      el._silaScrub.anim && el._silaScrub.anim.cancel();
      clearTimeout(el._silaScrub.timer);
      if (el._silaScrub.svg && el._silaScrub.svg.parentNode) el._silaScrub.svg.remove();
      el._silaScrub = null;
    }
    el.classList.remove('sila--scrubbing');
  }

  function buildOverlay(href) {
    var step = 100 / PASSES;
    var brush = step * 1.7;
    var d = 'M0 0';
    for (var i = 1; i <= PASSES; i++) d += ' L' + (i % 2 ? 100 : 0) + ' ' + (step * i).toFixed(2);

    var id = 'sila-scrub-' + (++uid);
    var svg = document.createElementNS(SVG_NS, 'svg');
    svg.setAttribute('class', 'sila__scrub');
    svg.setAttribute('viewBox', '0 0 100 100');
    svg.setAttribute('aria-hidden', 'true');
    svg.setAttribute('focusable', 'false');

    var mask = document.createElementNS(SVG_NS, 'mask');
    mask.setAttribute('id', id);
    mask.setAttribute('maskUnits', 'userSpaceOnUse');
    mask.setAttribute('x', -brush);
    mask.setAttribute('y', -brush);
    mask.setAttribute('width', 100 + 2 * brush);
    mask.setAttribute('height', 100 + 2 * brush);

    var path = document.createElementNS(SVG_NS, 'path');
    path.setAttribute('d', d);
    path.setAttribute('fill', 'none');
    path.setAttribute('stroke', '#fff');
    path.setAttribute('stroke-width', brush.toFixed(2));
    path.setAttribute('stroke-linecap', 'round');
    path.setAttribute('stroke-linejoin', 'round');
    path.setAttribute('pathLength', '1');
    path.style.strokeDasharray = '1 2';
    path.style.strokeDashoffset = '1';
    mask.appendChild(path);

    var image = document.createElementNS(SVG_NS, 'image');
    image.setAttribute('href', href);
    image.setAttribute('width', '100');
    image.setAttribute('height', '100');
    image.setAttribute('preserveAspectRatio', 'xMidYMax meet');
    image.setAttribute('mask', 'url(#' + id + ')');

    svg.appendChild(mask);
    svg.appendChild(image);
    return { svg: svg, path: path };
  }

  /* opts: delay (ms), onRevealed */
  function scribble(el, opts) {
    opts = opts || {};
    if (!el) return;
    var img = el.querySelector('.sila__art');
    if (!img) return;
    stopScrub(el);
    var done = function () { if (opts.onRevealed) opts.onRevealed(); };
    if (reduceMotion() || !document.createElementNS || !Element.prototype.animate) { done(); return; }

    var state = el._silaScrub = {};
    /* Hidden until the marker reaches it, even while the art loads. */
    el.classList.add('sila--scrubbing');

    function start() {
      if (el._silaScrub !== state) return;
      var overlay = buildOverlay(img.currentSrc || img.src);
      state.svg = overlay.svg;
      el.appendChild(overlay.svg);
      state.anim = overlay.path.animate(
        [{ strokeDashoffset: 1 }, { strokeDashoffset: 0 }],
        { duration: SCRUB_MS, delay: opts.delay || 0, easing: 'cubic-bezier(0.42, 0, 0.58, 1)', fill: 'both' }
      );
      state.anim.onfinish = function () {
        if (el._silaScrub !== state) return;
        stopScrub(el);
        done();
      };
    }

    /* Start only once the art is decoded, so the marker never sweeps
       over an empty box. */
    if (img.complete && img.naturalWidth) start();
    else {
      var ready = function () {
        img.removeEventListener('load', ready);
        img.removeEventListener('error', ready);
        if (img.naturalWidth) start();
        else if (el._silaScrub === state) { stopScrub(el); done(); }
      };
      img.addEventListener('load', ready);
      img.addEventListener('error', ready);
      if (img.loading === 'lazy') img.loading = 'eager';
    }
  }

  /* Swap the pose; the new one is scrubbed in, as when the app's speech
     line changes. opts: scrub (default true), force (scrub even when the
     pose is unchanged), delay, onRevealed */
  function set(el, art, opts) {
    opts = opts || {};
    if (!el) return;
    art = normalise(art);
    if (el.getAttribute('data-sila') === art && !opts.force) return;
    el.setAttribute('data-sila', art);
    var img = el.querySelector('.sila__art');
    if (img) img.src = src(art);
    if (opts.scrub === false) { stopScrub(el); return; }
    scribble(el, { delay: opts.delay, onRevealed: opts.onRevealed });
  }

  var FULL_BODY = ['standing', 'charging'];
  var CHEER_MS = 2200;

  function celebrate(el, opts) {
    opts = opts || {};
    if (!el || !el.querySelector('.sila__art')) return;
    var rest = el.getAttribute('data-sila-rest') || el.getAttribute('data-sila') || 'standing';
    el.setAttribute('data-sila-rest', rest);
    var full = FULL_BODY.indexOf(rest) >= 0;
    var cheerArt = full ? (rest === 'charging' ? 'standing' : 'charging') : 'laughing';
    preload([cheerArt, rest]);

    clearTimeout(el._silaRest);
    el.classList.add('sila--celebrating');
    set(el, cheerArt, {
      force: true,
      onRevealed: function () {
        if (opts.onLand) opts.onLand();
        el._silaRest = setTimeout(function () {
          set(el, rest, {
            onRevealed: function () { el.classList.remove('sila--celebrating'); }
          });
        }, CHEER_MS);
      }
    });
  }

  /* `sila--alive` mascots scrub in the first time they come into view,
     once the page loader (js/loader.js) has lifted. */
  function autoScrub() {
    var alive = Array.prototype.slice.call(document.querySelectorAll('.sila--alive'));
    if (!alive.length || reduceMotion() || !('IntersectionObserver' in window)) return;
    alive.forEach(function (el) { el.classList.add('sila--scrubbing'); });

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        observer.unobserve(entry.target);
        scribble(entry.target, { delay: 120 });
      });
    }, { threshold: 0.35 });

    var root = document.documentElement;
    var go = function () { alive.forEach(function (el) { observer.observe(el); }); };
    if (!document.getElementById('siteLoader') || root.classList.contains('loader-done')) go();
    else {
      var started = false;
      var once = function () { if (!started) { started = true; go(); } };
      window.addEventListener('silafit:loader-done', once);
      setTimeout(once, 4500); // the loader's own CSS failsafe has gone by then
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', autoScrub);
  else autoScrub();

  window.Sila = { html: html, set: set, scribble: scribble, celebrate: celebrate, arts: ARTS.slice() };
})();
