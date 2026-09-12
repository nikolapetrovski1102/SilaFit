/* ============================================================
   SilaFit admin console — session bar.

   nginx only serves admin.html to a request holding a valid session cookie, so
   by the time this runs the visitor is already authorized. What is left for the
   client is the honest UX around that: show who is signed in, how long the
   session has left, and — when it runs out mid-edit — stop pretending and send
   them back to the login page instead of letting them keep clicking.

   A network failure here is deliberately *not* treated as "signed out": the API
   might just be briefly unreachable while the cookie is still perfectly valid.
   ============================================================ */
(function () {
  'use strict';

  var auth = window.SilaAdminAuth;
  if (!auth) return;

  var expiryTimer = null;

  function $(sel) { return document.querySelector(sel); }

  function formatTimeLeft(expiresAtUtc) {
    var secondsLeft = Math.max(0, Math.round((new Date(expiresAtUtc).getTime() - Date.now()) / 1000));
    return Math.floor(secondsLeft / 60) + ' min';
  }

  function goToLogin(reason) {
    var next = location.pathname + location.search;
    location.replace(auth.loginUrl(next) + (reason ? (next ? '&' : '?') + 'reason=' + reason : ''));
  }

  function showSignedIn(session) {
    var nameEls = document.querySelectorAll('[data-session-username]');
    Array.prototype.forEach.call(nameEls, function (el) { el.textContent = session.username; });

    var expiryEls = document.querySelectorAll('[data-session-expiry]');
    Array.prototype.forEach.call(expiryEls, function (el) {
      el.textContent = 'expires after ' + formatTimeLeft(session.expiresAtUtc) + ' idle';
    });

    document.body.classList.add('is-signed-in');
    scheduleExpiryCheck(session.expiresAtUtc);
  }

  /* The API slides the idle deadline on every authenticated request, so the
     timestamp we hold is only a lower bound: re-check when it lapses rather than
     kicking someone out on a stale number. */
  function scheduleExpiryCheck(expiresAtUtc) {
    window.clearTimeout(expiryTimer);

    var msUntilExpiry = new Date(expiresAtUtc).getTime() - Date.now();
    expiryTimer = window.setTimeout(function () {
      auth.session().then(function (result) {
        if (result.ok && result.data) {
          scheduleExpiryCheck(result.data.expiresAtUtc);
        } else if (result.status === 401) {
          goToLogin('expired');
        }
      });
    }, Math.max(1000, msUntilExpiry + 1000));
  }

  function signOut(everywhere) {
    var call = everywhere ? auth.logoutEverywhere() : auth.logout();
    call.then(function () { goToLogin(everywhere ? 'signed-out-all' : 'signed-out'); });
  }

  Array.prototype.forEach.call(document.querySelectorAll('[data-sign-out]'), function (btn) {
    btn.addEventListener('click', function () { signOut(false); });
  });

  Array.prototype.forEach.call(document.querySelectorAll('[data-sign-out-everywhere]'), function (btn) {
    btn.addEventListener('click', function () { signOut(true); });
  });

  auth.session().then(function (result) {
    if (result.ok && result.data) {
      showSignedIn(result.data);
      return;
    }

    if (result.status === 401) {
      goToLogin('expired');
      return;
    }

    // Reachable but unhappy (5xx / offline): leave the console usable and say so.
    var banner = $('#sessionWarning');
    if (banner) {
      banner.textContent = result.message || 'Could not confirm your session with the API.';
      banner.hidden = false;
    }
  });
})();
