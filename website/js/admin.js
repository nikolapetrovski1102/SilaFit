/* ============================================================
   SilaFit admin dashboard — views, CRUD, toasts.
   All mutations go through SilaStore (js/data.js), which
   persists to localStorage — the marketing site reads the same
   store, so edits here go live there immediately.
   ============================================================ */
(function () {
  'use strict';

  var $ = function (sel, root) { return (root || document).querySelector(sel); };
  var $$ = function (sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); };

  function esc(str) {
    return String(str == null ? '' : str)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function num(v) { var n = parseInt(v, 10); return isNaN(n) ? 0 : n; }

  /* ---------------- Toasts ---------------- */
  function toast(message, isError) {
    var stack = $('#toastStack');
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

  /* ---------------- Sidebar counts ---------------- */
  function refreshCounts() {
    $('#countMealPlans').textContent = SilaStore.mealPlans.all().length;
    $('#countSuggestions').textContent = SilaStore.mealSuggestions.all().length;
    $('#countExercises').textContent = SilaStore.exercises.all().length;
    $('#countPlans').textContent = SilaStore.plans.all().length;
    $('#countUsers').textContent = SilaStore.users.all().length;
  }

  /* ================================================================
     OVERVIEW
     ================================================================ */
  function renderOverview() {
    var users = SilaStore.users.all();
    var paid = users.filter(function (u) { return u.plan !== 'FREE' && u.status === 'Active'; });
    var plans = SilaStore.plans.all();
    var mrr = paid.reduce(function (sum, u) {
      var p = plans.find(function (x) { return x.code === u.plan; });
      return sum + (p ? p.monthlyPrice : 0);
    }, 0);

    $('#overviewDate').textContent = new Date().toLocaleDateString('en-GB', {
      weekday: 'long', day: 'numeric', month: 'long', year: 'numeric'
    });
    $('#statUsers').textContent = users.length;
    $('#statSubs').textContent = paid.length;
    $('#statMeals').textContent = SilaStore.mealSuggestions.all().length;
    $('#statMealsDelta').textContent = '▲ ' + SilaStore.mealPlans.all().length + ' active weekly plans';
    $('#statMrr').textContent = '€' + mrr.toFixed(2);

    /* Bar chart — 12 weeks of plausible demo volume, current week accented. */
    var weeks = [214, 248, 231, 265, 289, 276, 302, 318, 295, 334, 351, 342];
    var max = Math.max.apply(null, weeks);
    $('#workoutChart').innerHTML = weeks.map(function (v, i) {
      var h = Math.round((v / max) * 100);
      var isNow = i === weeks.length - 1;
      return (
        '<div class="bar-chart__col">' +
          '<div class="bar-chart__bar' + (isNow ? ' is-accent' : '') + '" style="height:' + h + '%">' +
            '<span class="tip">' + v + ' workouts</span>' +
          '</div>' +
          '<span class="bar-chart__label">W' + (i + 1) + '</span>' +
        '</div>'
      );
    }).join('');

    /* Activity feed — derived from recent store content. */
    var newestMeal = SilaStore.mealSuggestions.all().slice(-1)[0];
    var newestPlan = SilaStore.mealPlans.all().slice(-1)[0];
    var items = [
      { icon: 'lime', text: '<b>Elena R.</b> completed <b>Push Day A</b> — 14 sets, new bench PR', time: '12 min' },
      { icon: 'gold', text: '<b>Marko P.</b> upgraded to <b>Advanced Tier</b>', time: '1 h' },
      newestMeal ? { icon: '', text: 'Meal suggestion <b>' + esc(newestMeal.title) + '</b> is live for ' + esc(SilaStore.MONTHS[newestMeal.month - 1]), time: '3 h' } : null,
      newestPlan ? { icon: 'lime', text: 'Weekly plan <b>' + esc(newestPlan.name) + '</b> ' + (newestPlan.isPublished ? 'published' : 'saved as draft'), time: '5 h' } : null,
      { icon: '', text: '<b>Viktor S.</b> hit a <b>201-day streak</b> 🔥', time: '8 h' },
      { icon: 'gold', text: 'AI monthly analytics report generated for 46 Pro users', time: '1 d' }
    ].filter(Boolean);

    $('#activityList').innerHTML = items.map(function (it) {
      return (
        '<div class="activity-item">' +
          '<div class="activity-item__icon ' + it.icon + '">' +
            '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6.5 6.5v11m11-11v11M3 9v6m18-6v6M6.5 12h11"/></svg>' +
          '</div>' +
          '<div class="body-md" style="font-size:13.5px">' + it.text + '</div>' +
          '<time>' + it.time + '</time>' +
        '</div>'
      );
    }).join('');
  }

  /* ================================================================
     MEAL PLANS — weekly templates with a day-by-day editor
     ================================================================ */
  var mealPlanGoalFilter = 'all';

  function renderMealPlanFilters() {
    var pills = [{ id: 'all', label: 'All goals' }].concat(
      SilaStore.GOALS.map(function (g) { return { id: g, label: SilaStore.GOAL_LABELS[g] }; })
    );
    $('#mealPlanFilters').innerHTML = pills.map(function (p) {
      return '<button class="filter-pill' + (mealPlanGoalFilter === p.id ? ' is-active' : '') + '" data-goal="' + p.id + '">' + p.label + '</button>';
    }).join('');
    $$('#mealPlanFilters .filter-pill').forEach(function (b) {
      b.addEventListener('click', function () {
        mealPlanGoalFilter = b.getAttribute('data-goal');
        renderMealPlans();
      });
    });
  }

  function planDayAverage(plan) {
    var totals = { kcal: 0, p: 0, c: 0, f: 0 };
    var days = 0;
    (plan.days || []).forEach(function (d) {
      if (!d.meals.length) return;
      days++;
      d.meals.forEach(function (m) {
        totals.kcal += m.caloriesKcal; totals.p += m.proteinG; totals.c += m.carbsG; totals.f += m.fatsG;
      });
    });
    if (!days) return totals;
    return {
      kcal: Math.round(totals.kcal / days), p: Math.round(totals.p / days),
      c: Math.round(totals.c / days), f: Math.round(totals.f / days)
    };
  }

  function renderMealPlans() {
    renderMealPlanFilters();
    var plans = SilaStore.mealPlans.all().filter(function (p) {
      return mealPlanGoalFilter === 'all' || p.goal === mealPlanGoalFilter;
    });

    var grid = $('#mealPlanGrid');
    if (!plans.length) {
      grid.innerHTML =
        '<div class="card empty-state" style="grid-column:1/-1">' +
          '<img src="assets/img/mascot/ready.png" alt="Mascot ready" />' +
          '<div class="headline-sm">No plans for this filter</div>' +
          '<p class="body-sm">Create a weekly template and it will show up here.</p>' +
        '</div>';
      return;
    }

    grid.innerHTML = plans.map(function (p) {
      var avg = planDayAverage(p);
      return (
        '<article class="card mp-card">' +
          '<div class="mp-card__head">' +
            '<span class="chip ' + (p.isPublished ? 'chip--accent' : '') + '">' + (p.isPublished ? 'Published' : 'Draft') + '</span>' +
            '<span class="chip chip--gold">' + esc(SilaStore.GOAL_LABELS[p.goal] || p.goal) + '</span>' +
            '<span class="spacer"></span>' +
            '<div class="row-actions">' +
              '<button class="icon-btn" data-edit-plan="' + p.id + '" title="Edit">' +
                '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 3a2.8 2.8 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3Z"/></svg>' +
              '</button>' +
              '<button class="icon-btn icon-btn--danger" data-del-plan="' + p.id + '" title="Delete">' +
                '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 7h16M9 7V4h6v3m-8 0 1 13h8l1-13"/></svg>' +
              '</button>' +
            '</div>' +
          '</div>' +
          '<div>' +
            '<div class="headline-sm">' + esc(p.name) + '</div>' +
            '<div class="mp-card__desc" style="margin-top:6px">' + esc(p.description || '') + '</div>' +
          '</div>' +
          '<div class="mp-card__targets">' +
            '<span class="chip">avg ' + avg.kcal + ' kcal</span>' +
            '<span class="chip">P ' + avg.p + 'g</span>' +
            '<span class="chip">C ' + avg.c + 'g</span>' +
            '<span class="chip">F ' + avg.f + 'g</span>' +
          '</div>' +
          '<div class="mp-card__foot">' +
            '<button class="btn btn--secondary btn--sm" data-edit-plan="' + p.id + '">Edit week</button>' +
            '<button class="btn btn--ghost btn--sm" data-toggle-publish="' + p.id + '">' + (p.isPublished ? 'Unpublish' : 'Publish') + '</button>' +
          '</div>' +
        '</article>'
      );
    }).join('');

    $$('[data-edit-plan]').forEach(function (b) {
      b.addEventListener('click', function () { openMealPlanEditor(b.getAttribute('data-edit-plan')); });
    });
    $$('[data-del-plan]').forEach(function (b) {
      b.addEventListener('click', function () {
        var plan = SilaStore.mealPlans.get(b.getAttribute('data-del-plan'));
        confirmDelete('Delete "' + plan.name + '"?', 'The whole 7-day template will be removed.', function () {
          SilaStore.mealPlans.remove(plan.id);
          toast('Meal plan deleted');
          refreshAll();
        });
      });
    });
    $$('[data-toggle-publish]').forEach(function (b) {
      b.addEventListener('click', function () {
        var plan = SilaStore.mealPlans.get(b.getAttribute('data-toggle-publish'));
        SilaStore.mealPlans.update(plan.id, { isPublished: !plan.isPublished });
        toast(plan.isPublished ? 'Plan unpublished' : 'Plan published — live in the app');
        refreshAll();
      });
    });
  }

  /* ----- Weekly editor modal ----- */
  var DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  function openMealPlanEditor(planId) {
    var isNew = !planId;
    var plan = isNew
      ? {
          name: '', goal: 'LoseFat', description: '', isPublished: false,
          targets: { calories: 2000, proteinG: 150, carbsG: 200, fatsG: 65 },
          days: DAYS.map(function (d) { return { day: d, meals: [] }; })
        }
      : JSON.parse(JSON.stringify(SilaStore.mealPlans.get(planId)));

    var activeDay = 0;

    var backdrop = openModal(
      modalHead(isNew ? 'New meal plan' : 'Edit meal plan') +
      '<div class="form-grid">' +
        '<div class="field field--full"><label>Plan name</label>' +
          '<input class="input" id="mpName" value="' + esc(plan.name) + '" placeholder="Lean Cut — 2000 kcal" /></div>' +
        '<div class="field"><label>Goal</label>' +
          '<select class="select" id="mpGoal">' +
            SilaStore.GOALS.map(function (g) {
              return '<option value="' + g + '"' + (plan.goal === g ? ' selected' : '') + '>' + SilaStore.GOAL_LABELS[g] + '</option>';
            }).join('') +
          '</select></div>' +
        '<div class="field"><label>Daily kcal target</label>' +
          '<input class="input" type="number" id="mpKcal" value="' + plan.targets.calories + '" /></div>' +
        '<div class="field field--full"><label>Description</label>' +
          '<textarea class="textarea" id="mpDesc" placeholder="Who is this week for?">' + esc(plan.description || '') + '</textarea></div>' +
        '<div class="field"><label>Protein target (g)</label><input class="input" type="number" id="mpP" value="' + plan.targets.proteinG + '" /></div>' +
        '<div class="field"><label>Carbs target (g)</label><input class="input" type="number" id="mpC" value="' + plan.targets.carbsG + '" /></div>' +
        '<div class="field"><label>Fats target (g)</label><input class="input" type="number" id="mpF" value="' + plan.targets.fatsG + '" /></div>' +
        '<div class="field" style="flex-direction:row;align-items:center;gap:12px;padding-top:22px;">' +
          '<label class="switch"><input type="checkbox" id="mpPublished"' + (plan.isPublished ? ' checked' : '') + ' /><span class="track"></span></label>' +
          '<span class="label-sm">Published (visible in app)</span>' +
        '</div>' +
      '</div>' +

      '<div class="eyebrow" style="margin-top:24px;">Weekly schedule</div>' +
      '<div class="week-tabs" id="weekTabs"></div>' +
      '<div id="dayEditor"></div>' +

      '<div class="modal__actions">' +
        '<button class="btn btn--ghost btn--sm" data-close>Cancel</button>' +
        '<button class="btn btn--primary" id="mpSave">' + (isNew ? 'Create plan' : 'Save changes') + '</button>' +
      '</div>',
      true
    );
    wireClose(backdrop);

    function syncMeta() {
      plan.name = $('#mpName').value.trim();
      plan.goal = $('#mpGoal').value;
      plan.description = $('#mpDesc').value.trim();
      plan.targets = { calories: num($('#mpKcal').value), proteinG: num($('#mpP').value), carbsG: num($('#mpC').value), fatsG: num($('#mpF').value) };
      plan.isPublished = $('#mpPublished').checked;
    }

    function renderTabs() {
      $('#weekTabs').innerHTML = plan.days.map(function (d, i) {
        var kcal = d.meals.reduce(function (s, m) { return s + m.caloriesKcal; }, 0);
        return '<button class="week-tab' + (i === activeDay ? ' is-active' : '') + '" data-day="' + i + '" title="' + kcal + ' kcal planned">' +
          d.day.slice(0, 3) + '</button>';
      }).join('');
      $$('#weekTabs .week-tab').forEach(function (b) {
        b.addEventListener('click', function () {
          collectDay();
          activeDay = parseInt(b.getAttribute('data-day'), 10);
          renderTabs();
          renderDay();
        });
      });
    }

    function renderDay() {
      var d = plan.days[activeDay];
      var totals = { kcal: 0, p: 0, c: 0, f: 0 };
      d.meals.forEach(function (m) { totals.kcal += m.caloriesKcal; totals.p += m.proteinG; totals.c += m.carbsG; totals.f += m.fatsG; });

      var slots = d.meals.map(function (m, i) {
        return (
          '<div class="meal-slot">' +
            '<div class="meal-slot__grid">' +
              '<div class="field"><label>Type</label>' +
                '<select class="select" data-meal="' + i + '" data-k="type">' +
                  SilaStore.MEAL_TYPES.map(function (t) {
                    return '<option' + (m.type === t ? ' selected' : '') + '>' + t + '</option>';
                  }).join('') +
                '</select></div>' +
              '<div class="field"><label>Meal</label><input class="input" data-meal="' + i + '" data-k="title" value="' + esc(m.title) + '" placeholder="Meal title" /></div>' +
              '<div class="field"><label>Kcal</label><input class="input" type="number" data-meal="' + i + '" data-k="caloriesKcal" value="' + m.caloriesKcal + '" /></div>' +
              '<div class="field"><label>P</label><input class="input" type="number" data-meal="' + i + '" data-k="proteinG" value="' + m.proteinG + '" /></div>' +
              '<div class="field"><label>C</label><input class="input" type="number" data-meal="' + i + '" data-k="carbsG" value="' + m.carbsG + '" /></div>' +
              '<div class="field"><label>F</label><input class="input" type="number" data-meal="' + i + '" data-k="fatsG" value="' + m.fatsG + '" /></div>' +
              '<button class="icon-btn icon-btn--danger" data-remove-meal="' + i + '" title="Remove" style="margin-bottom:1px">' +
                '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 6l12 12M18 6 6 18"/></svg>' +
              '</button>' +
            '</div>' +
          '</div>'
        );
      }).join('');

      $('#dayEditor').innerHTML =
        (slots || '<div class="empty-state" style="padding:24px"><img src="assets/img/mascot/ready.png" style="width:80px" alt="" /><div class="body-sm">No meals for ' + esc(d.day) + ' yet.</div></div>') +
        '<div class="day-total">' +
          '<span>Day total: <b>' + totals.kcal + ' kcal</b></span>' +
          '<span>P <b>' + totals.p + 'g</b></span>' +
          '<span>C <b>' + totals.c + 'g</b></span>' +
          '<span>F <b>' + totals.f + 'g</b></span>' +
          '<span style="margin-left:auto">Target ' + plan.targets.calories + ' kcal</span>' +
        '</div>' +
        '<button class="btn btn--secondary btn--sm" id="addMealBtn" style="margin-top:10px;width:100%">+ Add meal to ' + esc(d.day) + '</button>';

      $('#addMealBtn').addEventListener('click', function () {
        collectDay();
        d.meals.push({ type: 'Breakfast', title: '', caloriesKcal: 0, proteinG: 0, carbsG: 0, fatsG: 0 });
        renderDay();
      });
      $$('[data-remove-meal]', $('#dayEditor')).forEach(function (b) {
        b.addEventListener('click', function () {
          collectDay();
          d.meals.splice(parseInt(b.getAttribute('data-remove-meal'), 10), 1);
          renderDay();
        });
      });
    }

    function collectDay() {
      var d = plan.days[activeDay];
      $$('#dayEditor [data-meal]').forEach(function (input) {
        var i = parseInt(input.getAttribute('data-meal'), 10);
        var k = input.getAttribute('data-k');
        if (!d.meals[i]) return;
        d.meals[i][k] = (k === 'title' || k === 'type') ? input.value : num(input.value);
      });
    }

    $('#mpSave').addEventListener('click', function () {
      syncMeta();
      collectDay();
      if (!plan.name) { toast('Give the plan a name first', true); return; }
      /* Drop empty meal slots (no title). */
      plan.days.forEach(function (d) {
        d.meals = d.meals.filter(function (m) { return m.title.trim().length > 0; });
      });
      if (isNew) {
        SilaStore.mealPlans.create(plan);
        toast('Meal plan "' + plan.name + '" created');
      } else {
        var patch = JSON.parse(JSON.stringify(plan));
        delete patch.id;
        SilaStore.mealPlans.update(planId, patch);
        toast('Meal plan saved');
      }
      closeModal();
      refreshAll();
    });

    renderTabs();
    renderDay();
  }

  /* ================================================================
     MEAL SUGGESTIONS — table CRUD
     ================================================================ */
  var suggestionQuery = '';
  var suggestionMonth = 0; /* 0 = all */

  function renderSuggestionFilters() {
    var sel = $('#suggestionMonthFilter');
    sel.innerHTML = '<option value="0">All months</option>' +
      SilaStore.MONTHS.map(function (m, i) {
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

  function renderSuggestions() {
    renderSuggestionFilters();
    var rows = SilaStore.mealSuggestions.all().filter(function (s) {
      var matchesMonth = !suggestionMonth || s.month === suggestionMonth;
      var matchesQuery = !suggestionQuery ||
        s.title.toLowerCase().indexOf(suggestionQuery) > -1 ||
        (s.description || '').toLowerCase().indexOf(suggestionQuery) > -1;
      return matchesMonth && matchesQuery;
    }).sort(function (a, b) { return a.month - b.month; });

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
          '<td class="label-sm">' + esc(SilaStore.MONTHS[s.month - 1] || '—') + '</td>' +
          '<td class="num accent-text" style="font-weight:600">' + s.caloriesKcal + '</td>' +
          '<td class="num">' + s.proteinG + 'g</td>' +
          '<td class="num">' + s.carbsG + 'g</td>' +
          '<td class="num">' + s.fatsG + 'g</td>' +
          '<td>' + macroMini(s) + '</td>' +
          '<td><div class="row-actions">' +
            '<button class="icon-btn" data-edit-suggestion="' + s.id + '" title="Edit">' +
              '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 3a2.8 2.8 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3Z"/></svg>' +
            '</button>' +
            '<button class="icon-btn icon-btn--danger" data-del-suggestion="' + s.id + '" title="Delete">' +
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
        var s = SilaStore.mealSuggestions.get(b.getAttribute('data-del-suggestion'));
        confirmDelete('Delete "' + s.title + '"?', 'It disappears from the app strip and the landing page.', function () {
          SilaStore.mealSuggestions.remove(s.id);
          toast('Suggestion deleted');
          refreshAll();
        });
      });
    });
  }

  function openSuggestionEditor(id) {
    var isNew = !id;
    var s = isNew
      ? { title: '', mealType: 'Lunch', description: '', caloriesKcal: 400, proteinG: 30, carbsG: 40, fatsG: 12, month: new Date().getMonth() + 1 }
      : SilaStore.mealSuggestions.get(id);

    var backdrop = openModal(
      modalHead(isNew ? 'New meal suggestion' : 'Edit suggestion') +
      '<div class="form-grid">' +
        '<div class="field field--full"><label>Title</label>' +
          '<input class="input" id="sgTitle" value="' + esc(s.title) + '" placeholder="Grilled Chicken Caesar Salad" /></div>' +
        '<div class="field"><label>Meal type</label>' +
          '<select class="select" id="sgType">' +
            SilaStore.MEAL_TYPES.map(function (t) { return '<option' + (s.mealType === t ? ' selected' : '') + '>' + t + '</option>'; }).join('') +
          '</select></div>' +
        '<div class="field"><label>Suggested month</label>' +
          '<select class="select" id="sgMonth">' +
            SilaStore.MONTHS.map(function (m, i) { return '<option value="' + (i + 1) + '"' + (s.month === i + 1 ? ' selected' : '') + '>' + m + '</option>'; }).join('') +
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
      var data = {
        title: $('#sgTitle').value.trim(),
        mealType: $('#sgType').value,
        month: num($('#sgMonth').value),
        description: $('#sgDesc').value.trim(),
        caloriesKcal: num($('#sgKcal').value),
        proteinG: num($('#sgP').value),
        carbsG: num($('#sgC').value),
        fatsG: num($('#sgF').value)
      };
      if (!data.title) { toast('Title is required', true); return; }
      if (isNew) { SilaStore.mealSuggestions.create(data); toast('Suggestion added — live on the site'); }
      else { SilaStore.mealSuggestions.update(id, data); toast('Suggestion updated'); }
      closeModal();
      refreshAll();
    });
  }

  /* ================================================================
     EXERCISES — table CRUD
     ================================================================ */
  var MUSCLES = ['chest', 'back', 'shoulders', 'arms', 'legs', 'core'];
  var EQUIPMENT = ['Barbell', 'Dumbbell', 'Cable', 'Machine', 'Kettlebell', 'Bodyweight'];
  var exerciseQuery = '';
  var exerciseMuscle = 'all';

  function renderExerciseFilters() {
    var sel = $('#exerciseMuscleFilter');
    sel.innerHTML = '<option value="all">All muscles</option>' +
      MUSCLES.map(function (m) {
        return '<option value="' + m + '"' + (exerciseMuscle === m ? ' selected' : '') + '>' + m[0].toUpperCase() + m.slice(1) + '</option>';
      }).join('');
  }

  function renderExercises() {
    renderExerciseFilters();
    var rows = SilaStore.exercises.all().filter(function (e) {
      var matchesMuscle = exerciseMuscle === 'all' || e.muscleGroup === exerciseMuscle;
      var matchesQuery = !exerciseQuery || e.name.toLowerCase().indexOf(exerciseQuery) > -1;
      return matchesMuscle && matchesQuery;
    }).sort(function (a, b) { return a.name.localeCompare(b.name); });

    var head = '<thead><tr><th>Exercise</th><th>Muscle</th><th>Equipment</th><th>Type</th><th></th></tr></thead>';
    var body = rows.map(function (e) {
      return (
        '<tr>' +
          '<td><div class="row-title">' + esc(e.name) + '</div></td>' +
          '<td><span class="chip">' + esc(e.muscleGroup) + '</span></td>' +
          '<td class="label-sm">' + esc(e.equipment) + '</td>' +
          '<td>' + (e.isCompound ? '<span class="chip chip--accent">Compound</span>' : '<span class="chip">Isolation</span>') + '</td>' +
          '<td><div class="row-actions">' +
            '<button class="icon-btn" data-edit-exercise="' + e.id + '" title="Edit">' +
              '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 3a2.8 2.8 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3Z"/></svg>' +
            '</button>' +
            '<button class="icon-btn icon-btn--danger" data-del-exercise="' + e.id + '" title="Delete">' +
              '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 7h16M9 7V4h6v3m-8 0 1 13h8l1-13"/></svg>' +
            '</button>' +
          '</div></td>' +
        '</tr>'
      );
    }).join('');

    $('#exercisesTable').innerHTML = head + '<tbody>' +
      (body || '<tr><td colspan="5"><div class="empty-state"><img src="assets/img/mascot/resting.png" alt="" /><div class="headline-sm">No exercises match</div></div></td></tr>') +
      '</tbody>';

    $$('[data-edit-exercise]').forEach(function (b) {
      b.addEventListener('click', function () { openExerciseEditor(b.getAttribute('data-edit-exercise')); });
    });
    $$('[data-del-exercise]').forEach(function (b) {
      b.addEventListener('click', function () {
        var e = SilaStore.exercises.get(b.getAttribute('data-del-exercise'));
        confirmDelete('Delete "' + e.name + '"?', 'Splits referencing it keep their sets but lose the link.', function () {
          SilaStore.exercises.remove(e.id);
          toast('Exercise deleted');
          refreshAll();
        });
      });
    });
  }

  function openExerciseEditor(id) {
    var isNew = !id;
    var e = isNew ? { name: '', muscleGroup: 'chest', equipment: 'Barbell', isCompound: true } : SilaStore.exercises.get(id);

    var backdrop = openModal(
      modalHead(isNew ? 'New exercise' : 'Edit exercise') +
      '<div class="form-grid">' +
        '<div class="field field--full"><label>Name</label>' +
          '<input class="input" id="exName" value="' + esc(e.name) + '" placeholder="Barbell High-Bar Back Squat" /></div>' +
        '<div class="field"><label>Muscle group</label>' +
          '<select class="select" id="exMuscle">' +
            MUSCLES.map(function (m) { return '<option' + (e.muscleGroup === m ? ' selected' : '') + '>' + m[0].toUpperCase() + m.slice(1) + '</option>'; }).join('') +
          '</select></div>' +
        '<div class="field"><label>Equipment</label>' +
          '<select class="select" id="exEquip">' +
            EQUIPMENT.map(function (q) { return '<option' + (e.equipment === q ? ' selected' : '') + '>' + q + '</option>'; }).join('') +
          '</select></div>' +
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
      var data = {
        name: $('#exName').value.trim(),
        muscleGroup: $('#exMuscle').value,
        equipment: $('#exEquip').value,
        isCompound: $('#exCompound').checked
      };
      if (!data.name) { toast('Name is required', true); return; }
      if (isNew) { SilaStore.exercises.create(data); toast('Exercise added to library'); }
      else { SilaStore.exercises.update(id, data); toast('Exercise updated'); }
      closeModal();
      refreshAll();
    });
  }

  /* ================================================================
     SUBSCRIPTION PLANS — card editor with feature lists
     ================================================================ */
  function renderSubPlans() {
    var grid = $('#subPlanGrid');
    grid.innerHTML = SilaStore.plans.all().map(function (p) {
      var features = (p.features || []).map(function (f) {
        return '<li class="' + (f.highlighted ? 'is-highlighted' : '') + '" style="display:flex;gap:10px;font-size:14px;color:var(--on-surface)">' +
          '<span style="color:' + (f.highlighted ? 'var(--accent)' : 'var(--outline)') + '">✓</span>' + esc(f.text) + '</li>';
      }).join('');
      return (
        '<article class="card subplan-card' + (p.isFeatured ? ' is-featured' : '') + '">' +
          '<div style="display:flex;align-items:center;gap:10px;">' +
            '<span class="chip ' + (p.isFeatured ? 'chip--gold' : '') + '">' + esc(p.code) + '</span>' +
            (p.isFeatured ? '<span class="label-sm gold-text">Featured</span>' : '') +
            '<span class="spacer" style="flex:1"></span>' +
            '<div class="row-actions">' +
              '<button class="icon-btn" data-edit-subplan="' + p.id + '" title="Edit">' +
                '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 3a2.8 2.8 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3Z"/></svg>' +
              '</button>' +
              '<button class="icon-btn icon-btn--danger" data-del-subplan="' + p.id + '" title="Delete">' +
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
          '<ul style="list-style:none;display:flex;flex-direction:column;gap:8px;margin-top:6px;">' + features + '</ul>' +
        '</article>'
      );
    }).join('');

    $$('[data-edit-subplan]').forEach(function (b) {
      b.addEventListener('click', function () { openSubPlanEditor(b.getAttribute('data-edit-subplan')); });
    });
    $$('[data-del-subplan]').forEach(function (b) {
      b.addEventListener('click', function () {
        var p = SilaStore.plans.get(b.getAttribute('data-del-subplan'));
        confirmDelete('Delete "' + p.name + '"?', 'The pricing section on the site updates immediately.', function () {
          SilaStore.plans.remove(p.id);
          toast('Plan deleted');
          refreshAll();
        });
      });
    });
  }

  function openSubPlanEditor(id) {
    var isNew = !id;
    var p = isNew
      ? { code: 'NEW', name: '', tagline: '', monthlyPrice: 0, yearlyPrice: 0, isFeatured: false, features: [{ text: '', highlighted: false }] }
      : JSON.parse(JSON.stringify(SilaStore.plans.get(id)));

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
      '<div class="eyebrow" style="margin:20px 0 10px;">Feature list</div>' +
      '<div id="featureRows"></div>' +
      '<button class="btn btn--secondary btn--sm" id="addFeatureBtn" style="margin-top:10px;width:100%">+ Add feature</button>' +
      '<div class="modal__actions">' +
        '<button class="btn btn--ghost btn--sm" data-close>Cancel</button>' +
        '<button class="btn btn--primary" id="spSave">' + (isNew ? 'Create plan' : 'Save changes') + '</button>' +
      '</div>'
    );
    wireClose(backdrop);

    function renderFeatures() {
      $('#featureRows').innerHTML = p.features.map(function (f, i) {
        return (
          '<div class="feature-row" style="margin-bottom:8px;">' +
            '<input class="input" data-feature="' + i + '" value="' + esc(f.text) + '" placeholder="Feature text…" />' +
            '<label class="switch" title="Highlighted"><input type="checkbox" data-feature-hl="' + i + '"' + (f.highlighted ? ' checked' : '') + ' /><span class="track"></span></label>' +
            '<button class="icon-btn icon-btn--danger" data-feature-del="' + i + '" title="Remove">' +
              '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 6l12 12M18 6 6 18"/></svg>' +
            '</button>' +
          '</div>'
        );
      }).join('');

      $$('[data-feature]', $('#featureRows')).forEach(function (input) {
        input.addEventListener('input', function () {
          p.features[num(input.getAttribute('data-feature'))].text = input.value;
        });
      });
      $$('[data-feature-hl]', $('#featureRows')).forEach(function (input) {
        input.addEventListener('change', function () {
          p.features[num(input.getAttribute('data-feature-hl'))].highlighted = input.checked;
        });
      });
      $$('[data-feature-del]', $('#featureRows')).forEach(function (b) {
        b.addEventListener('click', function () {
          p.features.splice(num(b.getAttribute('data-feature-del')), 1);
          renderFeatures();
        });
      });
    }

    $('#addFeatureBtn').addEventListener('click', function () {
      p.features.push({ text: '', highlighted: false });
      renderFeatures();
    });

    $('#spSave').addEventListener('click', function () {
      var data = {
        code: $('#spCode').value.trim().toUpperCase() || 'PLAN',
        name: $('#spName').value.trim(),
        tagline: $('#spTagline').value.trim(),
        monthlyPrice: parseFloat($('#spMonthly').value) || 0,
        yearlyPrice: parseFloat($('#spYearly').value) || 0,
        isFeatured: $('#spFeatured').checked,
        features: p.features.filter(function (f) { return f.text.trim().length > 0; })
      };
      if (!data.name) { toast('Name is required', true); return; }
      if (isNew) { SilaStore.plans.create(data); toast('Plan created — live in pricing'); }
      else { SilaStore.plans.update(id, data); toast('Plan updated'); }
      closeModal();
      refreshAll();
    });

    renderFeatures();
  }

  /* ================================================================
     USERS — read-only table with KPI row
     ================================================================ */
  var userQuery = '';

  function renderUsers() {
    var allUsers = SilaStore.users.all();
    var rows = allUsers.filter(function (u) {
      return !userQuery ||
        u.name.toLowerCase().indexOf(userQuery) > -1 ||
        u.email.toLowerCase().indexOf(userQuery) > -1;
    });

    /* KPI mini-cards */
    var kpiRow = $('#userKpiRow');
    if (kpiRow) {
      var active = allUsers.filter(function (u) { return u.status === 'Active'; }).length;
      var paid = allUsers.filter(function (u) { return u.plan !== 'FREE' && u.status === 'Active'; }).length;
      var maxStreak = allUsers.reduce(function (m, u) { return Math.max(m, u.streak); }, 0);
      var avgStreak = allUsers.length ? Math.round(allUsers.reduce(function (s, u) { return s + u.streak; }, 0) / allUsers.length) : 0;
      kpiRow.innerHTML = [
        { label: 'Active users', val: active, sub: (allUsers.length - active) + ' churned' },
        { label: 'Paid subscribers', val: paid, sub: Math.round(paid / allUsers.length * 100) + '% conversion' },
        { label: 'Longest streak', val: maxStreak + ' d', sub: 'personal best' },
        { label: 'Avg. streak', val: avgStreak + ' d', sub: 'across all users' }
      ].map(function (k) {
        return '<div class="user-kpi"><div class="user-kpi__label">' + k.label + '</div><div class="user-kpi__val">' + k.val + '</div><div class="user-kpi__sub">' + k.sub + '</div></div>';
      }).join('');
    }

    var head = '<thead><tr><th>User</th><th>Plan</th><th class="num">Streak</th><th>Joined</th><th>Status</th></tr></thead>';
    var body = rows.map(function (u) {
      var planChip = u.plan === 'FREE' ? '<span class="chip">Free</span>'
        : u.plan === 'PRO' ? '<span class="chip chip--gold">Pro</span>'
        : '<span class="chip chip--accent">Advanced</span>';
      var streakBar = u.streak > 0
        ? '<div style="display:flex;align-items:center;gap:6px;"><span class="num">' + u.streak + ' d</span><div style="width:' + Math.min(u.streak, 60) + 'px;height:4px;border-radius:2px;background:var(--accent);opacity:0.5;"></div></div>'
        : '<span class="num" style="color:var(--outline);">0 d</span>';
      return (
        '<tr>' +
          '<td>' +
            '<div style="display:flex;align-items:center;gap:10px;">' +
              '<div style="width:32px;height:32px;border-radius:50%;background:var(--surface-high);display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:700;color:var(--on-surface-variant);flex:none;">' + esc(u.name.split(' ').map(function(w){return w[0];}).join('').slice(0,2).toUpperCase()) + '</div>' +
              '<div><div class="row-title">' + esc(u.name) + '</div><div class="row-sub">' + esc(u.email) + '</div></div>' +
            '</div>' +
          '</td>' +
          '<td>' + planChip + '</td>' +
          '<td>' + streakBar + '</td>' +
          '<td class="label-sm">' + esc(u.joined) + '</td>' +
          '<td>' + (u.status === 'Active'
            ? '<span class="chip chip--accent">Active</span>'
            : '<span class="chip chip--error">Churned</span>') + '</td>' +
        '</tr>'
      );
    }).join('');

    $('#usersTable').innerHTML = head + '<tbody>' +
      (body || '<tr><td colspan="5"><div class="empty-state"><img src="assets/img/mascot/resting.png" alt="" /><div class="headline-sm">No users match</div></div></td></tr>') +
    '</tbody>';
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
     Create dispatch + search wiring + refresh
     ================================================================ */
  function openCreate(kind) {
    if (kind === 'mealPlan') openMealPlanEditor(null);
    else if (kind === 'suggestion') openSuggestionEditor(null);
    else if (kind === 'exercise') openExerciseEditor(null);
    else if (kind === 'plan') openSubPlanEditor(null);
  }

  $$('[data-open-create]').forEach(function (b) {
    b.addEventListener('click', function () { openCreate(b.getAttribute('data-open-create')); });
  });

  $('#suggestionSearch').addEventListener('input', function (e) {
    suggestionQuery = e.target.value.trim().toLowerCase();
    renderSuggestions();
  });
  $('#suggestionMonthFilter').addEventListener('change', function (e) {
    suggestionMonth = num(e.target.value);
    renderSuggestions();
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
    renderUsers();
  });

  $('#resetStoreBtn').addEventListener('click', function () {
    confirmDelete('Reset all content to seed data?', 'Every edit you made in this dashboard will be lost.', function () {
      SilaStore.resetToSeed();
      toast('Store reset to seed data');
      refreshAll();
    });
  });

  function refreshAll() {
    refreshCounts();
    renderOverview();
    renderMealPlans();
    renderSuggestions();
    renderExercises();
    renderSubPlans();
    renderUsers();
  }

  refreshAll();
})();
