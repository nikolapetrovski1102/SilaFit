/* ============================================================
   SilaFit marketing site — interactions v2
   Premium interactions: nav scroll effect, reveal observer,
   counter animation, step carousel, trust ticker, meal strip.
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

  /* ----------------------------------------------------------------
     Nav — scroll effect + mobile burger
     ---------------------------------------------------------------- */
  var nav = $('#mainNav');
  if (nav) {
    window.addEventListener('scroll', function () {
      nav.classList.toggle('scrolled', window.scrollY > 20);
    }, { passive: true });
  }

  var burger = $('#navBurger');
  var links = $('#navLinks');
  if (burger && links) {
    burger.addEventListener('click', function () {
      var open = links.classList.toggle('is-open');
      burger.setAttribute('aria-expanded', String(open));
    });
    links.addEventListener('click', function (e) {
      if (e.target.tagName === 'A') links.classList.remove('is-open');
    });
    document.addEventListener('click', function (e) {
      if (!nav.contains(e.target)) links.classList.remove('is-open');
    });
  }

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
     Reveal animations — IntersectionObserver
     ---------------------------------------------------------------- */
  var revealClasses = ['.reveal', '.reveal-left', '.reveal-right'];
  var allReveal = $$(revealClasses.join(','));

  var revealObserver = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        revealObserver.unobserve(entry.target);
      }
    });
  }, { threshold: 0.08 });

  allReveal.forEach(function (el) { revealObserver.observe(el); });

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
     Trust bar — duplicate items for seamless loop
     ---------------------------------------------------------------- */
  var TRUST_ITEMS = [
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6.5 6.5v11m11-11v11M3 9v6m18-6v6M6.5 12h11"/></svg>', label: '48k workouts logged' },
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 17l6-6 4 4 8-8"/></svg>', label: 'Predictive PR curves' },
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="m12 2 2.4 7.2H22l-6 4.6 2.3 7.2-6.3-4.5-6.3 4.5L8 13.8 2 9.2h7.6L12 2Z"/></svg>', label: 'AI monthly reports' },
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 3c3.5 4.5 6 7.7 6 11a6 6 0 1 1-12 0c0-3.3 2.5-6.5 6-11Z"/></svg>', label: '97% streak survival rate' },
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 3v7a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V3M4 3h16M12 12v9"/></svg>', label: 'USDA-verified nutrition' },
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/></svg>', label: 'Real-time session tracking' },
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 3c3.5 4.5 6 7.7 6 11a6 6 0 1 1-12 0c0-3.3 2.5-6.5 6-11Z"/></svg>', label: 'Hydration monitoring' },
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="9" cy="8" r="3.5"/><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6"/></svg>', label: '12k+ active athletes' },
  ];

  var trustTrack = $('#trustTrack');
  if (trustTrack) {
    var html = TRUST_ITEMS.concat(TRUST_ITEMS).map(function (item) {
      return '<div class="trust-item">' + item.icon + '<span>' + item.label + '</span></div>';
    }).join('');
    trustTrack.innerHTML = html;
  }

  /* ----------------------------------------------------------------
     How it works — step carousel with auto-advance
     ---------------------------------------------------------------- */
  var steps = $$('.step[data-step]');
  var slides = $$('.screen-slide');
  var currentStep = 0;
  var stepTimer = null;
  var STEP_DURATION = 4000;

  function activateStep(idx) {
    steps.forEach(function (s, i) {
      var active = i === idx;
      s.classList.toggle('is-active', active);
      /* Reset + trigger progress bar */
      var bar = s.querySelector('.step__progress');
      if (bar) {
        bar.style.transition = 'none';
        bar.style.width = '0';
        if (active) {
          requestAnimationFrame(function () {
            requestAnimationFrame(function () {
              bar.style.transition = 'width ' + (STEP_DURATION / 1000) + 's linear';
              bar.style.width = '100%';
            });
          });
        }
      }
    });
    slides.forEach(function (sl, i) {
      sl.classList.toggle('is-active', i === idx);
    });
    currentStep = idx;
  }

  function nextStep() {
    activateStep((currentStep + 1) % steps.length);
  }

  function startStepTimer() {
    clearInterval(stepTimer);
    stepTimer = setInterval(nextStep, STEP_DURATION);
  }

  if (steps.length && slides.length) {
    steps.forEach(function (s) {
      s.addEventListener('click', function () {
        clearInterval(stepTimer);
        activateStep(parseInt(s.getAttribute('data-step'), 10));
        startStepTimer();
      });
    });
    activateStep(0);
    startStepTimer();
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
        '<article class="meal-card reveal is-visible">' +
          '<div class="meal-card__top">' +
            '<span class="chip">' + escapeHtml(m.mealType) + '</span>' +
            '<span class="label-sm num accent-text">' + m.caloriesKcal + ' kcal</span>' +
          '</div>' +
          '<div class="meal-card__title">' + escapeHtml(m.title) + '</div>' +
          '<div class="meal-card__desc">' + escapeHtml(m.description || '') + '</div>' +
          '<div class="meal-card__macros">' +
            '<div class="meal-card__macro"><b>' + m.proteinG + 'g</b><span>protein</span></div>' +
            '<div class="meal-card__macro"><b>' + m.carbsG + 'g</b><span>carbs</span></div>' +
            '<div class="meal-card__macro"><b>' + m.fatsG + 'g</b><span>fats</span></div>' +
          '</div>' +
        '</article>'
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
        return (
          '<li class="' + (f.highlighted ? 'is-highlighted' : '') + '">' +
            '<span class="tick">' +
              '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3"><path d="m4 12 5 5L20 6"/></svg>' +
            '</span>' +
            escapeHtml(f.text) +
          '</li>'
        );
      }).join('');

      return (
        '<article class="price-card ' + (featured ? 'price-card--featured' : '') + ' reveal is-visible">' +
          (featured ? '<span class="chip chip--gold price-card__badge">Most popular</span>' : '') +
          '<span class="eyebrow ' + (featured ? 'gold-text' : 'eyebrow--accent') + '">' + escapeHtml(p.code) + '</span>' +
          '<h3 class="headline-md" style="margin-top:8px;">' + escapeHtml(p.name) + '</h3>' +
          '<div class="price-card__price">' +
            '<span class="amount">€' + price.toFixed(2) + '</span>' +
            '<span class="per">' + per + '</span>' +
          '</div>' +
          '<p class="price-card__tagline">' + escapeHtml(p.tagline || '') + '</p>' +
          '<ul>' + features + '</ul>' +
          '<a class="btn ' + (featured ? 'btn--primary' : 'btn--secondary') + '" style="width:100%;justify-content:center;" href="#top">' +
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
