/* ============================================================
   SilaFit — light/dark theme toggle
   The resolved theme is stamped on <html data-theme> by the inline
   bootstrap in each page's <head>, before first paint, so there is
   no flash of the wrong palette. This file only wires the toggle
   buttons and remembers an explicit choice — until the visitor
   makes one, the site keeps following prefers-color-scheme.
   ============================================================ */
(function () {
  'use strict';

  var STORAGE_KEY = 'silafit-theme';
  var root = document.documentElement;
  var media = window.matchMedia ? window.matchMedia('(prefers-color-scheme: light)') : null;
  var buttons = Array.prototype.slice.call(document.querySelectorAll('[data-theme-toggle]'));

  function currentTheme() {
    return root.getAttribute('data-theme') === 'light' ? 'light' : 'dark';
  }

  function storedTheme() {
    try {
      var value = localStorage.getItem(STORAGE_KEY);
      return (value === 'light' || value === 'dark') ? value : null;
    } catch (e) {
      return null;
    }
  }

  function nextTheme(theme) {
    return theme === 'light' ? 'dark' : 'light';
  }

  /* Buttons always advertise the mode they switch *to*. */
  function syncButtons(theme) {
    var next = nextTheme(theme);
    buttons.forEach(function (btn) {
      var title = 'Switch to ' + next + ' mode';
      btn.setAttribute('aria-label', title);
      btn.setAttribute('title', title);
      btn.setAttribute('aria-pressed', String(theme === 'light'));
      var label = btn.querySelector('[data-theme-toggle-label]');
      if (label) label.textContent = next === 'light' ? 'Light mode' : 'Dark mode';
    });
  }

  function applyTheme(theme, persist) {
    root.setAttribute('data-theme', theme);
    if (persist) {
      try { localStorage.setItem(STORAGE_KEY, theme); } catch (e) { /* private mode */ }
    }
    syncButtons(theme);
  }

  buttons.forEach(function (btn) {
    btn.addEventListener('click', function () {
      applyTheme(nextTheme(currentTheme()), true);
    });
  });

  syncButtons(currentTheme());

  /* Follow the OS as long as the visitor hasn't picked a side. */
  if (media) {
    var onSystemChange = function (event) {
      if (!storedTheme()) applyTheme(event.matches ? 'light' : 'dark', false);
    };
    if (media.addEventListener) media.addEventListener('change', onSystemChange);
    else if (media.addListener) media.addListener(onSystemChange);
  }
})();
