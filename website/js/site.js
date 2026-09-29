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
        el.textContent = Math.round(target * eased) + suffix;
        if (t < 1) requestAnimationFrame(tick);
      }
      requestAnimationFrame(tick);
    });
  }, { threshold: 0.5 });

  $$('[data-count]').forEach(function (el) { counterObserver.observe(el); });

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

  function renderPricing() {
    var grid = $('#pricingGrid');
    if (!grid || !window.SilaStore) return;

    var plans = SilaStore.plans.all();
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
          '<a class="btn btn--lg ' + (featured ? 'btn--primary' : 'btn--secondary') + '" href="#top">' +
            (p.monthlyPrice === 0 ? 'Start free' : 'Choose ' + escapeHtml(p.name.replace(' Tier', ''))) +
          '</a>' +
        '</article>'
      );
    }).join('');
  }

  $$('.billing-toggle button').forEach(function (btn) {
    btn.addEventListener('click', function () {
      $$('.billing-toggle button').forEach(function (b) { b.classList.remove('is-active'); });
      btn.classList.add('is-active');
      billing = btn.getAttribute('data-billing');
      renderPricing();
    });
  });

  /* ----------------------------------------------------------------
     Init
     ---------------------------------------------------------------- */
  renderMealStrip();
  renderPricing();

})();
