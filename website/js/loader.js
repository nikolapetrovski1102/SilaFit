/* Full-screen loader: the SilaFit runner draws itself over the blurred
   backdrop (assets/img/branding/loader_{dark,light}.svg), then the overlay
   fades out once the page has loaded and the drawing has had time to finish.
   Shown once per browser session: the inline <head> bootstrap adds
   `no-loader` to <html> when this flag is set, so later pages never flash it. */
(function () {
  var el = document.getElementById('siteLoader');
  if (!el) return;
  var MIN_MS = 1500; // the runner finishes drawing at ~1.2s

  function hide() {
    var elapsed = window.performance ? performance.now() : MIN_MS;
    setTimeout(function () {
      el.classList.add('is-done');
      try { sessionStorage.setItem('silafit-loader-seen', '1'); } catch (e) { /* private mode */ }
      setTimeout(function () { if (el.parentNode) el.parentNode.removeChild(el); }, 600);
    }, Math.max(0, MIN_MS - elapsed));
  }

  if (document.readyState === 'complete') hide();
  else window.addEventListener('load', hide);
})();
