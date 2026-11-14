/* ============================================================
   SilaFit — smart download link (download.html, served at /download)
   Phones land on a short branded handoff: the SF mark paints itself in,
   "Opening the App Store" fills a bar, and ~1.6s later the page
   replaces itself with the store listing. iPadOS Safari (it claims to
   be a Mac) is caught too. Android does the same once PLAY_STORE_URL
   is set; until then it gets the "coming soon" state. Desktop gets
   both badges and a QR back to /download.

   Tagged links (/download?src=crooks-gym) record the open first, so the
   console's "Download links" report can credit the gym or profile with the
   visit and, once the app's first sign-in comes from the same network, the
   install, sign-up and purchase that followed.
   ============================================================ */
(function () {
  'use strict';

  var APP_STORE_URL = 'https://apps.apple.com/app/id6811345732';
  // Set to 'https://play.google.com/store/apps/details?id=com.nikolapetrovski.silafit'
  // when the Play listing is public (and uncomment the Android line in
  // deploy/nginx-sila.fitness.conf).
  var PLAY_STORE_URL = null;
  // App Store Connect > Analytics > Sources shows campaign (ct) installs once
  // this is set to the provider token from any App Store Connect campaign link.
  var APPLE_PROVIDER_TOKEN = null;

  var src = readSource();
  var SHARE_URL = 'https://sila.fitness/download' + (src ? '?src=' + encodeURIComponent(src) : '');
  if (src && APPLE_PROVIDER_TOKEN) {
    APP_STORE_URL += '?pt=' + encodeURIComponent(APPLE_PROVIDER_TOKEN) + '&ct=' + encodeURIComponent(src) + '&mt=8';
  }
  if (src && PLAY_STORE_URL) {
    PLAY_STORE_URL += '&referrer=' + encodeURIComponent('utm_source=' + src + '&utm_medium=download_link');
  }

  var ua = navigator.userAgent || '';
  var isIOS = /iPhone|iPad|iPod/i.test(ua) ||
    (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  var isAndroid = /Android/i.test(ua);

  // ?stay keeps a phone on this page (handy for checking it).
  var stay = /[?&]stay\b/.test(location.search);

  var root = document.documentElement;

  // How long the handoff stays up. The full SF mark drawing ends at ~1.32s.
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
  recordVisit(isIOS ? 'ios' : isAndroid ? 'android' : 'desktop');

  function readSource() {
    var m = /[?&]src=([^&#]*)/.exec(location.search);
    if (!m) return null;
    try { m = decodeURIComponent(m[1].replace(/\+/g, ' ')); } catch (e) { return null; }
    m = m.trim().toLowerCase();
    return /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(m) && m.length <= 40 ? m : null;
  }

  // One id per browser, so the report can tell repeat opens from new devices.
  function visitorId() {
    var key = 'silafit.download.visitor';
    try {
      var id = localStorage.getItem(key);
      if (!id && window.crypto && crypto.randomUUID) {
        id = crypto.randomUUID();
        localStorage.setItem(key, id);
      }
      return id || null;
    } catch (e) { return null; }
  }

  // Fired straight away, before the store redirect; keepalive lets it finish
  // after the page has been replaced.
  function recordVisit(platform) {
    var body = JSON.stringify({ source: src, visitorId: visitorId(), platform: platform });
    try {
      fetch('/api/download/visit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: body,
        keepalive: true,
        credentials: 'omit'
      }).catch(function () {});
    } catch (e) {
      try { navigator.sendBeacon('/api/download/visit', new Blob([body], { type: 'application/json' })); } catch (e2) { /* never block the download */ }
    }
  }

  function ready(fn) {
    if (document.readyState !== 'loading') fn();
    else document.addEventListener('DOMContentLoaded', fn);
  }

  var MK = document.documentElement.lang === 'mk';

  ready(function () {
    var handoff = document.getElementById('handoff');
    if (handoff && storeUrl) {
      handoff.querySelector('[data-handoff-store]').textContent =
        isIOS ? (MK ? 'App Store' : 'the App Store') : 'Google Play';
      handoff.querySelector('[data-handoff-link]').href = storeUrl;
    }

    var play = document.querySelector('[data-play-badge]');
    if (play && PLAY_STORE_URL) {
      play.setAttribute('href', PLAY_STORE_URL);
      play.removeAttribute('aria-disabled');
      play.classList.remove('store-badge--soon');
      var soon = play.querySelector('[data-play-soon]');
      if (soon) soon.textContent = MK ? 'Преземи од' : 'Get it on';
    }

    var note = document.querySelector('[data-download-note]');
    if (note && isAndroid && !PLAY_STORE_URL) {
      note.textContent = MK
        ? 'SilaFit за Android наскоро ќе биде на Google Play. На iPhone веќе е бесплатна.'
        : 'SilaFit for Android is on its way to Google Play. Check back soon. It’s already free on iPhone.';
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
