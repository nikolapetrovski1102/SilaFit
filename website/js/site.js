/* ============================================================
   SilaFit marketing site — interactions
   Active nav link, counter animation, and the meal list + pricing
   columns rendered from SilaStore. Shared motion lives in motion.js.
   ============================================================ */
(function () {
  'use strict';

  /* ----------------------------------------------------------------
     Utilities
     ---------------------------------------------------------------- */
  function $(sel, root) { return (root || document).querySelector(sel); }
  function $$(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  var nav = $('#mainNav');

  var APP_STORE_URL = 'https://apps.apple.com/app/id6811345732';

  /* Active nav link on scroll */
  var sections = $$('section[id], div[id="top"]');
  var navAnchors = $$('.nav__links a');
  var scrollActiveObserver = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) {
        var id = entry.target.id;
        navAnchors.forEach(function (a) {
          a.classList.toggle('is-active', a.getAttribute('href') === '#' + id);
        });
      }
    });
  }, { threshold: 0.4 });
  sections.forEach(function (s) { scrollActiveObserver.observe(s); });

  /* ----------------------------------------------------------------
     Animated stat counters
     ---------------------------------------------------------------- */
  var counterObserver = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      counterObserver.unobserve(entry.target);
      var el = entry.target;
      var target = parseInt(el.getAttribute('data-count'), 10);
      var suffix = el.getAttribute('data-suffix') || '';
      var start = performance.now();
      var duration = 1400;
      function tick(now) {
        var t = Math.min((now - start) / duration, 1);
        var eased = 1 - Math.pow(1 - t, 3);
        el.textContent = Math.round(target * eased).toLocaleString('en-US') + suffix;
        if (t < 1) requestAnimationFrame(tick);
      }
      requestAnimationFrame(tick);
    });
  }, { threshold: 0.5 });

  /* Under reduced motion the markup already holds the final number. */
  if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    $$('[data-count]').forEach(function (el) { counterObserver.observe(el); });
  }

  /* ----------------------------------------------------------------
     Meal suggestions strip — from SilaStore
     ---------------------------------------------------------------- */
  function renderMealStrip() {
    var strip = $('#mealStrip');
    if (!strip || !window.SilaStore) return;

    var month = new Date().getMonth() + 1;
    var meals = SilaStore.suggestionsForMonth(month);
    if (meals.length < 4) {
      var extra = SilaStore.mealSuggestions.all().filter(function (s) { return s.month !== month; });
      meals = meals.concat(extra).slice(0, 4);
    } else {
      meals = meals.slice(0, 4);
    }

    strip.innerHTML = meals.map(function (m) {
      return (
        '<li class="meal-row">' +
          '<span class="eyebrow meal-row__type">' + escapeHtml(m.mealType) + '</span>' +
          '<div>' +
            '<div class="meal-row__title">' + escapeHtml(m.title) + '</div>' +
            '<div class="meal-row__desc">' + escapeHtml(m.description || '') + '</div>' +
          '</div>' +
          '<div class="meal-row__kcal">' + m.caloriesKcal + '<span>kcal</span></div>' +
          '<div class="meal-row__macros">' +
            '<span><b>' + m.proteinG + 'g</b> P</span>' +
            '<span><b>' + m.carbsG + 'g</b> C</span>' +
            '<span><b>' + m.fatsG + 'g</b> F</span>' +
          '</div>' +
        '</li>'
      );
    }).join('');
  }

  /* ----------------------------------------------------------------
     Pricing grid — from SilaStore
     ---------------------------------------------------------------- */
  var billing = 'monthly';
  var plans = null;

  /* Same base-URL rule as support.js: in production the site and API
     share an origin; locally the site runs on a static server (or
     file://) and the API on :5080. */
  function apiBase() {
    if (window.SILAFIT_API_BASE) return window.SILAFIT_API_BASE.replace(/\/+$/, '');
    var isFileProtocol = location.protocol === 'file:';
    var isLoopbackHttp = location.protocol === 'http:' &&
      (location.hostname === 'localhost' || location.hostname === '127.0.0.1') &&
      location.port !== '5080';
    return (isFileProtocol || isLoopbackHttp) ? 'http://localhost:5080' : '';
  }

  /* GET /api/plans returns [{ plan, features }], the same catalog the app
     sells, so the page can't drift from the in-app prices. */
  function fromCatalog(entries) {
    return entries
      .slice()
      .sort(function (a, b) { return a.plan.sortOrder - b.plan.sortOrder; })
      .map(function (e) {
        return {
          name: e.plan.name,
          tagline: e.plan.tagline,
          monthlyPrice: Number(e.plan.monthlyPrice),
          yearlyPrice: Number(e.plan.yearlyPrice),
          isFeatured: e.plan.isFeatured,
          features: e.features
            .slice()
            .sort(function (a, b) { return a.sortOrder - b.sortOrder; })
            .map(function (f) { return { text: f.featureText, highlighted: f.isHighlighted }; })
        };
      });
  }

  function loadPlans() {
    var useSeed = function () {
      if (plans) return;
      plans = window.SilaStore ? SilaStore.plans.all() : [];
      renderPricing();
    };
    if (!window.fetch) return useSeed();

    var timer = setTimeout(useSeed, 4000);
    fetch(apiBase() + '/api/plans', { headers: { Accept: 'application/json' } })
      .then(function (res) { return res.ok ? res.json() : Promise.reject(res.status); })
      .then(function (body) {
        if (!body || !body.success || !body.data || !body.data.length) return Promise.reject('empty');
        clearTimeout(timer);
        plans = fromCatalog(body.data);
        renderPricing();
      })
      .catch(function () { clearTimeout(timer); useSeed(); });
  }

  function renderPricing() {
    var grid = $('#pricingGrid');
    if (!grid || !plans) return;

    grid.innerHTML = plans.map(function (p) {
      var price = billing === 'monthly' ? p.monthlyPrice : p.yearlyPrice;
      var per = billing === 'monthly' ? '/ month' : '/ year';
      var featured = p.isFeatured;
      var features = (p.features || []).map(function (f) {
        return '<li class="' + (f.highlighted ? 'is-highlighted' : '') + '">' + escapeHtml(f.text) + '</li>';
      }).join('');

      return (
        '<article class="plan' + (featured ? ' plan--featured' : '') + '">' +
          '<div class="plan__head">' +
            '<h3 class="plan__name">' + escapeHtml(p.name.replace(' Tier', '')) + '</h3>' +
            (featured ? '<span class="plan__badge">Most popular</span>' : '') +
          '</div>' +
          '<div class="plan__price">' +
            '<span class="t-stat">€' + price.toFixed(2) + '</span>' +
            '<span class="per">' + per + '</span>' +
          '</div>' +
          '<p class="plan__tagline">' + escapeHtml(p.tagline || '') + '</p>' +
          '<ul>' + features + '</ul>' +
          '<a class="btn btn--lg ' + (featured ? 'btn--primary' : 'btn--secondary') + '" href="' + APP_STORE_URL + '">' +
            (p.monthlyPrice === 0 ? 'Start free' : 'Get ' + escapeHtml(p.name.replace(' Tier', '')) + ' in the app') +
          '</a>' +
        '</article>'
      );
    }).join('');
  }

  /* The pill slides under the active option; prices swap with a
     short roll so the change reads as the same plan, new period. */
  function placeBillingPill() {
    var pill = $('.billing-toggle__pill');
    var active = $('.billing-toggle button.is-active');
    if (!pill || !active) return;
    pill.parentNode.classList.add('has-pill');
    pill.style.width = active.offsetWidth + 'px';
    pill.style.transform = 'translateX(' + active.offsetLeft + 'px)';
  }

  $$('.billing-toggle button').forEach(function (btn) {
    btn.addEventListener('click', function () {
      if (btn.classList.contains('is-active')) return;
      $$('.billing-toggle button').forEach(function (b) { b.classList.remove('is-active'); });
      btn.classList.add('is-active');
      billing = btn.getAttribute('data-billing');
      placeBillingPill();
      var grid = $('#pricingGrid');
      if (grid) grid.classList.add('is-swapping');
      setTimeout(function () {
        renderPricing();
        if (grid) {
          grid.classList.remove('is-swapping');
          grid.classList.add('is-swapped');
          setTimeout(function () { grid.classList.remove('is-swapped'); }, 420);
        }
      }, 160);
    });
  });
  window.addEventListener('resize', placeBillingPill);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(placeBillingPill);

  /* ----------------------------------------------------------------
     PR chart — a sample 12-week deadlift block ending on a new PR.
     Drawn as SVG so it stays sharp at any width; CSS draws
     the line in once the figure scrolls into view.
     ---------------------------------------------------------------- */
  function renderPrChart() {
    var host = $('[data-pr-chart] .pr-chart__plot');
    if (!host) return;

    var logged = [150, 152, 151, 155, 158, 157, 161, 164, 166, 169, 170, 173];
    /* Drawn at the host's real pixel width so strokes and labels keep
       their size on phones; phones also get a taller plot. */
    var W = Math.max(280, Math.round(host.clientWidth || 1000));
    var H = Math.round(Math.min(400, Math.max(260, W * (W < 600 ? 0.75 : 0.36))));
    var padL = 8, padR = 56, padT = 84, padB = 28;
    var weeks = logged.length;
    var min = 145, max = 180;
    function x(i) { return padL + (i / (weeks - 1)) * (W - padL - padR); }
    function y(v) { return padT + (1 - (v - min) / (max - min)) * (H - padT - padB); }

    /* Catmull-Rom → cubic Bézier so the line reads as a smoothed trend. */
    function smooth(pts) {
      var d = 'M' + pts[0][0].toFixed(1) + ' ' + pts[0][1].toFixed(1);
      for (var i = 0; i < pts.length - 1; i++) {
        var p0 = pts[i - 1] || pts[i], p1 = pts[i], p2 = pts[i + 1], p3 = pts[i + 2] || p2;
        var c1x = p1[0] + (p2[0] - p0[0]) / 6, c1y = p1[1] + (p2[1] - p0[1]) / 6;
        var c2x = p2[0] - (p3[0] - p1[0]) / 6, c2y = p2[1] - (p3[1] - p1[1]) / 6;
        d += ' C' + c1x.toFixed(1) + ' ' + c1y.toFixed(1) + ' ' + c2x.toFixed(1) + ' ' + c2y.toFixed(1) +
             ' ' + p2[0].toFixed(1) + ' ' + p2[1].toFixed(1);
      }
      return d;
    }

    var lp = logged.map(function (v, i) { return [x(i), y(v)]; });
    var line = smooth(lp);
    var area = line + ' L' + lp[lp.length - 1][0].toFixed(1) + ' ' + (H - padB) + ' L' + lp[0][0].toFixed(1) + ' ' + (H - padB) + ' Z';
    var target = lp[lp.length - 1];

    var grid = [150, 160, 170].map(function (v) {
      return '<line class="pr-grid" x1="0" x2="' + W + '" y1="' + y(v).toFixed(1) + '" y2="' + y(v).toFixed(1) + '"/>' +
             '<text class="pr-axis" x="' + W + '" y="' + (y(v) - 8).toFixed(1) + '" text-anchor="end">' + v + '</text>';
    }).join('');

    var dots = lp.slice(0, -1).map(function (p, i) {
      return '<circle class="pr-dot" cx="' + p[0].toFixed(1) + '" cy="' + p[1].toFixed(1) + '" r="5" style="--d:' + i + '"/>';
    }).join('');

    host.innerHTML =
      '<svg viewBox="0 0 ' + W + ' ' + H + '" role="img" aria-label="Deadlift estimated one-rep max rising from 150 to 173 kilograms over 12 weeks, ending on a new personal record">' +
        '<defs><linearGradient id="prFill" x1="0" y1="0" x2="0" y2="1">' +
          '<stop offset="0" stop-color="currentColor" stop-opacity="0.28"/><stop offset="1" stop-color="currentColor" stop-opacity="0"/>' +
        '</linearGradient></defs>' +
        grid +
        '<path class="pr-area" d="' + area + '" fill="url(#prFill)"/>' +
        '<path class="pr-line" d="' + line + '" pathLength="1"/>' +
        dots +
        '<circle class="pr-target-pulse" cx="' + target[0].toFixed(1) + '" cy="' + target[1].toFixed(1) + '" r="10"/>' +
        '<circle class="pr-target" cx="' + target[0].toFixed(1) + '" cy="' + target[1].toFixed(1) + '" r="8"/>' +
      '</svg>' +
      '<div class="pr-badge" style="left:' + (target[0] / W * 100).toFixed(2) + '%;top:' + (target[1] / H * 100).toFixed(2) + '%">' +
        '<b>173 kg</b><span>New PR · +3 kg</span>' +
      '</div>';
    host.setAttribute('data-w', W);
  }

  var prResizeTimer = null;
  window.addEventListener('resize', function () {
    clearTimeout(prResizeTimer);
    prResizeTimer = setTimeout(function () {
      var host = $('[data-pr-chart] .pr-chart__plot');
      if (host && Math.abs(host.clientWidth - Number(host.getAttribute('data-w'))) > 24) renderPrChart();
    }, 200);
  });

  /* ----------------------------------------------------------------
     App Store QR — desktop visitors can't tap the badge through to
     their phone, so give them a code to scan instead.
     ---------------------------------------------------------------- */
  function renderStoreQr() {
    var box = $('#storeQr');
    if (!box || !window.qrcode) return;
    var isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent) ||
      window.matchMedia('(pointer: coarse)').matches;
    if (isMobile) return;
    try {
      var qr = window.qrcode(0, 'M');
      qr.addData(APP_STORE_URL);
      qr.make();
      $('.store-qr__code', box).innerHTML = qr.createSvgTag({ cellSize: 4, margin: 2, scalable: true });
      box.hidden = false;
    } catch (e) { /* the badge alone still works */ }
  }

  /* ----------------------------------------------------------------
     Init
     ---------------------------------------------------------------- */
  renderMealStrip();
  loadPlans();
  renderStoreQr();
  renderPrChart();
  placeBillingPill();

})();
