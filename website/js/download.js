/* ============================================================
   SilaFit — smart download link (download.html, served at /download)
   nginx already redirects iPhone/iPad by user agent. This covers
   what nginx can't see: iPadOS Safari (it claims to be a Mac) and
   visits straight to /download.html. Android goes to Google Play
   once PLAY_STORE_URL is set; until then it gets the "coming soon"
   state. Desktop gets both badges and a QR back to /download.
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

  if (!stay && isIOS) { location.replace(APP_STORE_URL); return; }
  if (!stay && isAndroid && PLAY_STORE_URL) { location.replace(PLAY_STORE_URL); return; }

  var root = document.documentElement;
  root.setAttribute('data-platform', isIOS ? 'ios' : isAndroid ? 'android' : 'desktop');

  function ready(fn) {
    if (document.readyState !== 'loading') fn();
    else document.addEventListener('DOMContentLoaded', fn);
  }

  ready(function () {
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
