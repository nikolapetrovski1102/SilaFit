/* ============================================================
   SilaFit admin sign-in — page controller.

   Two steps against the API: password → challenge, then authenticator code →
   session cookie. Nothing here authenticates anybody; it collects the two
   factors, shows whatever the API says went wrong, and follows the cookie it is
   handed. See js/admin-auth.js for the client and AdminAuthController for the
   server side.
   ============================================================ */
(function () {
  'use strict';

  var auth = window.SilaAdminAuth;
  if (!auth) return;

  var params = new URLSearchParams(location.search);
  var nextPath = auth.safeNext(params.get('next'));
  var destination = nextPath || 'admin.html';

  var alertBox = document.getElementById('loginAlert');
  var stepItems = document.querySelectorAll('.login-step');
  var passwordForm = document.getElementById('passwordForm');
  var codeForm = document.getElementById('codeForm');
  var usernameEl = document.getElementById('adminUsername');
  var passwordEl = document.getElementById('adminPassword');
  var codeEl = document.getElementById('adminCode');
  var codeSubmit = document.getElementById('codeSubmit');
  var passwordSubmit = document.getElementById('passwordSubmit');
  var timerEl = document.getElementById('challengeTimer');
  var emailCodeBtn = document.getElementById('emailCodeBtn');

  var challengeToken = null;
  var challengeDeadline = 0;
  var timerHandle = null;
  var emailCodeCooldownHandle = null;

  /* Reasons we can be sent back here mid-flow, so the page explains itself
     instead of silently reappearing. */
  var REASONS = {
    'expired': 'Your session ended after a period of inactivity. Sign in again to pick up where you left off.',
    'signed-out': 'You have been signed out.',
    'signed-out-all': 'You have been signed out on every device.'
  };

  function showAlert(message, kind) {
    alertBox.textContent = message;
    alertBox.hidden = false;
    alertBox.classList.toggle('login-alert--info', kind === 'info');
  }

  function clearAlert() {
    alertBox.hidden = true;
    alertBox.textContent = '';
  }

  function goToStep(step) {
    passwordForm.hidden = step !== 1;
    codeForm.hidden = step !== 2;

    Array.prototype.forEach.call(stepItems, function (item) {
      var index = Number(item.getAttribute('data-step'));
      item.classList.toggle('is-active', index === step);
      item.classList.toggle('is-done', index < step);
    });

    (step === 1 ? usernameEl : codeEl).focus();
  }

  function setBusy(button, busy, label) {
    button.disabled = busy;
    button.dataset.label = button.dataset.label || button.textContent.trim();
    button.textContent = busy ? label : button.dataset.label;
  }

  /* Messages the API is allowed to hand back verbatim; anything else falls back to
     a neutral line so a 5xx stack detail can never end up on screen. */
  function messageFor(result, fallback) {
    if (result.status === 0) return result.message;
    if (result.status === 429) return result.message || 'Too many failed attempts. This account is temporarily locked.';
    if (result.status === 401 || result.status === 400) return result.message || fallback;
    return fallback;
  }

  /* Challenge tokens are short-lived; show the countdown so nobody types a code
     into an expired challenge. */
  function startChallengeTimer(expiresInSeconds) {
    challengeDeadline = Date.now() + expiresInSeconds * 1000;
    window.clearInterval(timerHandle);

    timerHandle = window.setInterval(function () {
      var secondsLeft = Math.round((challengeDeadline - Date.now()) / 1000);

      if (secondsLeft <= 0) {
        window.clearInterval(timerHandle);
        timerEl.textContent = 'expired';
        showAlert('That sign-in attempt expired. Enter your password again to start over.');
        goToStep(1);
        return;
      }

      timerEl.textContent = secondsLeft + 's left';
    }, 1000);

    timerEl.textContent = expiresInSeconds + 's left';
  }

  passwordForm.addEventListener('submit', function (event) {
    event.preventDefault();
    clearAlert();

    if (!usernameEl.value.trim() || !passwordEl.value) {
      showAlert('Enter both your username and password.');
      return;
    }

    setBusy(passwordSubmit, true, 'Checking…');

    auth.login(usernameEl.value.trim(), passwordEl.value).then(function (result) {
      setBusy(passwordSubmit, false);

      if (!result.ok || !result.data) {
        showAlert(messageFor(result, 'Sign-in failed. Please try again.'));
        passwordEl.value = '';
        passwordEl.focus();
        return;
      }

      challengeToken = result.data.challengeToken;
      passwordEl.value = '';
      showAlert('Password accepted. Enter the code from your authenticator app.', 'info');
      resetEmailCodeButton();
      goToStep(2);
      startChallengeTimer(result.data.expiresInSeconds);
    });
  });

  codeForm.addEventListener('submit', function (event) {
    event.preventDefault();
    clearAlert();

    var code = codeEl.value.replace(/\D/g, '');
    if (code.length !== 6) {
      showAlert('Enter the 6-digit code from your authenticator app.');
      return;
    }

    setBusy(codeSubmit, true, 'Verifying…');

    auth.verify(challengeToken, code).then(function (result) {
      setBusy(codeSubmit, false);

      if (result.ok && result.data) {
        window.clearInterval(timerHandle);
        // Full navigation (not fetch) so nginx sees the fresh cookie on the way in.
        location.assign(destination);
        return;
      }

      codeEl.value = '';
      codeEl.focus();
      showAlert(messageFor(result, 'That code could not be verified. Please try again.'));

      // A locked account or an expired challenge needs the whole flow restarted.
      if (result.status === 429 || result.status === 401) {
        window.clearInterval(timerHandle);
        timerEl.textContent = '';
      }
    });
  });

  /* Cooldown mirrors the API's own 30s resend window (AdminAuthService), so the
     button never fires a request that's just going to come back as a 409. */
  function startEmailCodeCooldown(seconds) {
    window.clearInterval(emailCodeCooldownHandle);
    var secondsLeft = seconds;
    emailCodeBtn.disabled = true;
    emailCodeBtn.textContent = 'Code sent — resend in ' + secondsLeft + 's';

    emailCodeCooldownHandle = window.setInterval(function () {
      secondsLeft -= 1;
      if (secondsLeft <= 0) {
        window.clearInterval(emailCodeCooldownHandle);
        emailCodeBtn.disabled = false;
        emailCodeBtn.textContent = 'Send email code instead';
        return;
      }
      emailCodeBtn.textContent = 'Code sent — resend in ' + secondsLeft + 's';
    }, 1000);
  }

  function resetEmailCodeButton() {
    window.clearInterval(emailCodeCooldownHandle);
    emailCodeBtn.disabled = false;
    emailCodeBtn.textContent = 'Send email code instead';
  }

  emailCodeBtn.addEventListener('click', function () {
    clearAlert();
    emailCodeBtn.disabled = true;

    auth.sendEmailCode(challengeToken).then(function (result) {
      if (!result.ok || !result.data) {
        resetEmailCodeButton();
        showAlert(messageFor(result, 'Could not send an email code. Please try again.'));

        if (result.status === 429 || result.status === 401) {
          window.clearInterval(timerHandle);
          timerEl.textContent = '';
        }
        return;
      }

      showAlert('Code sent to ' + result.data.maskedEmail + '. It expires in 10 minutes.', 'info');
      codeEl.value = '';
      codeEl.focus();
      startEmailCodeCooldown(30);
    });
  });

  document.getElementById('restartBtn').addEventListener('click', function () {
    challengeToken = null;
    window.clearInterval(timerHandle);
    timerEl.textContent = '';
    codeEl.value = '';
    clearAlert();
    resetEmailCodeButton();
    goToStep(1);
  });

  /* Digits only, and submit as soon as the sixth one lands - the code is going to
     expire anyway, so there is no reason to make anyone reach for the mouse. */
  codeEl.addEventListener('input', function () {
    codeEl.value = codeEl.value.replace(/\D/g, '').slice(0, 6);
    if (codeEl.value.length === 6) {
      codeForm.requestSubmit();
    }
  });

  var reason = REASONS[params.get('reason')];
  if (reason) {
    showAlert(reason, 'info');
    history.replaceState(null, '', location.pathname);
  }

  /* Already signed in? Skip the form — the cookie is what nginx and the API care
     about, so there is nothing to prove by retyping a password. */
  auth.session().then(function (result) {
    if (result.ok && result.data) {
      location.replace(destination);
    }
  });

  usernameEl.focus();
})();
