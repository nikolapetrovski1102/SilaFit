/* ============================================================
   SilaFit admin console — roles, operators, audit log.

   Unlike admin.js's content screens (meal plans, exercises, …), which are a
   localStorage/SilaStore demo with no server behind them, everything in this
   file talks to the real, cookie-authenticated API via window.SilaAdminAuth
   (js/admin-auth.js) — creating an operator here creates a real row with a
   real password hash and a real TOTP secret.

   Nav visibility for the three views this file owns (Roles / Operators /
   Audit log) is driven by the `permissions` list the session endpoint already
   returns (see AdminSessionDto). That's a courtesy, not the control — the API
   enforces the same permission on every request regardless of what the sidebar
   shows, via AdminPermissionGuard on the server.
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

  function fmtDate(iso) {
    if (!iso) return '—';
    var d = new Date(iso);
    return isNaN(d.getTime()) ? '—' : d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
  }

  /* ---------------- Toasts (own copy — see js/admin.js for the original) ---------------- */
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

  /* ---------------- Modal (own copy, same markup/behavior as js/admin.js) ---------------- */
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

  function wireClose(backdrop) {
    $$('[data-close]', backdrop).forEach(function (b) { b.addEventListener('click', closeModal); });
  }

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
    $('#confirmDeleteBtn').addEventListener('click', function () { closeModal(); onConfirm(); });
  }

  /* ================================================================
     State
     ================================================================ */
  var catalog = [];       // AdminPermissionDto[]
  var catalogByGroup = []; // [{ group, items: AdminPermissionDto[] }]
  var roles = [];          // AdminRoleDto[]
  var myPermissions = [];

  function has(permission) { return myPermissions.indexOf(permission) > -1; }

  function groupCatalog(list) {
    var order = [];
    var byGroup = {};
    list.forEach(function (p) {
      if (!byGroup[p.group]) { byGroup[p.group] = []; order.push(p.group); }
      byGroup[p.group].push(p);
    });
    return order.map(function (g) { return { group: g, items: byGroup[g] }; });
  }

  /* ================================================================
     Nav gating — hide tabs the signed-in operator has no permission for.
     ================================================================ */
  function applyNavGating() {
    var anyVisible = false;
    $$('.side-link[data-permission]').forEach(function (btn) {
      var visible = has(btn.getAttribute('data-permission'));
      btn.hidden = !visible;
      if (visible) anyVisible = true;
    });
    var label = $('[data-access-control-label]');
    if (label) label.hidden = !anyVisible;
  }

  /* ================================================================
     ROLES
     ================================================================ */
  function loadRoles() {
    return auth.getRoles().then(function (result) {
      if (!result.ok) {
        if (result.status !== 401) toast(result.message || 'Could not load roles.', true);
        return;
      }
      roles = result.data || [];
      renderRoles();
    });
  }

  function permRow(perm, checked, disabled, onToggle) {
    return (
      '<div class="perm-row">' +
        '<div class="perm-row__info">' +
          '<div class="perm-row__label">' + esc(perm.label) + '</div>' +
          '<div class="perm-row__desc">' + esc(perm.description) + '</div>' +
        '</div>' +
        '<label class="switch"><input type="checkbox" data-perm-toggle="' + esc(perm.permission) + '"' +
          (checked ? ' checked' : '') + (disabled ? ' disabled' : '') + ' /><span class="track"></span></label>' +
      '</div>'
    );
  }

  function roleCardHtml(role) {
    var granted = role.permissions || [];
    var body = catalogByGroup.map(function (g) {
      return (
        '<div class="perm-group">' +
          '<div class="perm-group__label">' + esc(g.group) + '</div>' +
          g.items.map(function (p) { return permRow(p, granted.indexOf(p.permission) > -1, role.isSystemRole); }).join('') +
        '</div>'
      );
    }).join('');

    return (
      '<div class="card" data-role-card="' + esc(role.name) + '">' +
        '<div class="role-card__head">' +
          '<div>' +
            '<div class="role-card__name">' +
              '<span class="headline-sm">' + esc(role.name) + '</span>' +
              (role.isSystemRole ? '<span class="chip chip--accent">System</span>' : '<span class="chip">Custom</span>') +
            '</div>' +
            '<div class="body-sm row-sub role-card__desc">' + esc(role.description || 'No description.') + '</div>' +
          '</div>' +
          (role.isSystemRole
            ? ''
            : '<button class="icon-btn icon-btn--danger" data-delete-role="' + esc(role.name) + '" title="Delete role">' +
                '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 7h16M9 7V4h6v3M6 7l1 13a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-13"/></svg>' +
              '</button>') +
        '</div>' +
        '<div class="body-sm" style="margin-bottom:14px;">' + role.operatorCount + ' operator' + (role.operatorCount === 1 ? '' : 's') +
          (role.isSystemRole ? ' · built in, cannot be changed' : '') + '</div>' +
        body +
      '</div>'
    );
  }

  function renderRoles() {
    var grid = $('#rolesGrid');
    if (!grid) return;
    grid.innerHTML = roles.length
      ? roles.map(roleCardHtml).join('')
      : '<div class="card"><div class="empty-state"><img src="assets/img/mascot/resting.png" alt="" /><div class="headline-sm">No roles yet</div></div></div>';

    $$('[data-perm-toggle]', grid).forEach(function (input) {
      input.addEventListener('change', function () {
        var card = input.closest('[data-role-card]');
        var roleName = card.getAttribute('data-role-card');
        var permission = input.getAttribute('data-perm-toggle');
        var granted = input.checked;
        input.disabled = true;
        auth.setRolePermission(roleName, permission, granted).then(function (result) {
          if (result.ok) {
            toast((result.data && result.data.message) || 'Updated.');
            var role = roles.find(function (r) { return r.name === roleName; });
            if (role) {
              var idx = role.permissions.indexOf(permission);
              if (granted && idx === -1) role.permissions.push(permission);
              if (!granted && idx > -1) role.permissions.splice(idx, 1);
            }
            input.disabled = false;
          } else {
            input.checked = !granted;
            input.disabled = false;
            toast(result.message || 'Could not update permission.', true);
          }
        });
      });
    });

    $$('[data-delete-role]', grid).forEach(function (btn) {
      btn.addEventListener('click', function () {
        var roleName = btn.getAttribute('data-delete-role');
        confirmDelete('Delete "' + roleName + '"?', 'Any operator still on this role keeps their account but loses every permission.', function () {
          auth.deleteRole(roleName).then(function (result) {
            if (result.ok) { toast((result.data && result.data.message) || 'Role deleted.'); loadRoles(); }
            else toast(result.message || 'Could not delete role.', true);
          });
        });
      });
    });
  }

  function openCreateRoleModal() {
    var backdrop = openModal(
      modalHead('New role') +
      '<div class="form-grid">' +
        '<div class="field field--full"><label>Role name</label><input class="input" id="roleName" placeholder="e.g. content-editor" /></div>' +
        '<div class="field field--full"><label>Description</label><textarea class="textarea" id="roleDesc" placeholder="What is this role for?"></textarea></div>' +
      '</div>' +
      '<div class="modal__actions">' +
        '<button class="btn btn--ghost btn--sm" data-close>Cancel</button>' +
        '<button class="btn btn--primary" id="roleSave">Create role</button>' +
      '</div>'
    );
    wireClose(backdrop);
    $('#roleSave').addEventListener('click', function () {
      var name = $('#roleName').value.trim();
      if (!name) { toast('A role name is required.', true); return; }
      auth.createRole(name, $('#roleDesc').value.trim()).then(function (result) {
        if (result.ok) { closeModal(); toast((result.data && result.data.message) || 'Role created.'); loadRoles(); }
        else toast(result.message || 'Could not create role.', true);
      });
    });
  }

  /* ================================================================
     OPERATORS
     ================================================================ */
  function loadOperators() {
    var includeInactive = $('#operatorsShowInactive') ? $('#operatorsShowInactive').checked : false;
    return Promise.all([auth.getOperators(includeInactive), roles.length ? Promise.resolve({ ok: true, data: roles }) : auth.getRoles()])
      .then(function (results) {
        var opsResult = results[0];
        if (!opsResult.ok) {
          if (opsResult.status !== 401) toast(opsResult.message || 'Could not load operators.', true);
          return;
        }
        if (results[1].ok) roles = results[1].data || roles;
        renderOperators(opsResult.data || []);
      });
  }

  function roleOptionsHtml(currentRoleName) {
    var options = roles.map(function (r) {
      return '<option value="' + esc(r.name) + '"' + (r.name === currentRoleName ? ' selected' : '') + '>' + esc(r.name) + '</option>';
    }).join('');
    if (!currentRoleName) {
      options = '<option value="" disabled selected>No role assigned</option>' + options;
    }
    return options;
  }

  function renderOperators(operators) {
    var table = $('#operatorsTable');
    if (!table) return;

    var head = '<thead><tr><th>Operator</th><th>Email</th><th>Role</th><th class="num">Sessions</th><th>Last login</th><th>Joined</th><th>Active</th></tr></thead>';
    var body = operators.map(function (op) {
      var emailCell = op.email
        ? esc(op.email) + (op.emailConfirmed
            ? ' <span class="chip chip--accent" title="Confirmed">Confirmed</span>'
            : ' <span class="chip chip--error" title="Not yet confirmed">Unconfirmed</span>')
        : '<span class="muted">None on file</span>';
      return (
        '<tr' + (op.isActive ? '' : ' style="opacity:0.55;"') + '>' +
          '<td><div class="row-title">' + esc(op.username) + '</div></td>' +
          '<td class="row-sub">' + emailCell + '</td>' +
          '<td><select class="select" style="height:32px;font-size:12.5px;" data-op-role="' + esc(op.username) + '">' + roleOptionsHtml(op.roleName) + '</select></td>' +
          '<td class="num">' + op.activeSessionCount + '</td>' +
          '<td class="row-sub">' + fmtDate(op.lastLoginAtUtc) + '</td>' +
          '<td class="row-sub">' + fmtDate(op.createdAtUtc) + '</td>' +
          '<td><label class="switch"><input type="checkbox" data-op-active="' + esc(op.username) + '"' + (op.isActive ? ' checked' : '') + ' /><span class="track"></span></label></td>' +
        '</tr>'
      );
    }).join('');

    table.innerHTML = head + '<tbody>' +
      (body || '<tr><td colspan="7"><div class="empty-state"><img src="assets/img/mascot/resting.png" alt="" /><div class="headline-sm">No operators</div></div></td></tr>') +
    '</tbody>';

    $$('[data-op-role]', table).forEach(function (select) {
      select.addEventListener('change', function () {
        var username = select.getAttribute('data-op-role');
        var roleName = select.value;
        select.disabled = true;
        auth.setOperatorRole(username, roleName).then(function (result) {
          select.disabled = false;
          if (result.ok) toast((result.data && result.data.message) || 'Role updated.');
          else toast(result.message || 'Could not change role.', true);
        });
      });
    });

    $$('[data-op-active]', table).forEach(function (toggle) {
      toggle.addEventListener('change', function () {
        var username = toggle.getAttribute('data-op-active');
        var isActive = toggle.checked;
        toggle.disabled = true;
        auth.setOperatorActive(username, isActive).then(function (result) {
          toggle.disabled = false;
          if (result.ok) { toast((result.data && result.data.message) || 'Updated.'); loadOperators(); }
          else { toggle.checked = !isActive; toast(result.message || 'Could not update operator.', true); }
        });
      });
    });
  }

  // qrcode-generator (js/vendor-qrcode.js) renders synchronously to an SVG
  // string, no canvas/DOM round-trip needed — safe to inline straight into
  // the modal markup below. Never fetch a QR image from a remote service for
  // this: the otpauth URI carries the raw TOTP secret.
  function totpQrSvg(otpAuthUri) {
    if (!window.qrcode) return null;
    try {
      var qr = window.qrcode(0, 'M');
      qr.addData(otpAuthUri);
      qr.make();
      return qr.createSvgTag({ cellSize: 4, margin: 2, scalable: true });
    } catch (e) {
      return null; // fall back to the manual secret/link below — never block enrollment on this
    }
  }

  function openOperatorCreatedModal(dto) {
    var qrSvg = totpQrSvg(dto.otpAuthUri);
    var backdrop = openModal(
      modalHead('Operator created') +
      '<p class="body-sm">Share the password with <strong>' + esc(dto.username) + '</strong> out of band, then have them enroll this secret in their authenticator app. A confirmation email was also sent to their address — they\'ll need to confirm it before "send email code instead" works for their sign-in.</p>' +
      '<div class="totp-reveal">' +
        '<div class="totp-reveal__warning">' +
          '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 9v4M12 17h.01M10.3 3.9 2.5 17a1.5 1.5 0 0 0 1.3 2.2h16.4a1.5 1.5 0 0 0 1.3-2.2L13.7 3.9a1.5 1.5 0 0 0-2.6 0Z"/></svg>' +
          'Shown once — it cannot be retrieved again' +
        '</div>' +
        '<ol class="totp-reveal__steps">' +
          '<li>Open an authenticator app (Google Authenticator, Authy, 1Password…)</li>' +
          '<li>Add account → Scan QR code' + (qrSvg ? '' : ' — or enter the secret below by hand') + '</li>' +
          '<li>Enter the 6-digit code it shows on the first sign-in</li>' +
        '</ol>' +
        (qrSvg ? '<div class="totp-reveal__qr">' + qrSvg + '</div>' : '') +
        '<div class="field"><label>' + (qrSvg ? "Can't scan? Enter this secret manually" : 'Authenticator secret') + '</label><code>' + esc(dto.totpSecret) + '</code></div>' +
        '<div class="field" style="margin-top:10px;"><label>Otpauth link</label><code>' + esc(dto.otpAuthUri) + '</code>' +
          '<span class="muted" style="font-size:11.5px;">For password managers that import a TOTP entry by link.</span>' +
        '</div>' +
      '</div>' +
      '<div class="modal__actions">' +
        '<button class="btn btn--primary" id="opCreatedDone">Done</button>' +
      '</div>',
      true
    );
    // Deliberately no [data-close]/backdrop-dismiss wiring here beyond the explicit
    // button: closing this modal is the operator's acknowledgement that they copied
    // the secret down, so Escape/backdrop-click still work (openModal wires those)
    // but there is no separate "×" shortcut that's easy to hit by accident.
    $('#opCreatedDone').addEventListener('click', function () { closeModal(); loadOperators(); });
  }

  function openCreateOperatorModal() {
    var backdrop = openModal(
      modalHead('Add operator') +
      '<div class="form-grid">' +
        '<div class="field field--full"><label>Username</label><input class="input" id="opUsername" placeholder="e.g. jane" /></div>' +
        '<div class="field field--full"><label>Email</label><input class="input" type="email" id="opEmail" placeholder="jane@example.com" /></div>' +
        '<div class="field field--full"><label>Temporary password</label><input class="input" type="password" id="opPassword" placeholder="At least 12 characters" /></div>' +
        '<div class="field field--full"><label>Role</label><select class="select" id="opRole">' +
          '<option value="">No role (no access until assigned)</option>' +
          roles.map(function (r) { return '<option value="' + esc(r.name) + '">' + esc(r.name) + '</option>'; }).join('') +
        '</select></div>' +
      '</div>' +
      '<div class="modal__actions">' +
        '<button class="btn btn--ghost btn--sm" data-close>Cancel</button>' +
        '<button class="btn btn--primary" id="opSave">Create operator</button>' +
      '</div>'
    );
    wireClose(backdrop);
    $('#opSave').addEventListener('click', function () {
      var username = $('#opUsername').value.trim();
      var email = $('#opEmail').value.trim();
      var password = $('#opPassword').value;
      var roleName = $('#opRole').value;
      if (!username) { toast('A username is required.', true); return; }
      if (!email || email.indexOf('@') === -1) { toast('A valid email is required.', true); return; }
      if (password.length < 12) { toast('Choose a password of at least 12 characters.', true); return; }
      auth.createOperator(username, email, password, roleName || null).then(function (result) {
        if (result.ok) { closeModal(); openOperatorCreatedModal(result.data); }
        else toast(result.message || 'Could not create operator.', true);
      });
    });
  }

  /* ================================================================
     AUDIT LOG
     ================================================================ */
  function loadAudit() {
    return auth.getRecentAudit(100).then(function (result) {
      if (!result.ok) {
        if (result.status !== 401) toast(result.message || 'Could not load the audit log.', true);
        return;
      }
      renderAudit(result.data || []);
    });
  }

  function renderAudit(entries) {
    var table = $('#auditTable');
    if (!table) return;

    var head = '<thead><tr><th>When</th><th>Operator</th><th>Action</th><th>Entity</th><th>Summary</th><th>From</th></tr></thead>';
    var body = entries.map(function (e) {
      return (
        '<tr>' +
          '<td class="row-sub">' + fmtDate(e.createdAtUtc) + '</td>' +
          '<td class="row-title">' + esc(e.username) + '</td>' +
          '<td><span class="chip">' + esc(e.action) + '</span></td>' +
          '<td class="row-sub">' + esc(e.entityType) + (e.entityId ? ' · ' + esc(e.entityId) : '') + '</td>' +
          '<td class="row-sub">' + esc(e.summary || '') + '</td>' +
          '<td class="row-sub">' + esc(e.createdFromIp || '') + '</td>' +
        '</tr>'
      );
    }).join('');

    table.innerHTML = head + '<tbody>' +
      (body || '<tr><td colspan="6"><div class="empty-state"><img src="assets/img/mascot/resting.png" alt="" /><div class="headline-sm">Nothing logged yet</div></div></td></tr>') +
    '</tbody>';
  }

  /* ================================================================
     Wiring + init
     ================================================================ */
  var createRoleBtn = $('#createRoleBtn');
  if (createRoleBtn) createRoleBtn.addEventListener('click', openCreateRoleModal);

  var createOperatorBtn = $('#createOperatorBtn');
  if (createOperatorBtn) createOperatorBtn.addEventListener('click', openCreateOperatorModal);

  var showInactive = $('#operatorsShowInactive');
  if (showInactive) showInactive.addEventListener('change', loadOperators);

  var refreshAuditBtn = $('#refreshAuditBtn');
  if (refreshAuditBtn) refreshAuditBtn.addEventListener('click', loadAudit);

  auth.session().then(function (result) {
    if (!result.ok || !result.data) return; // 401/offline: leave every gated tab hidden.

    myPermissions = result.data.permissions || [];
    applyNavGating();

    if (!myPermissions.length) return;

    auth.getPermissionCatalog().then(function (result) {
      if (result.ok) { catalog = result.data || []; catalogByGroup = groupCatalog(catalog); }
      if (has('roles.manage')) loadRoles();
    });
    if (has('operators.manage')) loadOperators();
    if (has('audit.read')) loadAudit();
  });
})();
