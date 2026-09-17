/* ============================================================
   SilaFit admin console — API client for the two-factor sign-in.

   The console is not protected by anything in this file. Access is enforced by
   the API: nginx refuses to serve admin.html at all unless a valid session
   cookie is presented (see deploy/nginx-sila.fitness.conf). Everything
   here just talks to those endpoints and reacts to their status codes.

   Every request sends `credentials: 'include'` so the HttpOnly session cookie
   travels with it — the cookie is never readable from JS, by design.
   ============================================================ */
(function (global) {
  'use strict';

  /* Same-origin by default: in production the static site and the API share a
     host, so relative URLs are correct. Locally there is no shared host — the
     site is opened straight from disk or served by a throwaway static server,
     while the API runs via `docker compose up` on :5080 (see
     docs/starting-the-stack.md) — so default to that instead of making every
     contributor discover and set `window.SILAFIT_API_BASE` by hand. Program.cs
     allow-lists loopback origins with credentials for exactly this case, in
     Development only. Set `window.SILAFIT_API_BASE` yourself in a script tag
     before this file loads to override (e.g. the API on a non-default port).

     Deliberately `localhost`, not this machine's LAN IP: the admin session
     cookie is SameSite=Strict (host-only, port doesn't matter), and the CORS
     policy in Program.cs only allow-lists localhost/127.0.0.1/null - so both
     the static site and this default have to stay on `localhost` for the
     post-login session check (and CORS) to accept the request at all. */
  var API_BASE = (global.SILAFIT_API_BASE || defaultDevApiBase()).replace(/\/+$/, '');

  function defaultDevApiBase() {
    var isFileProtocol = global.location.protocol === 'file:';
    var isLoopbackHttp = global.location.protocol === 'http:' &&
      (global.location.hostname === 'localhost' || global.location.hostname === '127.0.0.1') &&
      global.location.port !== '5080';

    return (isFileProtocol || isLoopbackHttp) ? 'http://localhost:5080' : '';
  }

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

  // Multipart upload — separate from request() because that helper always
  // JSON.stringifies its body, which would corrupt a File. No Content-Type
  // header is set here on purpose: the browser fills in the multipart
  // boundary itself, and overriding it drops the boundary and breaks parsing.
  function uploadFile(path, file) {
    var formData = new FormData();
    formData.append('file', file);

    return fetch(API_BASE + path, { method: 'POST', credentials: 'include', body: formData })
      .then(function (response) {
        return response.json().then(function (payload) {
          return {
            ok: response.ok,
            status: response.status,
            data: payload && payload.success ? payload.data : null,
            message: payload && payload.message ? payload.message : null
          };
        }, function () {
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

    /* "Send email code instead" — emails a one-time code to the account's address
       on file. The code it sends is checked by the same verify() call above, so
       no separate step is needed once it arrives. */
    sendEmailCode: function (challengeToken) {
      return request('/api/admin/auth/email-code', 'POST', { challengeToken: challengeToken });
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
    },

    /* ---------------------------------------------------------------
       Roles, operators and audit log — the "who can do what" screens.
       Every one of these can 403 (signed in, wrong permission) as well
       as 401 (not signed in); callers check `result.status`, same as
       everywhere else in this client.
       --------------------------------------------------------------- */

    /** The full set of permission names the database can grant. */
    getPermissionCatalog: function () {
      return request('/api/admin/rbac/permissions', 'GET');
    },

    /** Every role with its full permission grant list. */
    getRoles: function () {
      return request('/api/admin/rbac/roles', 'GET');
    },

    createRole: function (name, description) {
      return request('/api/admin/rbac/roles', 'POST', { name: name, description: description || null });
    },

    deleteRole: function (roleName) {
      return request('/api/admin/rbac/roles/' + encodeURIComponent(roleName), 'DELETE');
    },

    /** Grants or revokes one permission on one custom role. */
    setRolePermission: function (roleName, permission, granted) {
      return request('/api/admin/rbac/roles/permission', 'PUT', {
        roleName: roleName, permission: permission, granted: granted
      });
    },

    getOperators: function (includeInactive) {
      return request('/api/admin/rbac/operators' + (includeInactive ? '?includeInactive=true' : ''), 'GET');
    },

    /** Response carries a TOTP secret + otpauth URI — shown exactly once. */
    createOperator: function (username, email, password, roleName) {
      return request('/api/admin/rbac/operators', 'POST', {
        username: username, email: email, password: password, roleName: roleName || null
      });
    },

    /** Confirms the email a new operator was created with, from the link in their confirmation email. */
    confirmOperatorEmail: function (token) {
      return request('/api/admin/rbac/operators/confirm-email', 'POST', { token: token });
    },

    /** Re-sends the confirmation link to an operator's address on file (never a caller-supplied one). */
    resendOperatorConfirmation: function (username) {
      return request('/api/admin/rbac/operators/resend-confirmation', 'POST', { username: username });
    },

    setOperatorRole: function (username, roleName) {
      return request('/api/admin/rbac/operators/role', 'PUT', { username: username, roleName: roleName });
    },

    setOperatorActive: function (username, isActive) {
      return request('/api/admin/rbac/operators/active', 'PUT', { username: username, isActive: isActive });
    },

    getRecentAudit: function (limit) {
      return request('/api/admin/rbac/audit' + (limit ? '?limit=' + encodeURIComponent(limit) : ''), 'GET');
    },

    /* ---------------------------------------------------------------
       Content — exercises, meal suggestions, plans, splits and the
       read-only user list. Same 401/403 shape as the RBAC calls above.
       --------------------------------------------------------------- */

    getExercises: function () {
      return request('/api/admin/content/exercises', 'GET');
    },

    saveExercise: function (exercise) {
      return request('/api/admin/content/exercises', 'POST', exercise);
    },

    deleteExercise: function (exerciseId) {
      return request('/api/admin/content/exercises/' + encodeURIComponent(exerciseId), 'DELETE');
    },

    getMealSuggestions: function (filters) {
      filters = filters || {};
      var params = [];
      if (filters.suggestedMonth) params.push('suggestedMonth=' + encodeURIComponent(filters.suggestedMonth));
      if (filters.mealType) params.push('mealType=' + encodeURIComponent(filters.mealType));
      if (filters.search) params.push('search=' + encodeURIComponent(filters.search));
      return request('/api/admin/content/meal-suggestions' + (params.length ? '?' + params.join('&') : ''), 'GET');
    },

    saveMealSuggestion: function (suggestion) {
      return request('/api/admin/content/meal-suggestions', 'POST', suggestion);
    },

    deleteMealSuggestion: function (mealSuggestionId) {
      return request('/api/admin/content/meal-suggestions/' + encodeURIComponent(mealSuggestionId), 'DELETE');
    },

    getPlans: function () {
      return request('/api/admin/content/plans', 'GET');
    },

    getPlanFeatures: function (planId) {
      return request('/api/admin/content/plans/' + encodeURIComponent(planId) + '/features', 'GET');
    },

    savePlan: function (plan) {
      return request('/api/admin/content/plans', 'POST', plan);
    },

    deletePlan: function (planId) {
      return request('/api/admin/content/plans/' + encodeURIComponent(planId), 'DELETE');
    },

    savePlanFeature: function (feature) {
      return request('/api/admin/content/plans/features', 'POST', feature);
    },

    deletePlanFeature: function (planFeatureId) {
      return request('/api/admin/content/plans/features/' + encodeURIComponent(planFeatureId), 'DELETE');
    },

    getPlanEntitlements: function (planId) {
      return request('/api/admin/content/plans/' + encodeURIComponent(planId) + '/entitlements', 'GET');
    },

    savePlanEntitlements: function (entitlements) {
      return request('/api/admin/content/plans/entitlements', 'PUT', entitlements);
    },

    getSplits: function () {
      return request('/api/admin/content/splits', 'GET');
    },

    getSplitDetail: function (splitId) {
      return request('/api/admin/content/splits/' + encodeURIComponent(splitId), 'GET');
    },

    saveSplit: function (split) {
      return request('/api/admin/content/splits', 'POST', split);
    },

    deleteSplit: function (splitId) {
      return request('/api/admin/content/splits/' + encodeURIComponent(splitId), 'DELETE');
    },

    // Returns { ok, data: { url }, message } — url is the public
    // images.sila.fitness (or local /uploads fallback) address to store on the split.
    uploadImage: function (file) {
      return uploadFile('/api/admin/content/images', file);
    },

    /* Clients a split is assigned to, and the assign/unassign mutations. */
    getSplitAssignments: function (splitId) {
      return request('/api/admin/content/splits/' + encodeURIComponent(splitId) + '/assignments', 'GET');
    },

    assignSplit: function (splitId, userId, setActive) {
      return request('/api/admin/content/splits/assignments', 'POST', {
        splitId: splitId, userId: userId, setActive: !!setActive
      });
    },

    removeSplitAssignment: function (splitId, userId) {
      return request('/api/admin/content/splits/' + encodeURIComponent(splitId) +
        '/assignments/' + encodeURIComponent(userId), 'DELETE');
    },

    saveSplitDay: function (day) {
      return request('/api/admin/content/splits/days', 'POST', day);
    },

    deleteSplitDay: function (splitDayId) {
      return request('/api/admin/content/splits/days/' + encodeURIComponent(splitDayId), 'DELETE');
    },

    saveSplitDayExercise: function (exercise) {
      return request('/api/admin/content/splits/days/exercises', 'POST', exercise);
    },

    deleteSplitDayExercise: function (splitDayExerciseId) {
      return request('/api/admin/content/splits/days/exercises/' + encodeURIComponent(splitDayExerciseId), 'DELETE');
    },

    getDietPlans: function () {
      return request('/api/admin/content/diet-plans', 'GET');
    },

    getDietPlanDetail: function (dietPlanId) {
      return request('/api/admin/content/diet-plans/' + encodeURIComponent(dietPlanId), 'GET');
    },

    saveDietPlan: function (plan) {
      return request('/api/admin/content/diet-plans', 'POST', plan);
    },

    deleteDietPlan: function (dietPlanId) {
      return request('/api/admin/content/diet-plans/' + encodeURIComponent(dietPlanId), 'DELETE');
    },

    /* Clients a diet plan is assigned to, and the assign/unassign mutations. */
    getDietPlanAssignments: function (dietPlanId) {
      return request('/api/admin/content/diet-plans/' + encodeURIComponent(dietPlanId) + '/assignments', 'GET');
    },

    assignDietPlan: function (dietPlanId, userId, setActive) {
      return request('/api/admin/content/diet-plans/assignments', 'POST', {
        dietPlanId: dietPlanId, userId: userId, setActive: !!setActive
      });
    },

    removeDietPlanAssignment: function (dietPlanId, userId) {
      return request('/api/admin/content/diet-plans/' + encodeURIComponent(dietPlanId) +
        '/assignments/' + encodeURIComponent(userId), 'DELETE');
    },

    saveDietPlanDay: function (day) {
      return request('/api/admin/content/diet-plans/days', 'POST', day);
    },

    deleteDietPlanDay: function (dietPlanDayId) {
      return request('/api/admin/content/diet-plans/days/' + encodeURIComponent(dietPlanDayId), 'DELETE');
    },

    saveDietPlanMeal: function (meal) {
      return request('/api/admin/content/diet-plans/meals', 'POST', meal);
    },

    deleteDietPlanMeal: function (dietPlanMealId) {
      return request('/api/admin/content/diet-plans/meals/' + encodeURIComponent(dietPlanMealId), 'DELETE');
    },

    getUsers: function (search, limit) {
      var params = [];
      if (search) params.push('search=' + encodeURIComponent(search));
      if (limit) params.push('limit=' + encodeURIComponent(limit));
      return request('/api/admin/content/users' + (params.length ? '?' + params.join('&') : ''), 'GET');
    },

    /* Super-admin only (users.mock_data): replace one user's logs with a generated
       month of history so the monthly overview has something to show. Destructive
       and slow — the modal warns before calling this. */
    seedUserMockData: function (userId, profile, days, seed) {
      var body = { userId: userId, profile: profile, days: days };
      if (seed !== null && seed !== undefined && seed !== '') body.seed = parseInt(seed, 10);
      return request('/api/admin/content/users/mock-data', 'POST', body);
    }
  };
})(window);
