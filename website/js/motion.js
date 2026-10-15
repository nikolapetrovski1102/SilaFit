/* ============================================================
   SilaFit marketing site — shared motion
   Loaded on every public page. Drives the ambient background
   (scroll + pointer), the scroll progress bar, section scene
   tints, photo parallax, the marquee band, headline word splits,
   the mobile nav burger, and the playful extras (confetti, the
   screenshot coverflow, tilt, magnetic buttons, feature previews).
   Everything after the reveal block is skipped under reduced motion.
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
     Headlines — wrap each word so it can rise out of a mask. The hero
     plays on load; section headings play when they scroll in.
     Only text nodes and <em>/<br> are expected inside a heading.
     ---------------------------------------------------------------- */
  function splitWords(heading) {
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
            outer.setAttribute('aria-hidden', 'true');
            var inner = document.createElement('span');
            inner.style.setProperty('--i', index++);
            inner.textContent = part;
            outer.appendChild(inner);
            frag.appendChild(outer);
          });
          node.replaceChild(frag, child);
        } else if (child.nodeType === 1 && child.tagName !== 'BR' && !child.hasAttribute('data-nosplit')) {
          wrapWords(child);
        }
      });
    };
    var label = heading.cloneNode(true);
    $$('[data-nosplit]', label).forEach(function (n) { n.remove(); });
    heading.setAttribute('aria-label', label.textContent.replace(/\s+/g, ' ').trim());
    wrapWords(heading);
    heading.classList.remove('reveal');
    heading.classList.add('is-splitting');
  }

  var heroTitle = document.querySelector('[data-split]');
  if (heroTitle && !reduceMotion) {
    splitWords(heroTitle);
    requestAnimationFrame(function () {
      requestAnimationFrame(function () { heroTitle.classList.add('is-split'); });
    });
  }

  if (!reduceMotion && 'IntersectionObserver' in window) {
    var headingObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-split');
        headingObserver.unobserve(entry.target);
      });
    }, { threshold: 0.2, rootMargin: '0px 0px -8% 0px' });
    $$('.section h2.t-xl, .closing h2').forEach(function (h) {
      if (h.hasAttribute('data-split')) return;
      splitWords(h);
      headingObserver.observe(h);
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
  var lastY = window.scrollY;
  var velocity = 0;
  var skew = 0;

  function update() {
    ticking = false;
    var vh = window.innerHeight;
    var max = Math.max(1, document.documentElement.scrollHeight - vh);
    var progress = Math.min(1, Math.max(0, window.scrollY / max));
    root.style.setProperty('--scroll', progress.toFixed(4));

    var y = window.scrollY;
    if (nav) {
      nav.classList.toggle('scrolled', y > 20);
      /* Tuck the bar away while reading down, bring it back on any
         scroll up. The open mobile menu keeps it pinned. */
      var menuOpen = nav.querySelector('.nav__links.is-open');
      if (!menuOpen && Math.abs(y - lastY) > 4) nav.classList.toggle('is-tucked', y > lastY && y > 400);
    }
    velocity = y - lastY;
    lastY = y;

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

      /* The marquee leans into fast scrolling, then settles. */
      var targetSkew = Math.max(-10, Math.min(10, velocity * -0.25));
      skew += (targetSkew - skew) * 0.18;
      if (Math.abs(skew) < 0.02) skew = 0;
      marquees.forEach(function (el) { el.style.setProperty('--skew', skew.toFixed(2) + 'deg'); });
      if (skew !== 0) requestTick();

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

  if (reduceMotion) return;

  /* ----------------------------------------------------------------
     Confetti — one shared canvas, created on first use. Small,
     brand-coloured, and gone in under two seconds.
     ---------------------------------------------------------------- */
  var confettiCanvas = null, confettiCtx = null, confettiBits = [], confettiRunning = false;
  function confettiColors() {
    var cs = getComputedStyle(root);
    return ['--accent', '--macro-carbs', '--macro-fats', '--high-emphasis'].map(function (v) {
      return cs.getPropertyValue(v).trim() || '#defb92';
    });
  }
  function burst(x, y, count) {
    if (!confettiCanvas) {
      confettiCanvas = document.createElement('canvas');
      confettiCanvas.className = 'confetti';
      confettiCanvas.setAttribute('aria-hidden', 'true');
      document.body.appendChild(confettiCanvas);
      confettiCtx = confettiCanvas.getContext('2d');
    }
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    confettiCanvas.width = window.innerWidth * dpr;
    confettiCanvas.height = window.innerHeight * dpr;
    confettiCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
    var colors = confettiColors();
    for (var i = 0; i < (count || 70); i++) {
      var a = Math.random() * Math.PI * 2;
      var speed = 4 + Math.random() * 9;
      confettiBits.push({
        x: x, y: y,
        vx: Math.cos(a) * speed, vy: Math.sin(a) * speed - 6,
        w: 6 + Math.random() * 6, h: 4 + Math.random() * 4,
        r: Math.random() * Math.PI, vr: (Math.random() - 0.5) * 0.4,
        c: colors[i % colors.length], life: 0, max: 70 + Math.random() * 40,
        round: Math.random() < 0.3
      });
    }
    if (!confettiRunning) { confettiRunning = true; requestAnimationFrame(stepConfetti); }
  }
  function stepConfetti() {
    var ctx = confettiCtx;
    ctx.clearRect(0, 0, window.innerWidth, window.innerHeight);
    confettiBits = confettiBits.filter(function (b) { return b.life < b.max; });
    confettiBits.forEach(function (b) {
      b.life++;
      b.vy += 0.32; b.vx *= 0.985; b.vy *= 0.985;
      b.x += b.vx; b.y += b.vy; b.r += b.vr;
      ctx.save();
      ctx.globalAlpha = Math.max(0, 1 - b.life / b.max);
      ctx.translate(b.x, b.y);
      ctx.rotate(b.r);
      ctx.fillStyle = b.c;
      if (b.round) { ctx.beginPath(); ctx.arc(0, 0, b.h / 1.6, 0, Math.PI * 2); ctx.fill(); }
      else ctx.fillRect(-b.w / 2, -b.h / 2, b.w, b.h * Math.abs(Math.cos(b.r * 2)) + 1);
      ctx.restore();
    });
    if (confettiBits.length) requestAnimationFrame(stepConfetti);
    else { confettiRunning = false; ctx.clearRect(0, 0, window.innerWidth, window.innerHeight); }
  }
  function burstFrom(el, count) {
    var r = el.getBoundingClientRect();
    burst(r.left + r.width / 2, r.top + r.height / 2, count);
  }

  /* Mascots hop when poked; the closing one celebrates on arrival. */
  $$('.mascot, .closing__mascot').forEach(function (m) {
    m.style.cursor = 'pointer';
    m.addEventListener('click', function () {
      m.classList.remove('is-hopping');
      void m.offsetWidth;
      m.classList.add('is-hopping');
      burstFrom(m, 50);
    });
    m.addEventListener('animationend', function (e) {
      if (e.animationName === 'mascot-hop') m.classList.remove('is-hopping');
    });
  });

  var closing = document.querySelector('[data-closing]');
  if (closing && 'IntersectionObserver' in window) {
    var closingObserver = new IntersectionObserver(function (entries) {
      if (!entries[0].isIntersecting) return;
      closingObserver.disconnect();
      var mascot = closing.querySelector('.closing__mascot');
      setTimeout(function () {
        if (mascot) { mascot.classList.add('is-hopping'); burstFrom(mascot, 90); }
      }, 700);
    }, { threshold: 0.6 });
    closingObserver.observe(closing);
  }

  /* PR chart: once the line has drawn in, the new PR pops. */
  var prChart = document.querySelector('[data-pr-chart]');
  if (prChart && 'IntersectionObserver' in window) {
    var prObserver = new IntersectionObserver(function (entries) {
      if (!entries[0].isIntersecting) return;
      prObserver.disconnect();
      prChart.classList.add('is-drawn');
      setTimeout(function () {
        var t = prChart.querySelector('.pr-target');
        if (t) burstFrom(t, 40);
      }, 2000);
    }, { threshold: 0.45 });
    prObserver.observe(prChart);
  }

  /* Hero rest timer counts down while it's on screen. */
  var restTime = document.querySelector('.rest-time');
  if (restTime) {
    var restLeft = 90, restTimer = null;
    var tickRest = function () {
      restLeft = restLeft <= 0 ? 90 : restLeft - 1;
      restTime.textContent = Math.floor(restLeft / 60) + ':' + ('0' + (restLeft % 60)).slice(-2);
    };
    new IntersectionObserver(function (entries) {
      if (entries[0].isIntersecting) { if (!restTimer) restTimer = setInterval(tickRest, 1000); }
      else { clearInterval(restTimer); restTimer = null; }
    }).observe(restTime);
  }

  /* ----------------------------------------------------------------
     Screenshot rail — cards turn toward the centre like a coverflow,
     arrow buttons page through it, and mice can drag it.
     ---------------------------------------------------------------- */
  var rail = document.querySelector('.screens');
  if (rail) {
    var cards = $$('.screen', rail);
    var railTicking = false;
    var paintRail = function () {
      railTicking = false;
      var vw = window.innerWidth;
      cards.forEach(function (card) {
        var r = card.getBoundingClientRect();
        var t = ((r.left + r.width / 2) - vw / 2) / (vw / 2);
        t = Math.max(-1.2, Math.min(1.2, t));
        card.style.setProperty('--ct', t.toFixed(3));
        card.style.setProperty('--cs', (1 - Math.min(1, Math.abs(t)) * 0.07).toFixed(3));
      });
    };
    var queueRail = function () { if (!railTicking) { railTicking = true; requestAnimationFrame(paintRail); } };
    rail.addEventListener('scroll', queueRail, { passive: true });
    window.addEventListener('resize', queueRail);
    paintRail();

    var step = function (dir) {
      var w = cards[0] ? cards[0].getBoundingClientRect().width + 24 : 300;
      rail.scrollBy({ left: dir * w * (window.innerWidth > 900 ? 2 : 1), behavior: 'smooth' });
    };
    var prev = document.querySelector('[data-rail-prev]');
    var next = document.querySelector('[data-rail-next]');
    if (prev) prev.addEventListener('click', function () { step(-1); });
    if (next) next.addEventListener('click', function () { step(1); });
    var syncButtons = function () {
      if (prev) prev.disabled = rail.scrollLeft < 4;
      if (next) next.disabled = rail.scrollLeft > rail.scrollWidth - rail.clientWidth - 4;
    };
    rail.addEventListener('scroll', syncButtons, { passive: true });
    syncButtons();

    if (finePointer) {
      var dragging = false, moved = false, startX = 0, startLeft = 0;
      rail.addEventListener('pointerdown', function (e) {
        if (e.pointerType !== 'mouse' || e.button !== 0) return;
        dragging = true; moved = false;
        startX = e.clientX; startLeft = rail.scrollLeft;
      });
      window.addEventListener('pointermove', function (e) {
        if (!dragging) return;
        var dx = e.clientX - startX;
        if (!moved && Math.abs(dx) > 5) { moved = true; rail.classList.add('is-dragging'); }
        if (moved) rail.scrollLeft = startLeft - dx;
      });
      window.addEventListener('pointerup', function () {
        if (!dragging) return;
        dragging = false;
        rail.classList.remove('is-dragging');
      });
      rail.addEventListener('dragstart', function (e) { e.preventDefault(); });
    }
  }

  if (!finePointer) return;

  /* ----------------------------------------------------------------
     Fine pointers only from here: spotlight, tilt, magnetic buttons
     and the feature preview that follows the cursor.
     ---------------------------------------------------------------- */
  document.addEventListener('pointermove', function (e) {
    var card = e.target.closest && e.target.closest('[data-spot], .quote, .plan, .media--side, .index-row, .pr-chart');
    if (!card) return;
    var r = card.getBoundingClientRect();
    card.style.setProperty('--sx', (e.clientX - r.left) + 'px');
    card.style.setProperty('--sy', (e.clientY - r.top) + 'px');
  }, { passive: true });

  function tilt(el, strength) {
    el.addEventListener('pointermove', function (e) {
      var r = el.getBoundingClientRect();
      var px = (e.clientX - r.left) / r.width - 0.5;
      var py = (e.clientY - r.top) / r.height - 0.5;
      el.style.setProperty('--rx', (-py * strength).toFixed(2) + 'deg');
      el.style.setProperty('--ry', (px * strength).toFixed(2) + 'deg');
      el.classList.add('is-tilting');
    });
    el.addEventListener('pointerleave', function () {
      el.style.setProperty('--rx', '0deg');
      el.style.setProperty('--ry', '0deg');
      el.classList.remove('is-tilting');
    });
  }
  $$('.quote, .media--side').forEach(function (el) { tilt(el, 6); });
  $$('.screen').forEach(function (el) { tilt(el, 10); });

  $$('.btn, .store-badge, .rail-nav__btn').forEach(function (btn) {
    btn.classList.add('is-magnetic');
    btn.addEventListener('pointermove', function (e) {
      var r = btn.getBoundingClientRect();
      var dx = e.clientX - (r.left + r.width / 2);
      var dy = e.clientY - (r.top + r.height / 2);
      btn.style.setProperty('--magx', (dx * 0.22).toFixed(1) + 'px');
      btn.style.setProperty('--magy', (dy * 0.3).toFixed(1) + 'px');
    });
    btn.addEventListener('pointerleave', function () {
      btn.style.setProperty('--magx', '0px');
      btn.style.setProperty('--magy', '0px');
    });
  });

  var rows = $$('.index-row[data-preview]');
  if (rows.length) {
    var follower = document.createElement('div');
    follower.className = 'preview-follow';
    follower.setAttribute('aria-hidden', 'true');
    follower.innerHTML = '<img alt="" />';
    document.body.appendChild(follower);
    var fimg = follower.firstChild;
    var fx = 0, fy = 0, cx = 0, cy = 0, fRunning = false, fVisible = false;
    var moveFollower = function () {
      var dx = fx - cx;
      cx += dx * 0.16;
      cy += (fy - cy) * 0.16;
      var rot = Math.max(-12, Math.min(12, dx * 0.08));
      follower.style.transform = 'translate3d(' + cx.toFixed(1) + 'px,' + cy.toFixed(1) + 'px,0) rotate(' + rot.toFixed(2) + 'deg)';
      if (fVisible || Math.abs(dx) > 0.5) requestAnimationFrame(moveFollower);
      else fRunning = false;
    };
    rows.forEach(function (row) {
      row.addEventListener('pointerenter', function (e) {
        if (window.innerWidth <= 900) return;
        var src = row.getAttribute('data-preview');
        if (fimg.getAttribute('src') !== src) fimg.setAttribute('src', src);
        if (!fVisible) { cx = fx = e.clientX; cy = fy = e.clientY; }
        fVisible = true;
        follower.classList.add('is-visible');
        if (!fRunning) { fRunning = true; requestAnimationFrame(moveFollower); }
      });
      row.addEventListener('pointermove', function (e) { fx = e.clientX; fy = e.clientY; });
      row.addEventListener('pointerleave', function () {
        fVisible = false;
        follower.classList.remove('is-visible');
      });
    });
    window.addEventListener('scroll', function () {
      if (fVisible && !document.querySelector('.index-row[data-preview]:hover')) {
        fVisible = false;
        follower.classList.remove('is-visible');
      }
    }, { passive: true });
  }
})();
