/* ============================================================
   SilaFit admin console — API client for the two-factor sign-in.

   The console is not protected by anything in this file. Access is enforced by
   the API: nginx refuses to serve admin.html at all unless a valid session
   cookie is presented (see deploy/nginx-silafit.tappit.click.conf). Everything
   here just talks to those endpoints and reacts to their status codes.

   Every request sends `credentials: 'include'` so the HttpOnly session cookie
   travels with it — the cookie is never readable from JS, by design.
   ============================================================ */
(function (global) {
  'use strict';

  /* Same-origin by default: in production the static site and the API share a
     host, so relative URLs are correct. When testing locally with the site on a
     static server (say :8099) and the API on :5080, set
     `window.SILAFIT_API_BASE = 'http://localhost:5080'` in a script tag before
     this file loads — Program.cs allow-lists loopback origins with credentials
     for exactly that case, in Development only. */
  var API_BASE = (global.SILAFIT_API_BASE || '').replace(/\/+$/, '');

  function request(path, method, body) {
    var init = { method: method || 'GET', credentials: 'include', headers: {} };

    if (body !== undefined) {
      init.headers['Content-Type'] = 'application/json';
      init.body = JSON.stringify(body);
    }

    return fetch(API_BASE + path, init).then(function (response) {
      return response.json().then(function (payload) {
        return {
          ok: response.ok,
          status: response.status,
          data: payload && payload.success ? payload.data : null,
          message: payload && payload.message ? payload.message : null
        };
      }, function () {
        // 401s from the session probe carry a JSON envelope too, but never assume it.
        return { ok: response.ok, status: response.status, data: null, message: null };
      });
    }, function () {
      return {
        ok: false,
        status: 0,
        data: null,
        message: 'Could not reach the SilaFit API. Check your connection and try again.'
      };
    });
  }

  global.SilaAdminAuth = {
    /* Step 1 — password. Resolves to a challenge, not to a session. */
    login: function (username, password) {
      return request('/api/admin/auth/login', 'POST', { username: username, password: password });
    },

    /* Step 2 — authenticator code. Sets the session cookie on success. */
    verify: function (challengeToken, code) {
      return request('/api/admin/auth/verify', 'POST', { challengeToken: challengeToken, code: code });
    },

    /* Is the cookie still live? Also the endpoint nginx calls, so a 200 here means
       nginx would serve admin.html right now. */
    session: function () {
      return request('/api/admin/auth/session', 'GET');
    },

    logout: function () {
      return request('/api/admin/auth/logout', 'POST');
    },

    /* Ends sessions on every device, not just this browser. */
    logoutEverywhere: function () {
      return request('/api/admin/auth/logout-all', 'POST');
    },

    /* Only ever redirect to a path on this origin — never to a value a query
       string could point somewhere else. */
    safeNext: function (candidate) {
      return typeof candidate === 'string' && candidate.charAt(0) === '/' && candidate.charAt(1) !== '/' ? candidate : null;
    },

    loginUrl: function (next) {
      var safe = global.SilaAdminAuth.safeNext(next);
      return 'admin-login.html' + (safe ? '?next=' + encodeURIComponent(safe) : '');
    }
  };
})(window);
