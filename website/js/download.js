/* ============================================================
   SilaFit — smart download link (download.html, served at /download)
   Phones land on a short branded handoff: the runner draws itself in,
   "Opening the App Store" fills a bar, and ~1.6s later the page
   replaces itself with the store listing. iPadOS Safari (it claims to
   be a Mac) is caught too. Android does the same once PLAY_STORE_URL
   is set; until then it gets the "coming soon" state. Desktop gets
   both badges and a QR back to /download.
   ============================================================ */
(function () {
  'use strict';

  var APP_STORE_URL = 'https://apps.apple.com/app/id6811345732';
  // Set to 'https://play.google.com/store/apps/details?id=com.nikolapetrovski.silafit'
  // when the Play listing is public (and uncomment the Android line in
  // deploy/nginx-sila.fitness.conf).
  var PLAY_STORE_URL = null;
  var SHARE_URL = 'https://sila.fitness/download';

  var ua = navigator.userAgent || '';
  var isIOS = /iPhone|iPad|iPod/i.test(ua) ||
    (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  var isAndroid = /Android/i.test(ua);

  // ?stay keeps a phone on this page (handy for checking it).
  var stay = /[?&]stay\b/.test(location.search);

  var root = document.documentElement;

  // How long the handoff stays up. The full runner drawing ends at ~1.22s.
  var HANDOFF_MS = 1600;
  var storeUrl = stay ? null : isIOS ? APP_STORE_URL : (isAndroid && PLAY_STORE_URL) || null;

  if (storeUrl) {
    // Set before first paint so CSS shows the handoff, never the page under it.
    root.setAttribute('data-handoff', isIOS ? 'ios' : 'android');
    root.style.setProperty('--handoff-ms', HANDOFF_MS + 'ms');
    var go = function () { location.replace(storeUrl); };
    var timer = setTimeout(go, HANDOFF_MS);

    // Back from the store (bfcache): show the normal page, don't bounce again.
    window.addEventListener('pageshow', function (e) {
      if (e.persisted) { clearTimeout(timer); root.removeAttribute('data-handoff'); }
    });
    // Stuck in an in-app browser that blocked the redirect: after a few
    // seconds, fall back to the page with the badges.
    setTimeout(function () { root.removeAttribute('data-handoff'); }, HANDOFF_MS + 3500);
  }
  root.setAttribute('data-platform', isIOS ? 'ios' : isAndroid ? 'android' : 'desktop');

  function ready(fn) {
    if (document.readyState !== 'loading') fn();
    else document.addEventListener('DOMContentLoaded', fn);
  }

  ready(function () {
    var handoff = document.getElementById('handoff');
    if (handoff && storeUrl) {
      handoff.querySelector('[data-handoff-store]').textContent =
        isIOS ? 'the App Store' : 'Google Play';
      handoff.querySelector('[data-handoff-link]').href = storeUrl;
    }

    var play = document.querySelector('[data-play-badge]');
    if (play && PLAY_STORE_URL) {
      play.setAttribute('href', PLAY_STORE_URL);
      play.removeAttribute('aria-disabled');
      play.classList.remove('store-badge--soon');
      var soon = play.querySelector('[data-play-soon]');
      if (soon) soon.textContent = 'Get it on';
    }

    var note = document.querySelector('[data-download-note]');
    if (note && isAndroid && !PLAY_STORE_URL) {
      note.textContent = 'SilaFit for Android is on its way to Google Play. Check back soon. It’s already free on iPhone.';
    }

    var box = document.getElementById('downloadQr');
    var isPhone = isIOS || isAndroid || window.matchMedia('(pointer: coarse)').matches;
    if (!box || isPhone || !window.qrcode) return;
    try {
      var qr = window.qrcode(0, 'M');
      qr.addData(SHARE_URL);
      qr.make();
      box.querySelector('.store-qr__code').innerHTML =
        qr.createSvgTag({ cellSize: 4, margin: 2, scalable: true });
      box.hidden = false;
    } catch (e) { /* the badges alone still work */ }
  });
})();
