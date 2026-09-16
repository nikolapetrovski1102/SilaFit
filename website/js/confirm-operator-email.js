/* ============================================================
   SilaFit admin console — operator email confirmation link.

   Reads the `token` query param from the link an operator was emailed on
   creation, and posts it once to the API. Deliberately no session cookie
   involved — the token itself is the sole credential (mirrors the
   pre-session login endpoints), so this page works whether or not the
   recipient has ever signed in yet. See AdminRbacController.ConfirmOperatorEmail
   and AdminRbacService.ConfirmOperatorEmailAsync for the server side.
   ============================================================ */
(function () {
  'use strict';

  var auth = window.SilaAdminAuth;
  if (!auth) return;

  var introEl = document.getElementById('confirmIntro');
  var alertBox = document.getElementById('confirmAlert');
  var goToLoginBtn = document.getElementById('confirmGoToLogin');

  function showAlert(message, kind) {
    alertBox.textContent = message;
    alertBox.hidden = false;
    alertBox.classList.toggle('login-alert--info', kind === 'info');
  }

  var params = new URLSearchParams(location.search);
  var token = params.get('token');

  if (!token) {
    introEl.textContent = 'This link is missing its confirmation token.';
    showAlert('Ask an admin to resend your confirmation email.');
    goToLoginBtn.hidden = false;
    return;
  }

  auth.confirmOperatorEmail(token).then(function (result) {
    if (result.ok) {
      introEl.textContent = 'Your email is confirmed.';
      showAlert((result.data && result.data.message) || 'Email confirmed. You can now use "send email code instead" when signing in.', 'info');
    } else {
      introEl.textContent = 'This link could not be confirmed.';
      showAlert(result.message || 'This confirmation link is invalid or has expired. Ask an admin to resend it.');
    }
    goToLoginBtn.hidden = false;
  });
})();
