/* Full-screen loader: the SilaFit runner draws itself over the blurred
   backdrop, then the overlay eases away once the page has loaded and the
   drawing has finished.

   - Every page load shows it. The first one in a browser session plays the
     full drawing (~1.2s, loader_{dark,light}.svg); after that the inline
     <head> bootstrap adds `loader-fast` to <html> and the inline script next
     to #siteLoader picks loader_*_fast.svg, the same drawing in ~0.65s.
   - Clicking through to another page of the site fades the backdrop back in
     before leaving, so one page hands over to the next without a white flash.
   - CSS fades it out by itself after a few seconds even if this script never
     runs, so it can never trap the page. */
(function () {
  var el = document.getElementById('siteLoader');
  if (!el) return;

  var root = document.documentElement;
  var fast = root.classList.contains('loader-fast');
  var MIN_MS = fast ? 700 : 1350; // the drawing finishes at ~0.67s / ~1.22s
  var reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var shown = false;

  function reveal() {
    // Hand control from the CSS failsafe animation to the classes, or its
    // `forwards` fill would keep overriding them.
    el.style.animation = 'none';
    el.classList.remove('is-covering');
    el.classList.add('is-done');
    // Lets js/motion.js start the page title drawing once it's visible.
    if (!root.classList.contains('loader-done')) {
      root.classList.add('loader-done');
      window.dispatchEvent(new Event('silafit:loader-done'));
    }
  }

  function hide() {
    if (shown) return;
    shown = true;
    try { sessionStorage.setItem('silafit-loader-seen', '1'); } catch (e) { /* private mode */ }
    var elapsed = window.performance ? performance.now() : MIN_MS;
    setTimeout(function () {
      // One frame so the transition starts from the drawn state.
      requestAnimationFrame(reveal);
    }, Math.max(0, MIN_MS - elapsed));
  }

  if (document.readyState === 'complete') hide();
  else window.addEventListener('load', hide);

  // Coming back through the back/forward cache restores the page as it was
  // left, which can be mid-cover: uncover it.
  window.addEventListener('pageshow', function (e) {
    if (e.persisted) reveal();
  });

  if (reduceMotion) return;

  /* Page-to-page hand-off: cover, then navigate. Only plain left clicks on
     links to other pages of this site; anything opening elsewhere (new tab,
     download, the /download redirect, app-store links, admin) goes straight. */
  function isSitePage(a) {
    if (!a.href || a.target && a.target !== '_self') return false;
    if (a.hasAttribute('download') || a.hasAttribute('data-app-link')) return false;
    var url;
    try { url = new URL(a.href, location.href); } catch (e) { return false; }
    if (url.origin !== location.origin) return false;
    if (/^\/(download|admin)/.test(url.pathname)) return false;
    if (!/(\/|\.html)$/.test(url.pathname)) return false;
    // Same page, only the hash differs: let it scroll.
    if (url.pathname === location.pathname && url.search === location.search) return false;
    return true;
  }

  document.addEventListener('click', function (e) {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    var a = e.target.closest && e.target.closest('a');
    if (!a || !isSitePage(a)) return;
    e.preventDefault();
    var href = a.href;
    el.style.animation = 'none';
    el.classList.remove('is-done');
    el.classList.add('is-covering');
    setTimeout(function () { location.href = href; }, 260);
    // If the navigation never happens (blocked, offline), don't stay covered.
    setTimeout(reveal, 4000);
  });
})();
