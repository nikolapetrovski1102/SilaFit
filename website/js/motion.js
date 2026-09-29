/* ============================================================
   SilaFit marketing site — shared motion
   Loaded on every public page. Drives the ambient background
   (scroll + pointer), the scroll progress bar, section scene
   tints, photo parallax, the marquee band, the hero word split,
   and the mobile nav burger.
   ============================================================ */
(function () {
  'use strict';

  var root = document.documentElement;
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var finePointer = window.matchMedia('(pointer: fine)').matches;

  function $$(sel, scope) { return Array.prototype.slice.call((scope || document).querySelectorAll(sel)); }

  /* ----------------------------------------------------------------
     Ambient layer + progress bar are injected so every page gets
     them without repeating markup.
     ---------------------------------------------------------------- */
  if (!document.querySelector('.ambient')) {
    var ambient = document.createElement('div');
    ambient.className = 'ambient';
    ambient.setAttribute('aria-hidden', 'true');
    ambient.innerHTML =
      '<div class="ambient__orb ambient__orb--a"></div>' +
      '<div class="ambient__orb ambient__orb--b"></div>' +
      '<div class="ambient__orb ambient__orb--c"></div>' +
      '<div class="ambient__grain"></div>';
    document.body.insertBefore(ambient, document.body.firstChild);
  }

  var nav = document.querySelector('.nav');
  if (nav && !nav.querySelector('.scroll-progress')) {
    var bar = document.createElement('div');
    bar.className = 'scroll-progress';
    bar.setAttribute('aria-hidden', 'true');
    nav.appendChild(bar);
  }

  /* ----------------------------------------------------------------
     Mobile nav burger — works off classes so the secondary pages
     (which have no ids) get it too.
     ---------------------------------------------------------------- */
  if (nav) {
    var links = nav.querySelector('.nav__links');
    var burger = nav.querySelector('.nav__burger');
    if (links && !burger) {
      burger = document.createElement('button');
      burger.className = 'nav__burger';
      burger.type = 'button';
      burger.setAttribute('aria-label', 'Menu');
      burger.setAttribute('aria-expanded', 'false');
      burger.innerHTML =
        '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 8h16M4 16h16"/></svg>';
      (nav.querySelector('.nav__cta') || nav.querySelector('.nav__inner') || nav).appendChild(burger);
    }
    if (links && burger) {
      var setOpen = function (open) {
        links.classList.toggle('is-open', open);
        burger.setAttribute('aria-expanded', String(open));
      };
      burger.addEventListener('click', function (e) {
        e.stopPropagation();
        setOpen(!links.classList.contains('is-open'));
      });
      links.addEventListener('click', function (e) {
        if (e.target.closest('a')) setOpen(false);
      });
      document.addEventListener('click', function (e) {
        if (!nav.contains(e.target)) setOpen(false);
      });
      document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape') setOpen(false);
      });
      window.addEventListener('resize', function () {
        if (window.innerWidth > 900) setOpen(false);
      });
    }
  }

  /* ----------------------------------------------------------------
     Hero headline — wrap each word so it can rise out of a mask.
     Only text nodes and <em>/<br> are expected inside the heading.
     ---------------------------------------------------------------- */
  var heroTitle = document.querySelector('[data-split]');
  if (heroTitle && !reduceMotion) {
    var index = 0;
    var wrapWords = function (node) {
      Array.prototype.slice.call(node.childNodes).forEach(function (child) {
        if (child.nodeType === 3) {
          var frag = document.createDocumentFragment();
          child.textContent.split(/(\s+)/).forEach(function (part) {
            if (!part) return;
            if (/^\s+$/.test(part)) { frag.appendChild(document.createTextNode(' ')); return; }
            var outer = document.createElement('span');
            outer.className = 'split-word';
            var inner = document.createElement('span');
            inner.style.setProperty('--i', index++);
            inner.textContent = part;
            outer.appendChild(inner);
            frag.appendChild(outer);
          });
          node.replaceChild(frag, child);
        } else if (child.nodeType === 1 && child.tagName !== 'BR') {
          wrapWords(child);
        }
      });
    };
    heroTitle.setAttribute('aria-label', heroTitle.textContent.replace(/\s+/g, ' ').trim());
    wrapWords(heroTitle);
    heroTitle.classList.add('is-splitting');
    requestAnimationFrame(function () {
      requestAnimationFrame(function () { heroTitle.classList.add('is-split'); });
    });
  }

  /* ----------------------------------------------------------------
     Scene tints — the section nearest the middle of the viewport
     sets data-scene on <html>; CSS cross-fades the orb colours.
     ---------------------------------------------------------------- */
  var scenes = $$('[data-scene]');
  if (scenes.length && 'IntersectionObserver' in window) {
    var sceneObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) root.setAttribute('data-scene', entry.target.getAttribute('data-scene'));
      });
    }, { rootMargin: '-45% 0px -45% 0px' });
    scenes.forEach(function (s) { sceneObserver.observe(s); });
  }

  /* ----------------------------------------------------------------
     Scroll + pointer loop. Everything writes CSS variables; one
     rAF per frame at most, and nothing runs while idle.
     ---------------------------------------------------------------- */
  var parallax = $$('[data-parallax]');
  var marquees = $$('.marquee');
  var mx = 0, my = 0, tx = 0, ty = 0;
  var ticking = false;
  var pointerActive = false;

  function update() {
    ticking = false;
    var vh = window.innerHeight;
    var max = Math.max(1, document.documentElement.scrollHeight - vh);
    var progress = Math.min(1, Math.max(0, window.scrollY / max));
    root.style.setProperty('--scroll', progress.toFixed(4));

    if (nav) nav.classList.toggle('scrolled', window.scrollY > 20);

    if (!reduceMotion) {
      parallax.forEach(function (el) {
        var r = el.getBoundingClientRect();
        if (r.bottom < -100 || r.top > vh + 100) return;
        // -1 when the frame enters from below, +1 as it leaves the top.
        var t = ((r.top + r.height / 2) - vh / 2) / (vh / 2 + r.height / 2);
        el.style.setProperty('--py', (t * r.height * 0.07).toFixed(1) + 'px');
      });

      marquees.forEach(function (el) {
        var r = el.getBoundingClientRect();
        if (r.bottom < 0 || r.top > vh) return;
        var track = el.firstElementChild;
        var t = (vh - r.top) / (vh + r.height); // 0 → 1 across the pass
        var travel = Math.max(0, track.scrollWidth - el.clientWidth);
        track.style.setProperty('--mq', (-t * travel).toFixed(1) + 'px');
      });

      if (pointerActive) {
        tx += (mx - tx) * 0.06;
        ty += (my - ty) * 0.06;
        root.style.setProperty('--mx', tx.toFixed(3));
        root.style.setProperty('--my', ty.toFixed(3));
        if (Math.abs(mx - tx) > 0.001 || Math.abs(my - ty) > 0.001) requestTick();
      }
    }
  }

  function requestTick() {
    if (!ticking) {
      ticking = true;
      requestAnimationFrame(update);
    }
  }

  window.addEventListener('scroll', requestTick, { passive: true });
  window.addEventListener('resize', requestTick);
  if (finePointer && !reduceMotion) {
    window.addEventListener('pointermove', function (e) {
      mx = (e.clientX / window.innerWidth) * 2 - 1;
      my = (e.clientY / window.innerHeight) * 2 - 1;
      pointerActive = true;
      requestTick();
    }, { passive: true });
  }
  update();

  /* ----------------------------------------------------------------
     Reveal on scroll
     ---------------------------------------------------------------- */
  if ('IntersectionObserver' in window) {
    var revealObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          revealObserver.unobserve(entry.target);
        }
      });
    }, { threshold: 0.08 });
    $$('.reveal').forEach(function (el) { revealObserver.observe(el); });
  }
})();
