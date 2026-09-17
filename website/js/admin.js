/* ============================================================
   SilaFit admin dashboard — views, CRUD, toasts.
   Every mutation here goes through window.SilaAdminAuth (js/admin-auth.js),
   which talks to the real cookie-authenticated API and, through it, the real
   SQL Server database — there is no local store behind this file. Each
   content screen is gated by the exact content.* permission its API calls
   require; the sidebar hides a tab the signed-in operator can't use, and a
   403 that slips through anyway (e.g. a permission revoked mid-session)
   surfaces as a toast rather than a crash.
   ============================================================ */
(function () {
  'use strict';

  var auth = window.SilaAdminAuth;
  if (!auth) return;

  var $ = function (sel, root) { return (root || document).querySelector(sel); };
  var $$ = function (sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); };

  function esc(str) {
    return String(str == null ? '' : str)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function num(v) { var n = parseInt(v, 10); return isNaN(n) ? 0 : n; }

  function fmtDate(iso) {
    if (!iso) return '—';
    var d = new Date(iso);
    return isNaN(d.getTime()) ? '—' : d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
  }

  /* Closed sets mirrored from Silen.Services.Helpers.AdminContentFieldRules —
     the API is the real gate, this is just so the selects only offer values
     that will actually be accepted. */
  var MUSCLE_GROUPS = ['chest', 'back', 'legs', 'shoulders', 'arms', 'core'];
  var MEAL_TYPES = ['Breakfast', 'Lunch', 'Dinner', 'Snack'];
  // 'Custom' is a real, server-accepted category (a user-built split keeps it),
  // and it was missing here: opening such a split left the <select> with no
  // matching option, so the browser fell back to the first entry and saving
  // silently recategorised the split.
  var SPLIT_CATEGORIES = ['PushPullLegs', 'UpperLower', 'FullBody', 'ArnoldSplit', 'PHUL', 'PHAT', 'BroSplit', 'Circuit', 'Powerlifting', 'Calisthenics', 'GluteFocus', 'Custom'];
  var SPLIT_LEVELS = ['Beginner', 'Intermediate', 'Advanced'];
  var RECOMMENDED_GOALS = ['BuildMuscle', 'LoseFat', 'MaintainActive'];
  /* Mirrors Silen.Services.Helpers.AdminContentFieldRules.SplitVisibilities:
     Private = owner only, Public = every app user, Shared = assigned users. */
  var SPLIT_VISIBILITIES = ['Private', 'Public', 'Shared'];
  var DIET_PLAN_PERIODS = ['Weekly', 'Monthly'];
  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  /* ---------------- Toasts ---------------- */
  function toast(message, isError) {
    var stack = $('#toastStack');
    if (!stack) return;
    var el = document.createElement('div');
    el.className = 'toast' + (isError ? ' toast--error' : '');
    el.innerHTML = '<span class="dot"></span>' + esc(message);
    stack.appendChild(el);
    setTimeout(function () {
      el.style.transition = 'opacity 200ms ease, transform 200ms ease';
      el.style.opacity = '0';
      el.style.transform = 'translateY(8px)';
      setTimeout(function () { el.remove(); }, 220);
    }, 2600);
  }

  /* A failed call that isn't a 401 (session already handled elsewhere) gets a toast. */
  function toastOnFailure(result, fallback) {
    if (!result.ok && result.status !== 401) toast(result.message || fallback, true);
    return result.ok;
  }

  /* ---------------- Modal ---------------- */
  var modalRoot = $('#modalRoot');

  function openModal(html, wide) {
    modalRoot.innerHTML =
      '<div class="modal-backdrop" id="modalBackdrop">' +
        '<div class="modal' + (wide ? ' modal--wide' : '') + '" role="dialog">' + html + '</div>' +
      '</div>';
    var backdrop = $('#modalBackdrop');
    backdrop.addEventListener('mousedown', function (e) {
      if (e.target === backdrop) closeModal();
    });
    document.addEventListener('keydown', escListener);
    return backdrop;
  }

  function escListener(e) { if (e.key === 'Escape') closeModal(); }

  function closeModal() {
    modalRoot.innerHTML = '';
    document.removeEventListener('keydown', escListener);
  }

  function modalHead(title) {
    return (
      '<div class="modal__head">' +
        '<div class="headline-md">' + esc(title) + '</div>' +
        '<button class="icon-btn" data-close aria-label="Close">' +
          '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M6 6l12 12M18 6 6 18"/></svg>' +
        '</button>' +
      '</div>'
    );
  }

  /* Wire close buttons inside the currently open modal. */
  function wireClose(backdrop) {
    $$('[data-close]', backdrop).forEach(function (b) {
      b.addEventListener('click', closeModal);
    });
  }

  /* ---------------- Sidebar navigation ---------------- */
  var overlay = $('#sidebarOverlay');

  function openSidebar() {
    $('#sidebar').classList.add('is-open');
    if (overlay) overlay.classList.add('is-open');
  }
  function closeSidebar() {
    $('#sidebar').classList.remove('is-open');
    if (overlay) overlay.classList.remove('is-open');
  }

  if (overlay) {
    overlay.addEventListener('click', closeSidebar);
  }

  function showView(name) {
    $$('.side-link[data-view]').forEach(function (b) {
      b.classList.toggle('is-active', b.getAttribute('data-view') === name);
    });
    $$('.view').forEach(function (v) {
      v.classList.toggle('is-active', v.id === 'view-' + name);
    });
    closeSidebar();
    /* Scroll main to top on view change */
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  $$('.side-link[data-view]').forEach(function (b) {
    b.addEventListener('click', function () { showView(b.getAttribute('data-view')); });
  });

  $$('[data-goto]').forEach(function (b) {
    b.addEventListener('click', function () {
      showView(b.getAttribute('data-goto'));
      var create = b.getAttribute('data-open-create');
      if (create) openCreate(create);
    });
  });

  $$('.admin-menu-btn').forEach(function (b) {
    b.addEventListener('click', function () {
      if ($('#sidebar').classList.contains('is-open')) { closeSidebar(); } else { openSidebar(); }
    });
  });

  /* ================================================================
     Permissions — gates which of this file's own nav tabs show, and
     which of its own loaders run. The API enforces the same permission
     on every request regardless of what the sidebar shows.
     ================================================================ */
  var myPermissions = [];
  function has(permission) { return myPermissions.indexOf(permission) > -1; }

  var CONTENT_NAV_IDS = ['navSplits', 'navDietPlans', 'navSuggestions', 'navExercises', 'navPlans', 'navUsers'];

  function applyContentNavGating() {
    CONTENT_NAV_IDS.forEach(function (id) {
      var btn = document.getElementById(id);
      if (btn) btn.hidden = !has(btn.getAttribute('data-permission'));
    });
  }

  /* ================================================================
     State caches — populated by each view's loader, read by Overview.
     ================================================================ */
  var exercisesCache = [];
  var suggestionsCache = [];
  var plansCache = [];
  var splitsCache = [];
  var dietPlansCache = [];
  var usersCache = [];

  /* ================================================================
     Shared picker helpers.

     Both sub-editors (a split day's exercises, a diet day's meals) let the
     operator search, filter and change the referenced library row, so the
     option markup lives here instead of being duplicated per editor. Every
     option carries the row's key details - muscle group, meal type, calories -
     so the choice can be made without leaving the editor.
     ================================================================ */

  /// Options for an exercise <select>, alphabetised, filtered by an optional
  /// free-text term and/or muscle group, with `selectedId` pre-selected.
  function exerciseOptionHtml(selectedId, search, muscle) {
    var term = (search || '').trim().toLowerCase();
    return exercisesCache.filter(function (e) {
      if (muscle && e.muscleGroup !== muscle) return false;
      if (!term) return true;
      return (e.name || '').toLowerCase().indexOf(term) !== -1;
    }).sort(function (a, b) { return a.name.localeCompare(b.name); })
      .map(function (e) {
        return '<option value="' + e.exerciseId + '"' +
          (e.exerciseId === selectedId ? ' selected' : '') + '>' +
          esc(e.name) + ' (' + esc(e.muscleGroup) + ')</option>';
      }).join('');
  }

  /// Options for a meal <select>, alphabetised, filtered by an optional
  /// free-text term and/or meal type, with `selectedId` pre-selected.
  function mealOptionHtml(selectedId, search, mealType) {
    var term = (search || '').trim().toLowerCase();
    return suggestionsCache.filter(function (s) {
      if (mealType && s.mealType !== mealType) return false;
      if (!term) return true;
      return (s.title || '').toLowerCase().indexOf(term) !== -1;
    }).sort(function (a, b) { return a.title.localeCompare(b.title); })
      .map(function (s) {
        return '<option value="' + s.mealSuggestionId + '"' +
          (s.mealSuggestionId === selectedId ? ' selected' : '') + '>' +
          esc(s.title) + ' · ' + esc(s.mealType) + ' (' + s.caloriesKcal + ' kcal)</option>';
      }).join('');
  }

  /* ================================================================
     OVERVIEW
     ================================================================ */
  function renderOverview() {
    $('#overviewDate').textContent = new Date().toLocaleDateString('en-GB', {
      weekday: 'long', day: 'numeric', month: 'long', year: 'numeric'
    });

    if (has('users.read')) {
      $('#statUsers').textContent = usersCache.length;
      $('#statUsersDelta').textContent = usersCache.filter(function (u) { return u.isActive; }).length + ' active';
    } else {
      $('#statUsers').textContent = '—';
      $('#statUsersDelta').textContent = 'Requires users.read';
    }

    if (has('users.read') && has('content.plans.read')) {
      var paid = usersCache.filter(function (u) { return u.subscriptionStatus === 'Active' && u.activePlanCode; });
      var mrr = paid.reduce(function (sum, u) {
        var p = plansCache.find(function (x) { return x.code === u.activePlanCode; });
        if (!p) return sum;
        return sum + (u.billingCycle === 'Yearly' ? p.yearlyPrice / 12 : p.monthlyPrice);
      }, 0);
      $('#statSubs').textContent = paid.length;
      $('#statSubsDelta').textContent = usersCache.length ? Math.round(paid.length / usersCache.length * 100) + '% of users' : '';
      $('#statMrr').textContent = '€' + mrr.toFixed(2);
    } else {
      $('#statSubs').textContent = '—';
      $('#statSubsDelta').textContent = 'Requires users.read + content.plans.read';
      $('#statMrr').textContent = '—';
    }

    if (has('content.suggestions.read')) {
      $('#statMeals').textContent = suggestionsCache.length;
      var monthTagged = suggestionsCache.filter(function (s) { return s.suggestedMonth; }).length;
      $('#statMealsDelta').textContent = monthTagged + ' tagged to a month';
    } else {
      $('#statMeals').textContent = '—';
      $('#statMealsDelta').textContent = 'Requires content.suggestions.read';
    }

    var libraryRows = [
      has('content.splits.read') ? { label: 'Splits', value: splitsCache.length, sub: splitsCache.reduce(function (s, x) { return s + x.dayCount; }, 0) + ' days total', view: 'splits' } : null,
      has('content.diet_plans.read') ? { label: 'Diet plans', value: dietPlansCache.length, sub: dietPlansCache.reduce(function (s, x) { return s + x.dayCount; }, 0) + ' days total', view: 'diet-plans' } : null,
      has('content.exercises.read') ? { label: 'Exercises', value: exercisesCache.length, sub: 'reference library', view: 'exercises' } : null,
      has('content.suggestions.read') ? { label: 'Meal suggestions', value: suggestionsCache.length, sub: 'app + landing strip', view: 'suggestions' } : null,
      has('content.plans.read') ? { label: 'Subscription plans', value: plansCache.length, sub: plansCache.reduce(function (s, x) { return s + x.activeSubscriberCount; }, 0) + ' active subs', view: 'plans' } : null
    ].filter(Boolean);

    $('#libraryStatsList').innerHTML = libraryRows.length ? libraryRows.map(function (r) {
      return (
        '<div class="activity-item">' +
          '<div class="body-md" style="font-size:13.5px;flex:1">' + esc(r.label) + '<div class="row-sub">' + esc(r.sub) + '</div></div>' +
          '<time style="font-weight:700;color:var(--high-emphasis);font-size:15px;">' + r.value + '</time>' +
        '</div>'
      );
    }).join('') : '<div class="empty-state" style="padding:24px"><div class="body-sm">No content permissions granted to this operator.</div></div>';

    if (has('audit.read') && auth.getRecentAudit) {
      auth.getRecentAudit(6).then(function (result) {
        if (!result.ok) { $('#activityList').innerHTML = ''; return; }
        var entries = result.data || [];
        $('#activityList').innerHTML = entries.length ? entries.map(function (e) {
          return (
            '<div class="activity-item">' +
              '<div class="activity-item__icon">' +
                '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6.5 6.5v11m11-11v11M3 9v6m18-6v6M6.5 12h11"/></svg>' +
              '</div>' +
              '<div class="body-md" style="font-size:13.5px"><b>' + esc(e.username) + '</b> ' + esc(e.action) + ' — ' + esc(e.entityType) + (e.summary ? ' · ' + esc(e.summary) : '') + '</div>' +
              '<time>' + fmtDate(e.createdAtUtc) + '</time>' +
            '</div>'
          );
        }).join('') : '<div class="empty-state" style="padding:24px"><div class="body-sm">Nothing logged yet.</div></div>';
      });
    } else {
      $('#activityList').innerHTML = '<div class="empty-state" style="padding:24px"><div class="body-sm">Recent activity needs the audit.read permission.</div></div>';
    }
  }

  /* ================================================================
     SPLITS — day-by-day workout templates
     ================================================================ */
  var splitCategoryFilter = 'all';

  function renderSplitFilters() {
    var sel = $('#splitCategoryFilter');
    sel.innerHTML = '<option value="all">All categories</option>' +
      SPLIT_CATEGORIES.map(function (c) {
        return '<option value="' + c + '"' + (splitCategoryFilter === c ? ' selected' : '') + '>' + c + '</option>';
      }).join('');
  }

  function loadSplits() {
    return auth.getSplits().then(function (result) {
      if (!toastOnFailure(result, 'Could not load splits.')) return;
      splitsCache = result.data || [];
      renderSplits();
    });
  }

  function renderSplits() {
    renderSplitFilters();
    var splits = splitsCache.filter(function (s) {
      return splitCategoryFilter === 'all' || s.category === splitCategoryFilter;
    });

    var grid = $('#splitGrid');
    if (!grid) return;
    if (!splits.length) {
      grid.innerHTML =
        '<div class="card empty-state" style="grid-column:1/-1">' +
          '<img src="assets/img/mascot/ready.png" alt="Mascot ready" />' +
          '<div class="headline-sm">No splits yet</div>' +
          '<p class="body-sm">Create a split, then add its days and exercises.</p>' +
        '</div>';
      return;
    }

    grid.innerHTML = splits.map(function (s) {
      /* A trainer only ever gets the controls for splits they own (canManage is
         computed server-side from ownership + content.splits.manage_all). */
      var actions = s.canManage ? (
        '<button class="icon-btn" data-edit-split="' + s.splitId + '" title="Edit details">' +
          '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 3a2.8 2.8 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3Z"/></svg>' +
        '</button>' +
        '<button class="icon-btn icon-btn--danger" data-del-split="' + s.splitId + '" title="Delete">' +
          '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 7h16M9 7V4h6v3m-8 0 1 13h8l1-13"/></svg>' +
        '</button>'
      ) : '';

      var foot = '';
      if (s.canManage) {
        foot += '<button class="btn btn--secondary btn--sm" data-manage-days="' + s.splitId + '">Manage days</button>';
        if (has('content.splits.assign')) {
          foot += '<button class="btn btn--primary btn--sm" data-assign-split="' + s.splitId + '">Assign to clients</button>';
        }
      }

      return (
        '<article class="card mp-card">' +
          '<div class="mp-card__head">' +
            '<span class="chip chip--accent">' + esc(s.level) + '</span>' +
            '<span class="chip chip--gold">' + esc(s.category) + '</span>' +
            (s.isSystemDefault ? '<span class="chip">System</span>' : '') +
            '<span class="spacer"></span>' +
            '<div class="row-actions">' + actions + '</div>' +
          '</div>' +
          '<div>' +
            '<div class="headline-sm">' + esc(s.name) + '</div>' +
            '<div class="mp-card__desc" style="margin-top:6px">' + esc(s.description || '') + '</div>' +
          '</div>' +
          '<div class="mp-card__targets">' +
            '<span class="chip">' + esc(s.visibility || 'Public') + '</span>' +
            '<span class="chip">' + s.durationDays + ' days</span>' +
            '<span class="chip">' + s.dayCount + ' scheduled</span>' +
            '<span class="chip">' + s.exerciseCount + ' exercises</span>' +
            (s.ownerUsername ? '<span class="chip">by ' + esc(s.ownerUsername) + '</span>' : '') +
            (s.recommendedGoal ? '<span class="chip">' + esc(s.recommendedGoal) + '</span>' : '') +
            (s.assignedUserCount ? '<span class="chip chip--gold">' + s.assignedUserCount + ' assigned</span>' : '') +
            (s.activeUserCount ? '<span class="chip chip--accent">' + s.activeUserCount + ' active users</span>' : '') +
          '</div>' +
          (foot ? '<div class="mp-card__foot">' + foot + '</div>' : '') +
        '</article>'
      );
    }).join('');

    $$('[data-edit-split]').forEach(function (b) {
      b.addEventListener('click', function () { openSplitEditor(b.getAttribute('data-edit-split')); });
    });
    $$('[data-manage-days]').forEach(function (b) {
      b.addEventListener('click', function () { openSplitDaysEditor(b.getAttribute('data-manage-days')); });
    });
    $$('[data-assign-split]').forEach(function (b) {
      b.addEventListener('click', function () { openSplitAssignments(b.getAttribute('data-assign-split')); });
    });
    $$('[data-del-split]').forEach(function (b) {
      b.addEventListener('click', function () {
        var s = splitsCache.find(function (x) { return x.splitId === b.getAttribute('data-del-split'); });
        if (!s) return;
        confirmDelete('Delete "' + s.name + '"?', 'Refused while any user has this split active.', function () {
          auth.deleteSplit(s.splitId).then(function (result) {
            if (!toastOnFailure(result, 'Could not delete split.')) return;
            toast((result.data && result.data.message) || 'Split deleted.');
            loadSplits();
          });
        });
      });
    });
  }

  function openSplitEditor(splitId) {
    var isNew = !splitId;
    var s = isNew
      ? { name: '', category: SPLIT_CATEGORIES[0], level: SPLIT_LEVELS[0], durationDays: 7, description: '', heroImageUrl: '', recommendedGoal: '', visibility: 'Private', sortOrder: 0 }
      : splitsCache.find(function (x) { return x.splitId === splitId; });
    if (!isNew && !s) return;

    var backdrop = openModal(
      modalHead(isNew ? 'New split' : 'Edit split') +
      '<div class="form-grid">' +
        '<div class="field field--full"><label>Name</label>' +
          '<input class="input" id="spName" value="' + esc(s.name) + '" placeholder="Push Pull Legs — 6 Day" /></div>' +
        '<div class="field"><label>Category</label>' +
          '<select class="select" id="spCategory">' +
            SPLIT_CATEGORIES.map(function (c) { return '<option' + (s.category === c ? ' selected' : '') + '>' + c + '</option>'; }).join('') +
          '</select></div>' +
        '<div class="field"><label>Level</label>' +
          '<select class="select" id="spLevel">' +
            SPLIT_LEVELS.map(function (l) { return '<option' + (s.level === l ? ' selected' : '') + '>' + l + '</option>'; }).join('') +
          '</select></div>' +
        '<div class="field"><label>Visibility</label>' +
          '<select class="select" id="spVisibility">' +
            SPLIT_VISIBILITIES.map(function (v) { return '<option' + (s.visibility === v ? ' selected' : '') + '>' + v + '</option>'; }).join('') +
          '</select></div>' +
        '<div class="field field--full"><span class="label-sm" style="color:var(--on-surface-variant)">' +
          'Private: only you. Public: every app user. Shared: only the clients you assign it to.' +
        '</span></div>' +
        '<div class="field"><label>Duration (days)</label><input class="input" type="number" min="1" max="14" id="spDuration" value="' + s.durationDays + '" /></div>' +
        '<div class="field"><label>Recommended goal</label>' +
          '<select class="select" id="spGoal">' +
            '<option value="">No specific goal</option>' +
            RECOMMENDED_GOALS.map(function (g) { return '<option' + (s.recommendedGoal === g ? ' selected' : '') + '>' + g + '</option>'; }).join('') +
          '</select></div>' +
        '<div class="field field--full"><label>Description</label>' +
          '<textarea class="textarea" id="spDesc" placeholder="Who is this split for?">' + esc(s.description || '') + '</textarea></div>' +
        '<div class="field field--full"><label>Hero image</label>' +
          '<input class="input" id="spHero" value="' + esc(s.heroImageUrl || '') + '" placeholder="https://…" />' +
          '<div style="display:flex;align-items:center;gap:10px;margin-top:8px">' +
            '<input type="file" id="spHeroFile" accept="image/png,image/jpeg,image/webp" style="display:none" />' +
            '<button type="button" class="btn btn--ghost btn--sm" id="spHeroUploadBtn">Upload image…</button>' +
            '<span class="label-sm" id="spHeroUploadStatus" style="color:var(--on-surface-variant)"></span>' +
          '</div>' +
          (s.heroImageUrl
            ? '<img id="spHeroPreview" src="' + esc(s.heroImageUrl) + '" style="max-width:200px;max-height:120px;border-radius:8px;margin-top:8px;display:block" />'
            : '<img id="spHeroPreview" style="max-width:200px;max-height:120px;border-radius:8px;margin-top:8px;display:none" />') +
        '</div>' +
      '</div>' +
      '<div class="modal__actions">' +
        '<button class="btn btn--ghost btn--sm" data-close>Cancel</button>' +
        '<button class="btn btn--primary" id="spSave">' + (isNew ? 'Create split' : 'Save changes') + '</button>' +
      '</div>'
    );
    wireClose(backdrop);

    $('#spHeroUploadBtn').addEventListener('click', function () {
      $('#spHeroFile').click();
    });

    $('#spHeroFile').addEventListener('change', function () {
      var file = this.files && this.files[0];
      if (!file) return;
      var status = $('#spHeroUploadStatus');
      status.textContent = 'Uploading…';
      auth.uploadImage(file).then(function (result) {
        if (!toastOnFailure(result, 'Could not upload image.')) { status.textContent = ''; return; }
        var url = result.data && result.data.url;
        $('#spHero').value = url || '';
        var preview = $('#spHeroPreview');
        if (url) { preview.src = url; preview.style.display = 'block'; }
        status.textContent = 'Uploaded.';
        toast('Image uploaded.');
      });
    });

    $('#spSave').addEventListener('click', function () {
      var payload = {
        splitId: isNew ? null : s.splitId,
        name: $('#spName').value.trim(),
        category: $('#spCategory').value,
        level: $('#spLevel').value,
        durationDays: num($('#spDuration').value),
        description: $('#spDesc').value.trim(),
        heroImageUrl: $('#spHero').value.trim(),
        recommendedGoal: $('#spGoal').value || null,
        visibility: $('#spVisibility').value,
        sortOrder: s.sortOrder || 0
      };
      if (!payload.name) { toast('Give the split a name first', true); return; }
      auth.saveSplit(payload).then(function (result) {
        if (!toastOnFailure(result, 'Could not save split.')) return;
        toast((result.data && result.data.message) || 'Split saved.');
        closeModal();
        loadSplits().then(function () {
          if (isNew && result.data && result.data.id) openSplitDaysEditor(result.data.id);
        });
      });
    });
  }

  /* ----- Days + exercise-prescription editor ----- */
  function openSplitDaysEditor(splitId) {
    var detail = null;
    var activeDayId = null; /* null when a brand-new, unsaved day is selected */
    var draftDay = null;

    var showAllExercises = false;

    var backdrop = openModal(
      modalHead('Manage days') +
      '<div class="modal__actions" style="justify-content:flex-start;margin-bottom:8px;">' +
        '<button class="btn btn--ghost btn--sm" id="splitAllExercisesToggle">All exercises in this split</button>' +
      '</div>' +
      '<div id="splitAllExercisesPanel" style="display:none"></div>' +
      '<div class="week-tabs" id="splitDayTabs"></div>' +
      '<div id="splitDayBody"></div>' +
      '<div class="modal__actions">' +
        '<button class="btn btn--ghost btn--sm" data-close>Close</button>' +
      '</div>',
      true
    );
    wireClose(backdrop);

    $('#splitAllExercisesToggle').addEventListener('click', function () {
      showAllExercises = !showAllExercises;
      renderAllExercisesPanel();
    });

    function renderAllExercisesPanel() {
      var panel = $('#splitAllExercisesPanel');
      var tabs = $('#splitDayTabs');
      var body = $('#splitDayBody');
      $('#splitAllExercisesToggle').textContent = showAllExercises ? 'Hide all exercises' : 'All exercises in this split';

      if (!showAllExercises) {
        panel.style.display = 'none';
        tabs.style.display = '';
        body.style.display = '';
        return;
      }
      tabs.style.display = 'none';
      body.style.display = 'none';
      panel.style.display = '';

      var byDay = {};
      detail.dayExercises.forEach(function (ex) {
        (byDay[ex.splitDayId] = byDay[ex.splitDayId] || []).push(ex);
      });

      if (!detail.days.length) {
        panel.innerHTML = '<div class="empty-state" style="padding:24px"><div class="body-sm">No days yet.</div></div>';
        return;
      }

      panel.innerHTML = detail.days.map(function (d) {
        var rows = (byDay[d.splitDayId] || []).sort(function (a, b) { return a.sortOrder - b.sortOrder; });
        var heading = 'Day ' + d.dayIndex + (d.title ? ' — ' + esc(d.title) : '') + (d.isRestDay ? ' (rest)' : '');
        var rowsHtml = rows.length
          ? rows.map(function (ex) {
              return '<div class="meal-slot" style="padding:8px 12px;">' +
                '<span class="body-sm">' + esc(ex.exerciseName) + '</span>' +
                '<span class="label-sm" style="color:var(--on-surface-variant);margin-left:8px;">' +
                  ex.targetSets + ' × ' + ex.targetRepsLow + '–' + ex.targetRepsHigh + '</span>' +
              '</div>';
            }).join('')
          : '<p class="body-sm" style="color:var(--on-surface-variant);padding:0 12px;">No exercises on this day.</p>';
        return '<div class="eyebrow" style="margin-top:16px;">' + heading + '</div>' + rowsHtml;
      }).join('');
    }

    function load() {
      return auth.getSplitDetail(splitId).then(function (result) {
        if (!toastOnFailure(result, 'Could not load the split.')) { closeModal(); return; }
        detail = result.data;
        detail.days.sort(function (a, b) { return a.dayIndex - b.dayIndex; });
        if (draftDay) {
          renderTabs();
          renderDayBody();
          renderAllExercisesPanel();
          return;
        }
        if (!activeDayId && detail.days.length) activeDayId = detail.days[0].splitDayId;
        if (activeDayId && !detail.days.some(function (d) { return d.splitDayId === activeDayId; })) {
          activeDayId = detail.days.length ? detail.days[0].splitDayId : null;
        }
        renderTabs();
        renderDayBody();
        renderAllExercisesPanel();
      });
    }

    function renderTabs() {
      var tabs = detail.days.map(function (d) {
        var isActive = !draftDay && d.splitDayId === activeDayId;
        return '<button class="week-tab' + (isActive ? ' is-active' : '') + '" data-day-id="' + d.splitDayId + '">' +
          'Day ' + d.dayIndex + (d.isRestDay ? ' · rest' : '') + '</button>';
      }).join('');
      tabs += '<button class="week-tab' + (draftDay ? ' is-active' : '') + '" id="addDayTab">+ Add day</button>';
      $('#splitDayTabs').innerHTML = tabs;

      $$('#splitDayTabs [data-day-id]').forEach(function (b) {
        b.addEventListener('click', function () {
          draftDay = null;
          activeDayId = b.getAttribute('data-day-id');
          renderTabs();
          renderDayBody();
        });
      });
      $('#addDayTab').addEventListener('click', function () {
        var nextIndex = detail.days.reduce(function (m, d) { return Math.max(m, d.dayIndex); }, 0) + 1;
        draftDay = { splitDayId: null, splitId: splitId, dayIndex: nextIndex, title: '', focusLabel: '', estimatedMinutes: 45, isRestDay: false };
        renderTabs();
        renderDayBody();
      });
    }

    function currentDay() {
      if (draftDay) return draftDay;
      return detail.days.find(function (d) { return d.splitDayId === activeDayId; }) || null;
    }

    function renderDayBody() {
      var day = currentDay();
      if (!day) {
        $('#splitDayBody').innerHTML = '<div class="empty-state" style="padding:24px"><div class="body-sm">No days yet — add one to get started.</div></div>';
        return;
      }

      var dayExercises = day.splitDayId
        ? detail.dayExercises.filter(function (e) { return e.splitDayId === day.splitDayId; }).sort(function (a, b) { return a.sortOrder - b.sortOrder; })
        : [];

      $('#splitDayBody').innerHTML =
        '<div class="form-grid" style="margin-top:16px;">' +
          '<div class="field field--full"><label>Title</label><input class="input" id="dayTitle" value="' + esc(day.title) + '" placeholder="Push — Chest, Shoulders, Triceps" /></div>' +
          '<div class="field"><label>Focus label</label><input class="input" id="dayFocus" value="' + esc(day.focusLabel || '') + '" placeholder="Chest & shoulders" /></div>' +
          '<div class="field"><label>Estimated minutes</label><input class="input" type="number" id="dayMinutes" value="' + day.estimatedMinutes + '" /></div>' +
          '<div class="field" style="flex-direction:row;align-items:center;gap:12px;padding-top:22px;">' +
            '<label class="switch"><input type="checkbox" id="dayRest"' + (day.isRestDay ? ' checked' : '') + ' /><span class="track"></span></label>' +
            '<span class="label-sm">Rest day</span>' +
          '</div>' +
        '</div>' +
        '<div class="modal__actions" style="justify-content:flex-start;gap:8px;">' +
          '<button class="btn btn--primary btn--sm" id="daySave">' + (day.splitDayId ? 'Save day' : 'Add day') + '</button>' +
          (day.splitDayId ? '<button class="btn btn--danger btn--sm" id="dayDelete">Delete day</button>' : '') +
        '</div>' +
        (day.splitDayId ? (
          '<div class="eyebrow" style="margin-top:20px;">Exercises</div>' +
          '<div id="dayExerciseRows"></div>' +
          '<div class="meal-slot" id="dayExerciseAddRow"></div>'
        ) : '<p class="body-sm" style="margin-top:12px;">Save the day first, then add exercises to it.</p>');

      $('#daySave').addEventListener('click', function () {
        var payload = {
          splitDayId: day.splitDayId,
          splitId: splitId,
          dayIndex: day.dayIndex,
          title: $('#dayTitle').value.trim(),
          focusLabel: $('#dayFocus').value.trim(),
          estimatedMinutes: num($('#dayMinutes').value),
          isRestDay: $('#dayRest').checked
        };
        if (!payload.title && !payload.isRestDay) { toast('Give the day a title, or mark it a rest day', true); return; }
        auth.saveSplitDay(payload).then(function (result) {
          if (!toastOnFailure(result, 'Could not save day.')) return;
          toast((result.data && result.data.message) || 'Day saved.');
          draftDay = null;
          if (result.data && result.data.id) activeDayId = result.data.id;
          load();
          loadSplits();
        });
      });

      var deleteBtn = $('#dayDelete');
      if (deleteBtn) {
        deleteBtn.addEventListener('click', function () {
          confirmDelete('Delete this day?', 'Every exercise prescription on it is removed too.', function () {
            auth.deleteSplitDay(day.splitDayId).then(function (result) {
              if (!toastOnFailure(result, 'Could not delete day.')) return;
              toast((result.data && result.data.message) || 'Day removed.');
              activeDayId = null;
              load();
              loadSplits();
            });
          });
        });
      }

      if (day.splitDayId) renderExerciseRows(day, dayExercises);
    }

    function renderExerciseRows(day, dayExercises) {
      $('#dayExerciseRows').innerHTML = dayExercises.map(function (ex) {
        return (
          '<div class="meal-slot" data-exercise-row="' + ex.splitDayExerciseId + '">' +
            '<div class="meal-slot__grid">' +
              '<div class="field field--full"><label>Exercise</label><select class="select" data-ex-field="exerciseId">' + exerciseOptionHtml(ex.exerciseId) + '</select></div>' +
              '<div class="field"><label>Sets</label><input class="input" type="number" min="1" data-ex-field="targetSets" value="' + ex.targetSets + '" /></div>' +
              '<div class="field"><label>Reps low</label><input class="input" type="number" min="1" data-ex-field="targetRepsLow" value="' + ex.targetRepsLow + '" /></div>' +
              '<div class="field"><label>Reps high</label><input class="input" type="number" min="1" data-ex-field="targetRepsHigh" value="' + ex.targetRepsHigh + '" /></div>' +
              '<button class="icon-btn" data-save-exercise-row title="Save">' +
                '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 13l4 4L19 7"/></svg>' +
              '</button>' +
              '<button class="icon-btn icon-btn--danger" data-remove-exercise-row title="Remove">' +
                '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 6l12 12M18 6 6 18"/></svg>' +
              '</button>' +
            '</div>' +
          '</div>'
        );
      }).join('');

      $$('[data-exercise-row]').forEach(function (row) {
        var id = row.getAttribute('data-exercise-row');
        var ex = dayExercises.find(function (e) { return e.splitDayExerciseId === id; });
        $('[data-save-exercise-row]', row).addEventListener('click', function () {
          var payload = {
            splitDayExerciseId: id,
            splitDayId: day.splitDayId,
            exerciseId: $('[data-ex-field="exerciseId"]', row).value,
            sortOrder: ex.sortOrder,
            targetSets: num($('[data-ex-field="targetSets"]', row).value),
            targetRepsLow: num($('[data-ex-field="targetRepsLow"]', row).value),
            targetRepsHigh: num($('[data-ex-field="targetRepsHigh"]', row).value)
          };
          auth.saveSplitDayExercise(payload).then(function (result) {
            if (!toastOnFailure(result, 'Could not save exercise.')) return;
            toast('Exercise updated.');
            load();
            loadSplits();
          });
        });
        $('[data-remove-exercise-row]', row).addEventListener('click', function () {
          confirmDelete('Remove ' + ex.exerciseName + '?', 'It comes off this day only.', function () {
            auth.deleteSplitDayExercise(id).then(function (result) {
              if (!toastOnFailure(result, 'Could not remove exercise.')) return;
              toast('Exercise removed.');
              load();
              loadSplits();
            });
          });
        });
      });

      if (!exercisesCache.length) {
        // Only reached when the library itself is unavailable - not when a
        // filter happens to match nothing (the picker below handles that).
        $('#dayExerciseAddRow').innerHTML =
          '<p class="body-sm">No exercises are available to add. Add some in the Exercises view first.</p>';
        return;
      }

      $('#dayExerciseAddRow').innerHTML =
        '<div class="meal-slot__grid">' +
          '<div class="field field--full"><label>Search exercises</label>' +
            '<input class="input" id="addExSearch" placeholder="Filter by name…" autocomplete="off" /></div>' +
          '<div class="field"><label>Muscle group</label>' +
            '<select class="select" id="addExMuscle"><option value="">Any muscle group</option>' +
              MUSCLE_GROUPS.map(function (g) {
                return '<option value="' + g + '">' + g.charAt(0).toUpperCase() + g.slice(1) + '</option>';
              }).join('') +
            '</select></div>' +
          '<div class="field field--full"><label>Exercise <span id="addExCount"></span></label>' +
            '<select class="select" id="addExSelect"></select></div>' +
          '<div class="field"><label>Sets</label><input class="input" type="number" min="1" id="addExSets" value="3" /></div>' +
          '<div class="field"><label>Reps low</label><input class="input" type="number" min="1" id="addExRepsLow" value="8" /></div>' +
          '<div class="field"><label>Reps high</label><input class="input" type="number" min="1" id="addExRepsHigh" value="12" /></div>' +
          '<button class="btn btn--secondary btn--sm" id="addExBtn">Add</button>' +
        '</div>';

      function refreshAddExerciseOptions() {
        var html = exerciseOptionHtml(null, $('#addExSearch').value, $('#addExMuscle').value);
        $('#addExSelect').innerHTML = html || '<option value="">No exercises match this filter</option>';
        var count = html ? $('#addExSelect').options.length : 0;
        $('#addExCount').textContent = count ? '(' + count + ')' : '';
        $('#addExBtn').disabled = count === 0;
      }

      refreshAddExerciseOptions();
      $('#addExSearch').addEventListener('input', refreshAddExerciseOptions);
      $('#addExMuscle').addEventListener('change', refreshAddExerciseOptions);

      $('#addExBtn').addEventListener('click', function () {
        var payload = {
          splitDayExerciseId: null,
          splitDayId: day.splitDayId,
          exerciseId: $('#addExSelect').value,
          sortOrder: dayExercises.length,
          targetSets: num($('#addExSets').value),
          targetRepsLow: num($('#addExRepsLow').value),
          targetRepsHigh: num($('#addExRepsHigh').value)
        };
        auth.saveSplitDayExercise(payload).then(function (result) {
          if (!toastOnFailure(result, 'Could not add exercise.')) return;
          toast('Exercise added.');
          load();
          loadSplits();
        });
      });
    }

    load();
  }

  /* ----- Assigning a split to specific clients ----- */
  function openSplitAssignments(splitId) {
    var split = splitsCache.find(function (x) { return x.splitId === splitId; });
    if (!split) return;

    var assignments = [];
    var users = [];
    var search = '';

    var backdrop = openModal(
      modalHead('Assign "' + split.name + '"') +
      '<p class="body-sm" style="margin:0 0 12px;color:var(--on-surface-variant)">' +
        'Assigned clients can see this split in the app. Tick "make it their active split" to set it as their program right away.' +
      '</p>' +
      '<div class="eyebrow">Assigned clients</div>' +
      '<div id="assignList"></div>' +
      '<div class="eyebrow" style="margin:20px 0 10px;">Add a client</div>' +
      '<div class="form-grid">' +
        '<div class="field field--full"><label>Search users</label>' +
          '<input class="input" id="assignSearch" placeholder="Name or email…" /></div>' +
        '<div class="field field--full"><label>Client (plan shown so you can see who is paying)</label>' +
          '<select class="select" id="assignUser"></select></div>' +
        '<div class="field field--full" style="flex-direction:row;align-items:center;gap:12px;">' +
          '<label class="switch"><input type="checkbox" id="assignActive" /><span class="track"></span></label>' +
          '<span class="label-sm">Make it their active split</span>' +
        '</div>' +
      '</div>' +
      '<div id="assignHint"></div>' +
      '<div class="modal__actions">' +
        '<button class="btn btn--ghost btn--sm" data-close>Close</button>' +
        '<button class="btn btn--primary" id="assignSave">Assign</button>' +
      '</div>',
      true
    );
    wireClose(backdrop);

    function planLabel(x) {
      if (x.subscriptionStatus === 'Active' && x.activePlanCode) {
        return x.activePlanCode + (x.billingCycle ? ' · ' + x.billingCycle : '');
      }
      if (x.activePlanCode) return x.activePlanCode + ' · ' + (x.subscriptionStatus || 'inactive');
      return x.accountTier === 'Guest' ? 'No account' : 'No paid plan';
    }

    function renderUserOptions() {
      var assignedIds = assignments.map(function (a) { return a.userId; });
      var q = search.toLowerCase();
      var available = users.filter(function (u) {
        if (assignedIds.indexOf(u.userId) > -1) return false;
        if (!q) return true;
        return ((u.displayName || '') + ' ' + (u.email || '')).toLowerCase().indexOf(q) > -1;
      });

      var sel = $('#assignUser');
      sel.innerHTML = available.map(function (u) {
        return '<option value="' + u.userId + '">' +
          esc((u.displayName || u.email || u.userId) + ' — ' + planLabel(u)) + '</option>';
      }).join('');

      $('#assignHint').innerHTML = available.length ? '' :
        '<p class="body-sm" style="color:var(--on-surface-variant)">' +
          (users.length ? 'No matching unassigned clients.' : 'No users available (the user list needs users.read).') +
        '</p>';
      $('#assignSave').disabled = !available.length;
    }

    function renderAssignments() {
      $('#assignList').innerHTML = assignments.length ? assignments.map(function (a) {
        return (
          '<div class="activity-item">' +
            '<div class="body-md" style="font-size:13.5px;flex:1">' +
              '<b>' + esc(a.displayName || a.email || a.userId) + '</b>' +
              '<div class="row-sub">' + esc(a.email || '') + ' · ' + esc(planLabel(a)) +
                (a.isActive ? ' · <span class="chip chip--accent">Active split</span>' : '') +
              '</div>' +
            '</div>' +
            '<button class="icon-btn icon-btn--danger" data-unassign="' + a.userId + '" title="Unassign">' +
              '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 6l12 12M18 6 6 18"/></svg>' +
            '</button>' +
          '</div>'
        );
      }).join('') : '<div class="empty-state" style="padding:16px"><div class="body-sm">Not assigned to anyone yet.</div></div>';

      $$('[data-unassign]').forEach(function (b) {
        b.addEventListener('click', function () {
          var userId = b.getAttribute('data-unassign');
          var a = assignments.find(function (x) { return x.userId === userId; });
          if (!a) return;
          confirmDelete('Unassign ' + (a.displayName || a.email || 'this client') + '?',
            'They lose access; if it was their active split it is cleared.', function () {
              auth.removeSplitAssignment(splitId, userId).then(function (result) {
                if (!toastOnFailure(result, 'Could not unassign.')) return;
                toast('Client unassigned.');
                load();
                loadSplits();
              });
            });
        });
      });
    }

    function load() {
      return Promise.all([
        auth.getSplitAssignments(splitId),
        auth.getUsers('', 200)
      ]).then(function (results) {
        var assignmentResult = results[0];
        var userResult = results[1];
        if (!toastOnFailure(assignmentResult, 'Could not load assignments.')) { closeModal(); return; }
        assignments = assignmentResult.data || [];
        users = userResult && userResult.ok ? (userResult.data || []) : [];
        renderAssignments();
        renderUserOptions();
      });
    }

    $('#assignSearch').addEventListener('input', function () {
      search = $('#assignSearch').value.trim();
      renderUserOptions();
    });

    $('#assignSave').addEventListener('click', function () {
      var userId = $('#assignUser').value;
      if (!userId) { toast('Pick a client first', true); return; }
      auth.assignSplit(splitId, userId, $('#assignActive').checked).then(function (result) {
        if (!toastOnFailure(result, 'Could not assign split.')) return;
        toast((result.data && result.data.message) || 'Split assigned.');
        $('#assignActive').checked = false;
        load();
        loadSplits();
      });
    });

    load();
  }

  /* ================================================================
     DIET PLANS — weekly/monthly meal templates (structural clone of Splits)
     ================================================================ */
  var dietPlanPeriodFilter = 'all';

  function renderDietPlanFilters() {
    var sel = $('#dietPlanPeriodFilter');
    if (!sel) return;
    sel.innerHTML = '<option value="all">All periods</option>' +
      DIET_PLAN_PERIODS.map(function (p) {
        return '<option value="' + p + '"' + (dietPlanPeriodFilter === p ? ' selected' : '') + '>' + p + '</option>';
      }).join('');
  }

  function loadDietPlans() {
    return auth.getDietPlans().then(function (result) {
      if (!toastOnFailure(result, 'Could not load diet plans.')) return;
      dietPlansCache = result.data || [];
      renderDietPlans();
    });
  }

  function renderDietPlans() {
    renderDietPlanFilters();
    var plans = dietPlansCache.filter(function (p) {
      return dietPlanPeriodFilter === 'all' || p.periodType === dietPlanPeriodFilter;
    });

    var grid = $('#dietPlanGrid');
    if (!grid) return;
    if (!plans.length) {
      grid.innerHTML =
        '<div class="card empty-state" style="grid-column:1/-1">' +
          '<img src="assets/img/mascot/ready.png" alt="Mascot ready" />' +
          '<div class="headline-sm">No diet plans yet</div>' +
          '<p class="body-sm">Create a plan, then add its days and meals.</p>' +
        '</div>';
      return;
    }

    grid.innerHTML = plans.map(function (p) {
      /* A trainer only ever gets the controls for plans they own (canManage is
         computed server-side from ownership + content.diet_plans.manage_all). */
      var actions = p.canManage ? (
        '<button class="icon-btn" data-edit-diet-plan="' + p.dietPlanId + '" title="Edit details">' +
          '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 3a2.8 2.8 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3Z"/></svg>' +
        '</button>' +
        '<button class="icon-btn icon-btn--danger" data-del-diet-plan="' + p.dietPlanId + '" title="Delete">' +
          '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 7h16M9 7V4h6v3m-8 0 1 13h8l1-13"/></svg>' +
        '</button>'
      ) : '';

      var foot = '';
      if (p.canManage) {
        foot += '<button class="btn btn--secondary btn--sm" data-manage-diet-days="' + p.dietPlanId + '">Manage days</button>';
        if (has('content.diet_plans.assign')) {
          foot += '<button class="btn btn--primary btn--sm" data-assign-diet-plan="' + p.dietPlanId + '">Assign to clients</button>';
        }
      }

      return (
        '<article class="card mp-card">' +
          '<div class="mp-card__head">' +
            '<span class="chip chip--accent">' + esc(p.periodType) + '</span>' +
            (p.isSystemDefault ? '<span class="chip">System</span>' : '') +
            '<span class="spacer"></span>' +
            '<div class="row-actions">' + actions + '</div>' +
          '</div>' +
          '<div>' +
            '<div class="headline-sm">' + esc(p.name) + '</div>' +
            '<div class="mp-card__desc" style="margin-top:6px">' + esc(p.description || '') + '</div>' +
          '</div>' +
          '<div class="mp-card__targets">' +
            '<span class="chip">' + esc(p.visibility || 'Public') + '</span>' +
            '<span class="chip">' + p.durationDays + ' days</span>' +
            '<span class="chip">' + p.dayCount + ' scheduled</span>' +
            '<span class="chip">' + p.mealCount + ' meals</span>' +
            (p.ownerUsername ? '<span class="chip">by ' + esc(p.ownerUsername) + '</span>' : '') +
            (p.assignedUserCount ? '<span class="chip chip--gold">' + p.assignedUserCount + ' assigned</span>' : '') +
            (p.activeUserCount ? '<span class="chip chip--accent">' + p.activeUserCount + ' active users</span>' : '') +
          '</div>' +
          (foot ? '<div class="mp-card__foot">' + foot + '</div>' : '') +
        '</article>'
      );
    }).join('');

    $$('[data-edit-diet-plan]').forEach(function (b) {
      b.addEventListener('click', function () { openDietPlanEditor(b.getAttribute('data-edit-diet-plan')); });
    });
    $$('[data-manage-diet-days]').forEach(function (b) {
      b.addEventListener('click', function () { openDietPlanDaysEditor(b.getAttribute('data-manage-diet-days')); });
    });
    $$('[data-assign-diet-plan]').forEach(function (b) {
      b.addEventListener('click', function () { openDietPlanAssignments(b.getAttribute('data-assign-diet-plan')); });
    });
    $$('[data-del-diet-plan]').forEach(function (b) {
      b.addEventListener('click', function () {
        var p = dietPlansCache.find(function (x) { return x.dietPlanId === b.getAttribute('data-del-diet-plan'); });
        if (!p) return;
        confirmDelete('Delete "' + p.name + '"?', 'Refused while any user has this plan active.', function () {
          auth.deleteDietPlan(p.dietPlanId).then(function (result) {
            if (!toastOnFailure(result, 'Could not delete diet plan.')) return;
            toast((result.data && result.data.message) || 'Diet plan deleted.');
            loadDietPlans();
          });
        });
      });
    });
  }

  function openDietPlanEditor(dietPlanId) {
    var isNew = !dietPlanId;
    var p = isNew
      ? { name: '', periodType: DIET_PLAN_PERIODS[0], durationDays: 7, description: '', heroImageUrl: '', visibility: 'Private', sortOrder: 0 }
      : dietPlansCache.find(function (x) { return x.dietPlanId === dietPlanId; });
    if (!isNew && !p) return;

    var backdrop = openModal(
      modalHead(isNew ? 'New diet plan' : 'Edit diet plan') +
      '<div class="form-grid">' +
        '<div class="field field--full"><label>Name</label>' +
          '<input class="input" id="dpName" value="' + esc(p.name) + '" placeholder="High Protein Cut — 7 Day" /></div>' +
        '<div class="field"><label>Period</label>' +
          '<select class="select" id="dpPeriod">' +
            DIET_PLAN_PERIODS.map(function (t) { return '<option' + (p.periodType === t ? ' selected' : '') + '>' + t + '</option>'; }).join('') +
          '</select></div>' +
        '<div class="field"><label>Visibility</label>' +
          '<select class="select" id="dpVisibility">' +
            SPLIT_VISIBILITIES.map(function (v) { return '<option' + (p.visibility === v ? ' selected' : '') + '>' + v + '</option>'; }).join('') +
          '</select></div>' +
        '<div class="field field--full"><span class="label-sm" style="color:var(--on-surface-variant)">' +
          'Private: only you. Public: every app user. Shared: only the clients you assign it to.' +
        '</span></div>' +
        '<div class="field"><label>Duration (days)</label><input class="input" type="number" min="1" max="31" id="dpDuration" value="' + p.durationDays + '" /></div>' +
        '<div class="field field--full"><label>Description</label>' +
          '<textarea class="textarea" id="dpDesc" placeholder="Who is this plan for?">' + esc(p.description || '') + '</textarea></div>' +
        '<div class="field field--full"><label>Hero image URL</label><input class="input" id="dpHero" value="' + esc(p.heroImageUrl || '') + '" placeholder="https://…" /></div>' +
      '</div>' +
      '<div class="modal__actions">' +
        '<button class="btn btn--ghost btn--sm" data-close>Cancel</button>' +
        '<button class="btn btn--primary" id="dpSave">' + (isNew ? 'Create plan' : 'Save changes') + '</button>' +
      '</div>'
    );
    wireClose(backdrop);

    $('#dpSave').addEventListener('click', function () {
      var payload = {
        dietPlanId: isNew ? null : p.dietPlanId,
        name: $('#dpName').value.trim(),
        periodType: $('#dpPeriod').value,
        durationDays: num($('#dpDuration').value),
        description: $('#dpDesc').value.trim(),
        heroImageUrl: $('#dpHero').value.trim(),
        visibility: $('#dpVisibility').value,
        sortOrder: p.sortOrder || 0
      };
      if (!payload.name) { toast('Give the plan a name first', true); return; }
      auth.saveDietPlan(payload).then(function (result) {
        if (!toastOnFailure(result, 'Could not save diet plan.')) return;
        toast((result.data && result.data.message) || 'Diet plan saved.');
        closeModal();
        loadDietPlans().then(function () {
          if (isNew && result.data && result.data.id) openDietPlanDaysEditor(result.data.id);
        });
      });
    });
  }

  /* ----- Days + meal-slot editor ----- */
  function openDietPlanDaysEditor(dietPlanId) {
    var detail = null;
    var activeDayId = null; /* null when a brand-new, unsaved day is selected */
    var draftDay = null;

    var backdrop = openModal(
      modalHead('Manage days') +
      '<div class="week-tabs" id="dietPlanDayTabs"></div>' +
      '<div id="dietPlanDayBody"></div>' +
      '<div class="modal__actions">' +
        '<button class="btn btn--ghost btn--sm" data-close>Close</button>' +
      '</div>',
      true
    );
    wireClose(backdrop);

    function load() {
      return auth.getDietPlanDetail(dietPlanId).then(function (result) {
        if (!toastOnFailure(result, 'Could not load the diet plan.')) { closeModal(); return; }
        detail = result.data;
        detail.days.sort(function (a, b) { return a.dayIndex - b.dayIndex; });
        if (draftDay) {
          renderTabs();
          renderDayBody();
          return;
        }
        if (!activeDayId && detail.days.length) activeDayId = detail.days[0].dietPlanDayId;
        if (activeDayId && !detail.days.some(function (d) { return d.dietPlanDayId === activeDayId; })) {
          activeDayId = detail.days.length ? detail.days[0].dietPlanDayId : null;
        }
        renderTabs();
        renderDayBody();
      });
    }

    function renderTabs() {
      var tabs = detail.days.map(function (d) {
        var isActive = !draftDay && d.dietPlanDayId === activeDayId;
        return '<button class="week-tab' + (isActive ? ' is-active' : '') + '" data-day-id="' + d.dietPlanDayId + '">' +
          'Day ' + d.dayIndex + '</button>';
      }).join('');
      tabs += '<button class="week-tab' + (draftDay ? ' is-active' : '') + '" id="addDietDayTab">+ Add day</button>';
      $('#dietPlanDayTabs').innerHTML = tabs;

      $$('#dietPlanDayTabs [data-day-id]').forEach(function (b) {
        b.addEventListener('click', function () {
          draftDay = null;
          activeDayId = b.getAttribute('data-day-id');
          renderTabs();
          renderDayBody();
        });
      });
      $('#addDietDayTab').addEventListener('click', function () {
        var nextIndex = detail.days.reduce(function (m, d) { return Math.max(m, d.dayIndex); }, 0) + 1;
        draftDay = { dietPlanDayId: null, dietPlanId: dietPlanId, dayIndex: nextIndex, title: '' };
        renderTabs();
        renderDayBody();
      });
    }

    function currentDay() {
      if (draftDay) return draftDay;
      return detail.days.find(function (d) { return d.dietPlanDayId === activeDayId; }) || null;
    }

    function renderDayBody() {
      var day = currentDay();
      if (!day) {
        $('#dietPlanDayBody').innerHTML = '<div class="empty-state" style="padding:24px"><div class="body-sm">No days yet — add one to get started.</div></div>';
        return;
      }

      var dayMeals = day.dietPlanDayId
        ? detail.meals.filter(function (m) { return m.dietPlanDayId === day.dietPlanDayId; }).sort(function (a, b) { return a.sortOrder - b.sortOrder; })
        : [];

      $('#dietPlanDayBody').innerHTML =
        '<div class="form-grid" style="margin-top:16px;">' +
          '<div class="field field--full"><label>Title</label><input class="input" id="dietDayTitle" value="' + esc(day.title || '') + '" placeholder="High protein reset" /></div>' +
        '</div>' +
        '<div class="modal__actions" style="justify-content:flex-start;gap:8px;">' +
          '<button class="btn btn--primary btn--sm" id="dietDaySave">' + (day.dietPlanDayId ? 'Save day' : 'Add day') + '</button>' +
          (day.dietPlanDayId ? '<button class="btn btn--danger btn--sm" id="dietDayDelete">Delete day</button>' : '') +
        '</div>' +
        (day.dietPlanDayId ? (
          '<div class="eyebrow" style="margin-top:20px;">Meals</div>' +
          '<div id="dietDayMealRows"></div>' +
          '<div class="meal-slot" id="dietDayMealAddRow"></div>'
        ) : '<p class="body-sm" style="margin-top:12px;">Save the day first, then add meals to it.</p>');

      $('#dietDaySave').addEventListener('click', function () {
        var payload = {
          dietPlanDayId: day.dietPlanDayId,
          dietPlanId: dietPlanId,
          dayIndex: day.dayIndex,
          title: $('#dietDayTitle').value.trim() || null
        };
        auth.saveDietPlanDay(payload).then(function (result) {
          if (!toastOnFailure(result, 'Could not save day.')) return;
          toast((result.data && result.data.message) || 'Day saved.');
          draftDay = null;
          if (result.data && result.data.id) activeDayId = result.data.id;
          load();
          loadDietPlans();
        });
      });

      var deleteDietDayBtn = $('#dietDayDelete');
      if (deleteDietDayBtn) {
        deleteDietDayBtn.addEventListener('click', function () {
          confirmDelete('Delete this day?', 'Every meal slot on it is removed too.', function () {
            auth.deleteDietPlanDay(day.dietPlanDayId).then(function (result) {
              if (!toastOnFailure(result, 'Could not delete day.')) return;
              toast((result.data && result.data.message) || 'Day removed.');
              activeDayId = null;
              load();
              loadDietPlans();
            });
          });
        });
      }

      if (day.dietPlanDayId) renderMealRows(day, dayMeals);
    }

    function renderMealRows(day, dayMeals) {
      $('#dietDayMealRows').innerHTML = dayMeals.map(function (m) {
        return (
          '<div class="meal-slot" data-meal-row="' + m.dietPlanMealId + '">' +
            '<div class="meal-slot__grid">' +
              '<div class="field field--full"><label>Meal</label><select class="select" data-meal-field="mealSuggestionId">' + mealOptionHtml(m.mealSuggestionId) + '</select></div>' +
              '<div class="field"><label>Meal type</label>' +
                '<select class="select" data-meal-field="mealType">' +
                  MEAL_TYPES.map(function (t) { return '<option' + (m.mealType === t ? ' selected' : '') + '>' + t + '</option>'; }).join('') +
                '</select></div>' +
              '<button class="icon-btn" data-save-meal-row title="Save">' +
                '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 13l4 4L19 7"/></svg>' +
              '</button>' +
              '<button class="icon-btn icon-btn--danger" data-remove-meal-row title="Remove">' +
                '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 6l12 12M18 6 6 18"/></svg>' +
              '</button>' +
            '</div>' +
          '</div>'
        );
      }).join('');

      $$('[data-meal-row]').forEach(function (row) {
        var id = row.getAttribute('data-meal-row');
        var m = dayMeals.find(function (x) { return x.dietPlanMealId === id; });
        $('[data-save-meal-row]', row).addEventListener('click', function () {
          var payload = {
            dietPlanMealId: id,
            dietPlanDayId: day.dietPlanDayId,
            mealSuggestionId: $('[data-meal-field="mealSuggestionId"]', row).value,
            sortOrder: m.sortOrder,
            mealType: $('[data-meal-field="mealType"]', row).value
          };
          auth.saveDietPlanMeal(payload).then(function (result) {
            if (!toastOnFailure(result, 'Could not save meal.')) return;
            toast('Meal updated.');
            load();
            loadDietPlans();
          });
        });
        $('[data-remove-meal-row]', row).addEventListener('click', function () {
          confirmDelete('Remove ' + m.mealSuggestionTitle + '?', 'It comes off this day only.', function () {
            auth.deleteDietPlanMeal(id).then(function (result) {
              if (!toastOnFailure(result, 'Could not remove meal.')) return;
              toast('Meal removed.');
              load();
              loadDietPlans();
            });
          });
        });
      });

      if (!suggestionsCache.length) {
        $('#dietDayMealAddRow').innerHTML =
          '<p class="body-sm">No meal suggestions are available to add. Add some in the Meal Suggestions view first.</p>';
        return;
      }

      $('#dietDayMealAddRow').innerHTML =
        '<div class="meal-slot__grid">' +
          '<div class="field field--full"><label>Search meals</label>' +
            '<input class="input" id="addMealSearch" placeholder="Filter by name…" autocomplete="off" /></div>' +
          '<div class="field"><label>Meal type filter</label>' +
            '<select class="select" id="addMealFilter"><option value="">Any meal type</option>' +
              MEAL_TYPES.map(function (t) { return '<option value="' + t + '">' + t + '</option>'; }).join('') +
            '</select></div>' +
          '<div class="field field--full"><label>Meal <span id="addMealCount"></span></label>' +
            '<select class="select" id="addMealSelect"></select></div>' +
          '<div class="field"><label>Meal type for this slot</label>' +
            '<select class="select" id="addMealType">' +
              MEAL_TYPES.map(function (t) { return '<option>' + t + '</option>'; }).join('') +
            '</select></div>' +
          '<button class="btn btn--secondary btn--sm" id="addMealBtn">Add</button>' +
        '</div>';

      function refreshAddMealOptions() {
        var html = mealOptionHtml(null, $('#addMealSearch').value, $('#addMealFilter').value);
        $('#addMealSelect').innerHTML = html || '<option value="">No meals match this filter</option>';
        var count = html ? $('#addMealSelect').options.length : 0;
        $('#addMealCount').textContent = count ? '(' + count + ')' : '';
        $('#addMealBtn').disabled = count === 0;
      }

      refreshAddMealOptions();
      $('#addMealSearch').addEventListener('input', refreshAddMealOptions);
      $('#addMealFilter').addEventListener('change', refreshAddMealOptions);

      $('#addMealBtn').addEventListener('click', function () {
        var payload = {
          dietPlanMealId: null,
          dietPlanDayId: day.dietPlanDayId,
          mealSuggestionId: $('#addMealSelect').value,
          sortOrder: dayMeals.length,
          mealType: $('#addMealType').value
        };
        auth.saveDietPlanMeal(payload).then(function (result) {
          if (!toastOnFailure(result, 'Could not add meal.')) return;
          toast('Meal added.');
          load();
          loadDietPlans();
        });
      });
    }

    load();
  }

  /* ----- Assigning a diet plan to specific clients ----- */
  function openDietPlanAssignments(dietPlanId) {
    var plan = dietPlansCache.find(function (x) { return x.dietPlanId === dietPlanId; });
    if (!plan) return;

    var assignments = [];
    var users = [];
    var search = '';

    var backdrop = openModal(
      modalHead('Assign "' + plan.name + '"') +
      '<p class="body-sm" style="margin:0 0 12px;color:var(--on-surface-variant)">' +
        'Assigned clients can see this plan in the app. Tick "make it their active plan" to set it as their program right away.' +
      '</p>' +
      '<div class="eyebrow">Assigned clients</div>' +
      '<div id="dietAssignList"></div>' +
      '<div class="eyebrow" style="margin:20px 0 10px;">Add a client</div>' +
      '<div class="form-grid">' +
        '<div class="field field--full"><label>Search users</label>' +
          '<input class="input" id="dietAssignSearch" placeholder="Name or email…" /></div>' +
        '<div class="field field--full"><label>Client (plan shown so you can see who is paying)</label>' +
          '<select class="select" id="dietAssignUser"></select></div>' +
        '<div class="field field--full" style="flex-direction:row;align-items:center;gap:12px;">' +
          '<label class="switch"><input type="checkbox" id="dietAssignActive" /><span class="track"></span></label>' +
          '<span class="label-sm">Make it their active plan</span>' +
        '</div>' +
      '</div>' +
      '<div id="dietAssignHint"></div>' +
      '<div class="modal__actions">' +
        '<button class="btn btn--ghost btn--sm" data-close>Close</button>' +
        '<button class="btn btn--primary" id="dietAssignSave">Assign</button>' +
      '</div>',
      true
    );
    wireClose(backdrop);

    function planLabel(x) {
      if (x.subscriptionStatus === 'Active' && x.activePlanCode) {
        return x.activePlanCode + (x.billingCycle ? ' · ' + x.billingCycle : '');
      }
      if (x.activePlanCode) return x.activePlanCode + ' · ' + (x.subscriptionStatus || 'inactive');
      return x.accountTier === 'Guest' ? 'No account' : 'No paid plan';
    }

    function renderUserOptions() {
      var assignedIds = assignments.map(function (a) { return a.userId; });
      var q = search.toLowerCase();
      var available = users.filter(function (u) {
        if (assignedIds.indexOf(u.userId) > -1) return false;
        if (!q) return true;
        return ((u.displayName || '') + ' ' + (u.email || '')).toLowerCase().indexOf(q) > -1;
      });

      var sel = $('#dietAssignUser');
      sel.innerHTML = available.map(function (u) {
        return '<option value="' + u.userId + '">' +
          esc((u.displayName || u.email || u.userId) + ' — ' + planLabel(u)) + '</option>';
      }).join('');

      $('#dietAssignHint').innerHTML = available.length ? '' :
        '<p class="body-sm" style="color:var(--on-surface-variant)">' +
          (users.length ? 'No matching unassigned clients.' : 'No users available (the user list needs users.read).') +
        '</p>';
      $('#dietAssignSave').disabled = !available.length;
    }

    function renderAssignments() {
      $('#dietAssignList').innerHTML = assignments.length ? assignments.map(function (a) {
        return (
          '<div class="activity-item">' +
            '<div class="body-md" style="font-size:13.5px;flex:1">' +
              '<b>' + esc(a.displayName || a.email || a.userId) + '</b>' +
              '<div class="row-sub">' + esc(a.email || '') + ' · ' + esc(planLabel(a)) +
                (a.isActive ? ' · <span class="chip chip--accent">Active plan</span>' : '') +
              '</div>' +
            '</div>' +
            '<button class="icon-btn icon-btn--danger" data-diet-unassign="' + a.userId + '" title="Unassign">' +
              '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 6l12 12M18 6 6 18"/></svg>' +
            '</button>' +
          '</div>'
        );
      }).join('') : '<div class="empty-state" style="padding:16px"><div class="body-sm">Not assigned to anyone yet.</div></div>';

      $$('[data-diet-unassign]').forEach(function (b) {
        b.addEventListener('click', function () {
          var userId = b.getAttribute('data-diet-unassign');
          var a = assignments.find(function (x) { return x.userId === userId; });
          if (!a) return;
          confirmDelete('Unassign ' + (a.displayName || a.email || 'this client') + '?',
            'They lose access; if it was their active plan it is cleared.', function () {
              auth.removeDietPlanAssignment(dietPlanId, userId).then(function (result) {
                if (!toastOnFailure(result, 'Could not unassign.')) return;
                toast('Client unassigned.');
                load();
                loadDietPlans();
              });
            });
        });
      });
    }

    function load() {
      return Promise.all([
        auth.getDietPlanAssignments(dietPlanId),
        auth.getUsers('', 200)
      ]).then(function (results) {
        var assignmentResult = results[0];
        var userResult = results[1];
        if (!toastOnFailure(assignmentResult, 'Could not load assignments.')) { closeModal(); return; }
        assignments = assignmentResult.data || [];
        users = userResult && userResult.ok ? (userResult.data || []) : [];
        renderAssignments();
        renderUserOptions();
      });
    }

    $('#dietAssignSearch').addEventListener('input', function () {
      search = $('#dietAssignSearch').value.trim();
      renderUserOptions();
    });

    $('#dietAssignSave').addEventListener('click', function () {
      var userId = $('#dietAssignUser').value;
      if (!userId) { toast('Pick a client first', true); return; }
      auth.assignDietPlan(dietPlanId, userId, $('#dietAssignActive').checked).then(function (result) {
        if (!toastOnFailure(result, 'Could not assign diet plan.')) return;
        toast((result.data && result.data.message) || 'Diet plan assigned.');
        $('#dietAssignActive').checked = false;
        load();
        loadDietPlans();
      });
    });

    load();
  }

  /* ================================================================
     MEAL SUGGESTIONS — table CRUD
     ================================================================ */
  var suggestionQuery = '';
  var suggestionMonth = 0; /* 0 = all */

  function renderSuggestionFilters() {
    var sel = $('#suggestionMonthFilter');
    sel.innerHTML = '<option value="0">All months</option>' +
      MONTHS.map(function (m, i) {
        return '<option value="' + (i + 1) + '"' + (suggestionMonth === i + 1 ? ' selected' : '') + '>' + m + '</option>';
      }).join('');
  }

  function macroMini(m) {
    var total = (m.proteinG * 4) + (m.carbsG * 4) + (m.fatsG * 9) || 1;
    var p = Math.round((m.proteinG * 4 / total) * 100);
    var c = Math.round((m.carbsG * 4 / total) * 100);
    var f = Math.max(0, 100 - p - c);
    return (
      '<div class="mini-macro" title="P ' + p + '% · C ' + c + '% · F ' + f + '%">' +
        '<span style="width:' + p + '%;background:var(--macro-protein)"></span>' +
        '<span style="width:' + c + '%;background:var(--macro-carbs)"></span>' +
        '<span style="width:' + f + '%;background:var(--macro-fats)"></span>' +
      '</div>'
    );
  }

  function loadSuggestions() {
    return auth.getMealSuggestions({
      suggestedMonth: suggestionMonth || null,
      search: suggestionQuery || null
    }).then(function (result) {
      if (!toastOnFailure(result, 'Could not load meal suggestions.')) return;
      suggestionsCache = result.data || [];
      renderSuggestions();
    });
  }

  function renderSuggestions() {
    renderSuggestionFilters();
    var rows = suggestionsCache.slice().sort(function (a, b) { return (a.suggestedMonth || 99) - (b.suggestedMonth || 99); });

    var head =
      '<thead><tr>' +
        '<th>Meal</th><th>Type</th><th>Month</th><th class="num">Kcal</th>' +
        '<th class="num">P</th><th class="num">C</th><th class="num">F</th><th>Split</th><th></th>' +
      '</tr></thead>';

    var body = rows.map(function (s) {
      return (
        '<tr>' +
          '<td><div class="row-title">' + esc(s.title) + '</div><div class="row-sub">' + esc(s.description || '') + '</div></td>' +
          '<td><span class="chip">' + esc(s.mealType) + '</span></td>' +
          '<td class="label-sm">' + (s.suggestedMonth ? esc(MONTHS[s.suggestedMonth - 1]) : '—') + '</td>' +
          '<td class="num accent-text" style="font-weight:600">' + s.caloriesKcal + '</td>' +
          '<td class="num">' + s.proteinG + 'g</td>' +
          '<td class="num">' + s.carbsG + 'g</td>' +
          '<td class="num">' + s.fatsG + 'g</td>' +
          '<td>' + macroMini(s) + '</td>' +
          '<td><div class="row-actions">' +
            '<button class="icon-btn" data-edit-suggestion="' + s.mealSuggestionId + '" title="Edit">' +
              '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 3a2.8 2.8 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3Z"/></svg>' +
            '</button>' +
            '<button class="icon-btn icon-btn--danger" data-del-suggestion="' + s.mealSuggestionId + '" title="Delete">' +
              '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 7h16M9 7V4h6v3m-8 0 1 13h8l1-13"/></svg>' +
            '</button>' +
          '</div></td>' +
        '</tr>'
      );
    }).join('');

    $('#suggestionsTable').innerHTML = head + '<tbody>' +
      (body || '<tr><td colspan="9"><div class="empty-state"><img src="assets/img/mascot/resting.png" alt="" /><div class="headline-sm">Nothing matches</div><div class="body-sm">Try another search or month filter.</div></div></td></tr>') +
      '</tbody>';

    $$('[data-edit-suggestion]').forEach(function (b) {
      b.addEventListener('click', function () { openSuggestionEditor(b.getAttribute('data-edit-suggestion')); });
    });
    $$('[data-del-suggestion]').forEach(function (b) {
      b.addEventListener('click', function () {
        var s = suggestionsCache.find(function (x) { return x.mealSuggestionId === b.getAttribute('data-del-suggestion'); });
        if (!s) return;
        confirmDelete('Delete "' + s.title + '"?', 'It disappears from the app strip and the landing page.', function () {
          auth.deleteMealSuggestion(s.mealSuggestionId).then(function (result) {
            if (!toastOnFailure(result, 'Could not delete suggestion.')) return;
            toast((result.data && result.data.message) || 'Suggestion deleted.');
            loadSuggestions();
          });
        });
      });
    });
  }

  function openSuggestionEditor(id) {
    var isNew = !id;
    var s = isNew
      ? { title: '', mealType: 'Lunch', description: '', caloriesKcal: 400, proteinG: 30, carbsG: 40, fatsG: 12, suggestedMonth: new Date().getMonth() + 1, sortOrder: 0 }
      : suggestionsCache.find(function (x) { return x.mealSuggestionId === id; });
    if (!isNew && !s) return;

    var backdrop = openModal(
      modalHead(isNew ? 'New meal suggestion' : 'Edit suggestion') +
      '<div class="form-grid">' +
        '<div class="field field--full"><label>Title</label>' +
          '<input class="input" id="sgTitle" value="' + esc(s.title) + '" placeholder="Grilled Chicken Caesar Salad" /></div>' +
        '<div class="field"><label>Meal type</label>' +
          '<select class="select" id="sgType">' +
            MEAL_TYPES.map(function (t) { return '<option' + (s.mealType === t ? ' selected' : '') + '>' + t + '</option>'; }).join('') +
          '</select></div>' +
        '<div class="field"><label>Suggested month</label>' +
          '<select class="select" id="sgMonth">' +
            '<option value="0">Not tied to a month</option>' +
            MONTHS.map(function (m, i) { return '<option value="' + (i + 1) + '"' + (s.suggestedMonth === i + 1 ? ' selected' : '') + '>' + m + '</option>'; }).join('') +
          '</select></div>' +
        '<div class="field field--full"><label>Description</label>' +
          '<textarea class="textarea" id="sgDesc" placeholder="Ingredients, portions, vibe…">' + esc(s.description || '') + '</textarea></div>' +
        '<div class="field"><label>Calories (kcal)</label><input class="input" type="number" id="sgKcal" value="' + s.caloriesKcal + '" /></div>' +
        '<div class="field"><label>Protein (g)</label><input class="input" type="number" id="sgP" value="' + s.proteinG + '" /></div>' +
        '<div class="field"><label>Carbs (g)</label><input class="input" type="number" id="sgC" value="' + s.carbsG + '" /></div>' +
        '<div class="field"><label>Fats (g)</label><input class="input" type="number" id="sgF" value="' + s.fatsG + '" /></div>' +
      '</div>' +
      '<div class="modal__actions">' +
        '<button class="btn btn--ghost btn--sm" data-close>Cancel</button>' +
        '<button class="btn btn--primary" id="sgSave">' + (isNew ? 'Add suggestion' : 'Save changes') + '</button>' +
      '</div>'
    );
    wireClose(backdrop);

    $('#sgSave').addEventListener('click', function () {
      var monthValue = num($('#sgMonth').value);
      var payload = {
        mealSuggestionId: isNew ? null : s.mealSuggestionId,
        title: $('#sgTitle').value.trim(),
        mealType: $('#sgType').value,
        suggestedMonth: monthValue || null,
        description: $('#sgDesc').value.trim(),
        caloriesKcal: num($('#sgKcal').value),
        proteinG: num($('#sgP').value),
        carbsG: num($('#sgC').value),
        fatsG: num($('#sgF').value),
        sortOrder: s.sortOrder || 0
      };
      if (!payload.title) { toast('Title is required', true); return; }
      auth.saveMealSuggestion(payload).then(function (result) {
        if (!toastOnFailure(result, 'Could not save suggestion.')) return;
        toast((result.data && result.data.message) || 'Suggestion saved.');
        closeModal();
        loadSuggestions();
      });
    });
  }

  /* ================================================================
     EXERCISES — table CRUD
     ================================================================ */
  var EQUIPMENT = ['Barbell', 'Dumbbell', 'Cable', 'Machine', 'Kettlebell', 'Bodyweight'];
  var exerciseQuery = '';
  var exerciseMuscle = 'all';

  function renderExerciseFilters() {
    var sel = $('#exerciseMuscleFilter');
    sel.innerHTML = '<option value="all">All muscles</option>' +
      MUSCLE_GROUPS.map(function (m) {
        return '<option value="' + m + '"' + (exerciseMuscle === m ? ' selected' : '') + '>' + m[0].toUpperCase() + m.slice(1) + '</option>';
      }).join('');
  }

  function loadExercises() {
    return auth.getExercises().then(function (result) {
      if (!toastOnFailure(result, 'Could not load exercises.')) return;
      exercisesCache = result.data || [];
      renderExercises();
    });
  }

  function renderExercises() {
    renderExerciseFilters();
    var rows = exercisesCache.filter(function (e) {
      var matchesMuscle = exerciseMuscle === 'all' || e.muscleGroup === exerciseMuscle;
      var matchesQuery = !exerciseQuery || e.name.toLowerCase().indexOf(exerciseQuery) > -1;
      return matchesMuscle && matchesQuery;
    }).sort(function (a, b) { return a.name.localeCompare(b.name); });

    var head = '<thead><tr><th>Exercise</th><th>Muscle</th><th>Equipment</th><th>Type</th><th class="num">In use</th><th></th></tr></thead>';
    var body = rows.map(function (e) {
      return (
        '<tr>' +
          '<td><div class="row-title">' + esc(e.name) + '</div></td>' +
          '<td><span class="chip">' + esc(e.muscleGroup) + '</span></td>' +
          '<td class="label-sm">' + esc(e.equipmentType || '—') + '</td>' +
          '<td>' + (e.isCompound ? '<span class="chip chip--accent">Compound</span>' : '<span class="chip">Isolation</span>') + '</td>' +
          '<td class="num">' + e.usageCount + '</td>' +
          '<td><div class="row-actions">' +
            '<button class="icon-btn" data-edit-exercise="' + e.exerciseId + '" title="Edit">' +
              '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 3a2.8 2.8 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3Z"/></svg>' +
            '</button>' +
            '<button class="icon-btn icon-btn--danger" data-del-exercise="' + e.exerciseId + '" title="Delete">' +
              '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 7h16M9 7V4h6v3m-8 0 1 13h8l1-13"/></svg>' +
            '</button>' +
          '</div></td>' +
        '</tr>'
      );
    }).join('');

    $('#exercisesTable').innerHTML = head + '<tbody>' +
      (body || '<tr><td colspan="6"><div class="empty-state"><img src="assets/img/mascot/resting.png" alt="" /><div class="headline-sm">No exercises match</div></div></td></tr>') +
      '</tbody>';

    $$('[data-edit-exercise]').forEach(function (b) {
      b.addEventListener('click', function () { openExerciseEditor(b.getAttribute('data-edit-exercise')); });
    });
    $$('[data-del-exercise]').forEach(function (b) {
      b.addEventListener('click', function () {
        var e = exercisesCache.find(function (x) { return x.exerciseId === b.getAttribute('data-del-exercise'); });
        if (!e) return;
        confirmDelete('Delete "' + e.name + '"?', 'Refused while any split day still references it.', function () {
          auth.deleteExercise(e.exerciseId).then(function (result) {
            if (!toastOnFailure(result, 'Could not delete exercise.')) return;
            toast((result.data && result.data.message) || 'Exercise deleted.');
            loadExercises();
          });
        });
      });
    });
  }

  function openExerciseEditor(id) {
    var isNew = !id;
    var e = isNew
      ? { name: '', muscleGroup: MUSCLE_GROUPS[0], equipmentType: EQUIPMENT[0], isCompound: true, demoVideoUrl: '' }
      : exercisesCache.find(function (x) { return x.exerciseId === id; });
    if (!isNew && !e) return;

    var backdrop = openModal(
      modalHead(isNew ? 'New exercise' : 'Edit exercise') +
      '<div class="form-grid">' +
        '<div class="field field--full"><label>Name</label>' +
          '<input class="input" id="exName" value="' + esc(e.name) + '" placeholder="Barbell High-Bar Back Squat" /></div>' +
        '<div class="field"><label>Muscle group</label>' +
          '<select class="select" id="exMuscle">' +
            MUSCLE_GROUPS.map(function (m) { return '<option value="' + m + '"' + (e.muscleGroup === m ? ' selected' : '') + '>' + m[0].toUpperCase() + m.slice(1) + '</option>'; }).join('') +
          '</select></div>' +
        '<div class="field"><label>Equipment</label>' +
          '<select class="select" id="exEquip">' +
            EQUIPMENT.map(function (q) { return '<option' + (e.equipmentType === q ? ' selected' : '') + '>' + q + '</option>'; }).join('') +
          '</select></div>' +
        '<div class="field field--full"><label>Demo video URL</label><input class="input" id="exVideo" value="' + esc(e.demoVideoUrl || '') + '" placeholder="https://…" /></div>' +
        '<div class="field field--full" style="flex-direction:row;align-items:center;gap:12px;">' +
          '<label class="switch"><input type="checkbox" id="exCompound"' + (e.isCompound ? ' checked' : '') + ' /><span class="track"></span></label>' +
          '<span class="label-sm">Compound movement</span>' +
        '</div>' +
      '</div>' +
      '<div class="modal__actions">' +
        '<button class="btn btn--ghost btn--sm" data-close>Cancel</button>' +
        '<button class="btn btn--primary" id="exSave">' + (isNew ? 'Add exercise' : 'Save changes') + '</button>' +
      '</div>'
    );
    wireClose(backdrop);

    $('#exSave').addEventListener('click', function () {
      var payload = {
        exerciseId: isNew ? null : e.exerciseId,
        name: $('#exName').value.trim(),
        muscleGroup: $('#exMuscle').value,
        equipmentType: $('#exEquip').value,
        isCompound: $('#exCompound').checked,
        demoVideoUrl: $('#exVideo').value.trim()
      };
      if (!payload.name) { toast('Name is required', true); return; }
      auth.saveExercise(payload).then(function (result) {
        if (!toastOnFailure(result, 'Could not save exercise.')) return;
        toast((result.data && result.data.message) || 'Exercise saved.');
        closeModal();
        loadExercises();
      });
    });
  }

  /* ================================================================
     SUBSCRIPTION PLANS — card editor; features are their own rows
     ================================================================ */
  function loadPlans() {
    return auth.getPlans().then(function (result) {
      if (!toastOnFailure(result, 'Could not load plans.')) return;
      plansCache = result.data || [];
      renderSubPlans();
    });
  }

  function renderSubPlans() {
    var grid = $('#subPlanGrid');
    grid.innerHTML = plansCache.map(function (p) {
      return (
        '<article class="card subplan-card' + (p.isFeatured ? ' is-featured' : '') + '">' +
          '<div style="display:flex;align-items:center;gap:10px;">' +
            '<span class="chip ' + (p.isFeatured ? 'chip--gold' : '') + '">' + esc(p.code) + '</span>' +
            (p.isFeatured ? '<span class="label-sm gold-text">Featured</span>' : '') +
            '<span class="spacer" style="flex:1"></span>' +
            '<div class="row-actions">' +
              '<button class="icon-btn" data-edit-subplan="' + p.planId + '" title="Edit">' +
                '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 3a2.8 2.8 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3Z"/></svg>' +
              '</button>' +
              '<button class="icon-btn icon-btn--danger" data-del-subplan="' + p.planId + '" title="Delete">' +
                '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 7h16M9 7V4h6v3m-8 0 1 13h8l1-13"/></svg>' +
              '</button>' +
            '</div>' +
          '</div>' +
          '<div class="headline-md">' + esc(p.name) + '</div>' +
          '<div class="body-sm">' + esc(p.tagline || '') + '</div>' +
          '<div style="display:flex;gap:18px;" class="num">' +
            '<span><b style="color:var(--high-emphasis);font-size:20px">€' + p.monthlyPrice.toFixed(2) + '</b> <span class="body-sm">/mo</span></span>' +
            '<span><b style="color:var(--high-emphasis);font-size:20px">€' + p.yearlyPrice.toFixed(2) + '</b> <span class="body-sm">/yr</span></span>' +
          '</div>' +
          '<div class="body-sm">' + p.featureCount + ' feature' + (p.featureCount === 1 ? '' : 's') + ' · ' + p.activeSubscriberCount + ' active subscriber' + (p.activeSubscriberCount === 1 ? '' : 's') + '</div>' +
        '</article>'
      );
    }).join('');

    $$('[data-edit-subplan]').forEach(function (b) {
      b.addEventListener('click', function () { openSubPlanEditor(b.getAttribute('data-edit-subplan')); });
    });
    $$('[data-del-subplan]').forEach(function (b) {
      b.addEventListener('click', function () {
        var p = plansCache.find(function (x) { return x.planId === b.getAttribute('data-del-subplan'); });
        if (!p) return;
        confirmDelete('Delete "' + p.name + '"?', 'Refused while the plan has active subscribers.', function () {
          auth.deletePlan(p.planId).then(function (result) {
            if (!toastOnFailure(result, 'Could not delete plan.')) return;
            toast((result.data && result.data.message) || 'Plan deleted.');
            loadPlans();
          });
        });
      });
    });
  }

  function openSubPlanEditor(id) {
    var isNew = !id;
    var p = isNew
      ? { code: '', name: '', tagline: '', monthlyPrice: 0, yearlyPrice: 0, isFeatured: false, sortOrder: 0 }
      : plansCache.find(function (x) { return x.planId === id; });
    if (!isNew && !p) return;

    var features = [];

    var backdrop = openModal(
      modalHead(isNew ? 'New subscription plan' : 'Edit plan') +
      '<div class="form-grid">' +
        '<div class="field"><label>Code</label><input class="input" id="spCode" value="' + esc(p.code) + '" placeholder="PRO" /></div>' +
        '<div class="field"><label>Name</label><input class="input" id="spName" value="' + esc(p.name) + '" placeholder="Pro Tier" /></div>' +
        '<div class="field field--full"><label>Tagline</label><input class="input" id="spTagline" value="' + esc(p.tagline || '') + '" /></div>' +
        '<div class="field"><label>Monthly price (€)</label><input class="input" type="number" step="0.01" id="spMonthly" value="' + p.monthlyPrice + '" /></div>' +
        '<div class="field"><label>Yearly price (€)</label><input class="input" type="number" step="0.01" id="spYearly" value="' + p.yearlyPrice + '" /></div>' +
        '<div class="field field--full" style="flex-direction:row;align-items:center;gap:12px;">' +
          '<label class="switch"><input type="checkbox" id="spFeatured"' + (p.isFeatured ? ' checked' : '') + ' /><span class="track"></span></label>' +
          '<span class="label-sm">Featured plan (gold highlight on the site)</span>' +
        '</div>' +
      '</div>' +
      '<div class="eyebrow" style="margin:20px 0 10px;">Feature list' + (isNew ? ' (save the plan first)' : '') + '</div>' +
      '<div id="featureRows"></div>' +
      (isNew ? '' : '<button class="btn btn--secondary btn--sm" id="addFeatureBtn" style="margin-top:10px;width:100%">+ Add feature</button>') +
      '<div class="eyebrow" style="margin:20px 0 10px;">Entitlements</div>' +
      '<div class="form-grid">' +
        '<div class="field"><label>Max active splits</label><input class="input" type="number" min="0" id="entMaxSplits" placeholder="Blank = unlimited" /></div>' +
        '<div class="field"><label>Max active diet plans</label><input class="input" type="number" min="0" id="entMaxDietPlans" placeholder="Blank = unlimited" /></div>' +
        '<div class="field field--full" style="flex-direction:row;align-items:center;gap:12px;">' +
          '<label class="switch"><input type="checkbox" id="entAllowAi" /><span class="track"></span></label>' +
          '<span class="label-sm">Allow AI-generated splits &amp; diet plans</span>' +
        '</div>' +
      '</div>' +
      '<div class="modal__actions">' +
        '<button class="btn btn--ghost btn--sm" data-close>Cancel</button>' +
        '<button class="btn btn--primary" id="spSave">' + (isNew ? 'Create plan' : 'Save changes') + '</button>' +
      '</div>'
    );
    wireClose(backdrop);

    function renderFeatures() {
      $('#featureRows').innerHTML = features.length ? features.map(function (f) {
        return (
          '<div class="feature-row" style="margin-bottom:8px;" data-feature-row="' + f.planFeatureId + '">' +
            '<input class="input" data-feature-text value="' + esc(f.featureText) + '" placeholder="Feature text…" />' +
            '<label class="switch" title="Highlighted"><input type="checkbox" data-feature-hl' + (f.isHighlighted ? ' checked' : '') + ' /><span class="track"></span></label>' +
            '<button class="icon-btn" data-feature-save title="Save">' +
              '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 13l4 4L19 7"/></svg>' +
            '</button>' +
            '<button class="icon-btn icon-btn--danger" data-feature-del title="Remove">' +
              '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 6l12 12M18 6 6 18"/></svg>' +
            '</button>' +
          '</div>'
        );
      }).join('') : (isNew ? '' : '<p class="body-sm">No features yet.</p>');

      $$('[data-feature-row]', $('#featureRows')).forEach(function (row) {
        var fid = row.getAttribute('data-feature-row');
        var f = features.find(function (x) { return x.planFeatureId === fid; });
        $('[data-feature-save]', row).addEventListener('click', function () {
          var payload = {
            planFeatureId: fid,
            planId: p.planId,
            featureText: $('[data-feature-text]', row).value.trim(),
            sortOrder: f.sortOrder,
            isHighlighted: $('[data-feature-hl]', row).checked
          };
          if (!payload.featureText) { toast('Feature text can\'t be empty', true); return; }
          auth.savePlanFeature(payload).then(function (result) {
            if (!toastOnFailure(result, 'Could not save feature.')) return;
            toast('Feature saved.');
            loadFeatures();
          });
        });
        $('[data-feature-del]', row).addEventListener('click', function () {
          auth.deletePlanFeature(fid).then(function (result) {
            if (!toastOnFailure(result, 'Could not remove feature.')) return;
            toast('Feature removed.');
            loadFeatures();
          });
        });
      });
    }

    function loadFeatures() {
      if (isNew) return;
      auth.getPlanFeatures(p.planId).then(function (result) {
        if (!toastOnFailure(result, 'Could not load features.')) return;
        features = result.data || [];
        renderFeatures();
      });
    }

    function nullableInt(value) {
      var trimmed = (value || '').trim();
      if (!trimmed) return null;
      var n = parseInt(trimmed, 10);
      return isNaN(n) ? null : n;
    }

    function loadEntitlements() {
      if (isNew) return;
      auth.getPlanEntitlements(p.planId).then(function (result) {
        if (!toastOnFailure(result, 'Could not load entitlements.')) return;
        var e = result.data;
        $('#entMaxSplits').value = (e && e.maxActiveSplits != null) ? e.maxActiveSplits : '';
        $('#entMaxDietPlans').value = (e && e.maxActiveDietPlans != null) ? e.maxActiveDietPlans : '';
        $('#entAllowAi').checked = !!(e && e.allowAiGeneration);
      });
    }

    var addFeatureBtn = $('#addFeatureBtn');
    if (addFeatureBtn) {
      addFeatureBtn.addEventListener('click', function () {
        auth.savePlanFeature({ planFeatureId: null, planId: p.planId, featureText: 'New feature', sortOrder: features.length, isHighlighted: false })
          .then(function (result) {
            if (!toastOnFailure(result, 'Could not add feature.')) return;
            loadFeatures();
          });
      });
    }

    $('#spSave').addEventListener('click', function () {
      var payload = {
        planId: isNew ? null : p.planId,
        code: $('#spCode').value.trim().toUpperCase(),
        name: $('#spName').value.trim(),
        tagline: $('#spTagline').value.trim(),
        monthlyPrice: parseFloat($('#spMonthly').value) || 0,
        yearlyPrice: parseFloat($('#spYearly').value) || 0,
        isFeatured: $('#spFeatured').checked,
        sortOrder: p.sortOrder || 0
      };
      if (!payload.name || !payload.code) { toast('Code and name are required', true); return; }

      var entitlementsPayload = {
        planId: isNew ? null : p.planId,
        maxActiveSplits: nullableInt($('#entMaxSplits').value),
        maxActiveDietPlans: nullableInt($('#entMaxDietPlans').value),
        allowAiGeneration: $('#entAllowAi').checked
      };

      auth.savePlan(payload).then(function (result) {
        if (!toastOnFailure(result, 'Could not save plan.')) return;
        var planId = (isNew && result.data && result.data.id) ? result.data.id : p.planId;
        entitlementsPayload.planId = planId;

        auth.savePlanEntitlements(entitlementsPayload).then(function (entResult) {
          toastOnFailure(entResult, 'Plan saved, but entitlements could not be saved.');
          toast((result.data && result.data.message) || 'Plan saved.');
          if (isNew && planId) {
            closeModal();
            loadPlans().then(function () { openSubPlanEditor(planId); });
          } else {
            closeModal();
            loadPlans();
          }
        });
      });
    });

    loadFeatures();
    renderFeatures();
    loadEntitlements();
  }

  /* ================================================================
     USERS — read-only table with KPI row
     ================================================================ */
  var userQuery = '';

  function loadUsers() {
    return auth.getUsers(userQuery || null, 200).then(function (result) {
      if (!toastOnFailure(result, 'Could not load users.')) return;
      usersCache = result.data || [];
      renderUsers();
      renderOverview();
    });
  }

  function renderUsers() {
    var allUsers = usersCache;

    var kpiRow = $('#userKpiRow');
    if (kpiRow) {
      var active = allUsers.filter(function (u) { return u.isActive; }).length;
      var paid = allUsers.filter(function (u) { return u.subscriptionStatus === 'Active' && u.activePlanCode; }).length;
      kpiRow.innerHTML = [
        { label: 'Active users', val: active, sub: (allUsers.length - active) + ' inactive' },
        { label: 'Paid subscribers', val: paid, sub: allUsers.length ? Math.round(paid / allUsers.length * 100) + '% conversion' : '—' },
        { label: 'Total users', val: allUsers.length, sub: 'matching current search' }
      ].map(function (k) {
        return '<div class="user-kpi"><div class="user-kpi__label">' + k.label + '</div><div class="user-kpi__val">' + k.val + '</div><div class="user-kpi__sub">' + k.sub + '</div></div>';
      }).join('');
    }

    /* The mock-data action is destructive, so it is hidden unless the operator holds
       users.mock_data (super-admin only). The API enforces the same permission. */
    var canSeed = has('users.mock_data');

    var head = '<thead><tr><th>User</th><th>Plan</th><th>Billing</th><th>Joined</th><th>Status</th>' +
      (canSeed ? '<th></th>' : '') + '</tr></thead>';
    var body = allUsers.map(function (u) {
      var name = u.displayName || u.email || 'Unnamed user';
      var planChip = !u.activePlanCode ? '<span class="chip">Free</span>' : '<span class="chip chip--gold">' + esc(u.activePlanCode) + '</span>';
      return (
        '<tr>' +
          '<td>' +
            '<div style="display:flex;align-items:center;gap:10px;">' +
              '<div style="width:32px;height:32px;border-radius:50%;background:var(--surface-high);display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:700;color:var(--on-surface-variant);flex:none;">' + esc(name.split(' ').map(function (w) { return w[0]; }).join('').slice(0, 2).toUpperCase()) + '</div>' +
              '<div><div class="row-title">' + esc(name) + '</div><div class="row-sub">' + esc(u.email || '—') + '</div></div>' +
            '</div>' +
          '</td>' +
          '<td>' + planChip + '</td>' +
          '<td class="label-sm">' + esc(u.billingCycle || '—') + '</td>' +
          '<td class="label-sm">' + fmtDate(u.createdAtUtc) + '</td>' +
          '<td>' + (u.isActive
            ? '<span class="chip chip--accent">Active</span>'
            : '<span class="chip chip--error">Inactive</span>') + '</td>' +
          (canSeed
            ? '<td style="text-align:right;white-space:nowrap;"><button class="btn btn--secondary btn--sm" data-mock-user="' + esc(u.userId) + '">Mock data</button></td>'
            : '') +
        '</tr>'
      );
    }).join('');

    $('#usersTable').innerHTML = head + '<tbody>' +
      (body || '<tr><td colspan="' + (canSeed ? 6 : 5) + '"><div class="empty-state"><img src="assets/img/mascot/resting.png" alt="" /><div class="headline-sm">No users match</div></div></td></tr>') +
    '</tbody>';

    if (canSeed) {
      $$('#usersTable [data-mock-user]').forEach(function (btn) {
        btn.addEventListener('click', function () {
          var userId = btn.getAttribute('data-mock-user');
          var user = allUsers.find(function (u) { return u.userId === userId; });
          if (user) openMockDataModal(user);
        });
      });
    }
  }

  /* Super-admin only: generate a month of history for one user so the monthly
     overview can be exercised. Warns first - it replaces their logs and grants a
     yearly subscription. */
  function openMockDataModal(user) {
    var label = user.displayName || user.email || 'this user';
    var backdrop = openModal(
      modalHead('Generate mock data') +
      '<p class="body-sm">Fills <b>' + esc(label) + '</b> with a generated month of workouts, meals, hydration and bodyweight, so the monthly overview has something to show.</p>' +
      '<p class="body-sm" style="margin-top:8px;color:var(--error);">This replaces their existing logs and grants a yearly subscription. It cannot be undone.</p>' +
      '<div class="form-grid" style="margin-top:14px;">' +
        '<div class="field field--full"><label>Profile</label>' +
          '<select class="select" id="mockProfile">' +
            '<option value="Advanced">Advanced — heavier split, tighter adherence</option>' +
            '<option value="Pro">Pro — simpler split, looser adherence</option>' +
          '</select>' +
        '</div>' +
        '<div class="field"><label>Days of history</label>' +
          '<input class="input" id="mockDays" type="number" min="1" max="365" value="30" />' +
        '</div>' +
        '<div class="field"><label>Random seed (optional)</label>' +
          '<input class="input" id="mockSeedInput" type="number" placeholder="Any" />' +
        '</div>' +
      '</div>' +
      '<div class="modal__actions">' +
        '<button class="btn btn--ghost btn--sm" data-close>Cancel</button>' +
        '<button class="btn btn--primary" id="mockSeedBtn">Generate</button>' +
      '</div>'
    );
    wireClose(backdrop);

    $('#mockSeedBtn').addEventListener('click', function () {
      var profile = $('#mockProfile').value;
      var days = num($('#mockDays').value) || 30;
      var seedValue = $('#mockSeedInput').value;
      var seed = seedValue === '' ? null : num(seedValue);
      var btn = $('#mockSeedBtn');
      btn.disabled = true;
      btn.textContent = 'Generating…';

      auth.seedUserMockData(user.userId, profile, days, seed).then(function (result) {
        if (!toastOnFailure(result, 'Could not generate mock data.')) {
          btn.disabled = false;
          btn.textContent = 'Generate';
          return;
        }
        toast((result.data && result.data.message) || 'Mock data generated.');
        closeModal();
        loadUsers();
      });
    });
  }

  /* ================================================================
     Confirm-delete modal
     ================================================================ */
  function confirmDelete(title, body, onConfirm) {
    var backdrop = openModal(
      '<div style="text-align:center;padding:8px 0 4px;">' +
        '<img src="assets/img/mascot/proud.png" alt="" style="width:88px;margin:0 auto 14px;" />' +
        '<div class="headline-md">' + esc(title) + '</div>' +
        '<p class="body-sm" style="margin-top:8px;">' + esc(body) + '</p>' +
      '</div>' +
      '<div class="modal__actions" style="justify-content:center;">' +
        '<button class="btn btn--secondary btn--sm" data-close>Keep it</button>' +
        '<button class="btn btn--danger" id="confirmDeleteBtn">Delete</button>' +
      '</div>'
    );
    wireClose(backdrop);
    $('#confirmDeleteBtn').addEventListener('click', function () {
      closeModal();
      onConfirm();
    });
  }

  /* ================================================================
     Create dispatch + search wiring + init
     ================================================================ */
  function openCreate(kind) {
    if (kind === 'split') openSplitEditor(null);
    else if (kind === 'diet-plan') openDietPlanEditor(null);
    else if (kind === 'suggestion') openSuggestionEditor(null);
    else if (kind === 'exercise') openExerciseEditor(null);
    else if (kind === 'plan') openSubPlanEditor(null);
  }

  $$('[data-open-create]').forEach(function (b) {
    b.addEventListener('click', function () { openCreate(b.getAttribute('data-open-create')); });
  });

  var splitCategorySelect = $('#splitCategoryFilter');
  if (splitCategorySelect) {
    splitCategorySelect.addEventListener('change', function (e) {
      splitCategoryFilter = e.target.value;
      renderSplits();
    });
  }
  var dietPlanPeriodSelect = $('#dietPlanPeriodFilter');
  if (dietPlanPeriodSelect) {
    dietPlanPeriodSelect.addEventListener('change', function (e) {
      dietPlanPeriodFilter = e.target.value;
      renderDietPlans();
    });
  }
  $('#suggestionSearch').addEventListener('input', function (e) {
    suggestionQuery = e.target.value.trim().toLowerCase();
    loadSuggestions();
  });
  $('#suggestionMonthFilter').addEventListener('change', function (e) {
    suggestionMonth = num(e.target.value);
    loadSuggestions();
  });
  $('#exerciseSearch').addEventListener('input', function (e) {
    exerciseQuery = e.target.value.trim().toLowerCase();
    renderExercises();
  });
  $('#exerciseMuscleFilter').addEventListener('change', function (e) {
    exerciseMuscle = e.target.value;
    renderExercises();
  });
  $('#userSearch').addEventListener('input', function (e) {
    userQuery = e.target.value.trim().toLowerCase();
    loadUsers();
  });

  /* ================================================================
     Init — read the session's permissions, gate this file's own nav
     tabs, then load only what the operator may see.
     ================================================================ */
  auth.session().then(function (result) {
    if (!result.ok || !result.data) return; // 401/offline: leave every gated tab hidden.

    myPermissions = result.data.permissions || [];
    applyContentNavGating();
    renderOverview();

    var loaders = [];
    if (has('content.splits.read')) loaders.push(loadSplits());
    if (has('content.diet_plans.read')) loaders.push(loadDietPlans());
    // The split-day editor and the diet-plan day editor fill their pickers from
    // these two caches, so an operator who may write those areas needs them
    // loaded even without the library's own read permission. The API accepts
    // either permission on those two reads for exactly this reason.
    if (has('content.suggestions.read') || has('content.diet_plans.write')) loaders.push(loadSuggestions());
    if (has('content.exercises.read') || has('content.splits.write')) loaders.push(loadExercises());
    if (has('content.plans.read')) loaders.push(loadPlans());
    if (has('users.read')) loaders.push(loadUsers());

    Promise.all(loaders).then(renderOverview);
  });
})();
