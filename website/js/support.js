/* ============================================================
   SilaFit support page — contact form
   Posts to POST /api/support/contact, which emails the support
   inbox with the visitor's address as Reply-To.
   ============================================================ */
(function (global) {
  'use strict';

  var form = document.getElementById('contactForm');
  if (!form) return;

  /* Same base-URL rule as admin-auth.js: in production the site and API
     share an origin; locally the site runs on a throwaway static server
     (or file://) and the API on :5080. */
  var API_BASE = (global.SILAFIT_API_BASE || defaultDevApiBase()).replace(/\/+$/, '');

  function defaultDevApiBase() {
    var isFileProtocol = global.location.protocol === 'file:';
    var isLoopbackHttp = global.location.protocol === 'http:' &&
      (global.location.hostname === 'localhost' || global.location.hostname === '127.0.0.1') &&
      global.location.port !== '5080';
    return (isFileProtocol || isLoopbackHttp) ? 'http://localhost:5080' : '';
  }

  var FALLBACK = "We couldn't send your message right now. Please email support@sila.fitness directly.";

  var nameInput = form.elements.name;
  var emailInput = form.elements.email;
  var messageInput = form.elements.message;
  var topics = form.querySelector('.contact-topics');
  var count = document.getElementById('contactCount');
  var status = document.getElementById('contactStatus');
  var submit = document.getElementById('contactSubmit');
  var submitLabel = submit.querySelector('.contact-form__label');
  var sent = document.getElementById('contactSent');
  var sentEmail = document.getElementById('contactSentEmail');
  var again = document.getElementById('contactAgain');

  messageInput.addEventListener('input', function () {
    count.textContent = messageInput.value.length.toLocaleString('en');
  });

  // Clear an error as soon as the visitor starts fixing it.
  form.addEventListener('input', function (e) {
    if (e.target.getAttribute('aria-invalid') === 'true') e.target.removeAttribute('aria-invalid');
    if (e.target.name === 'topic') topics.classList.remove('is-invalid');
    status.textContent = '';
  });

  function selectedTopic() {
    var checked = form.querySelector('input[name="topic"]:checked');
    return checked ? checked.value : '';
  }

  /* Returns the first problem (and marks the field), or null when valid. */
  function validate() {
    var problems = [];
    if (!nameInput.value.trim()) problems.push([nameInput, 'Please enter your name.']);
    var email = emailInput.value.trim();
    if (!email) problems.push([emailInput, 'Please enter your email address.']);
    else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) problems.push([emailInput, 'Please enter a valid email address.']);
    if (!selectedTopic()) problems.push([topics, 'Please choose a topic.']);
    var message = messageInput.value.trim();
    if (message.length < 10) problems.push([messageInput, 'Please describe what happened (at least 10 characters).']);

    problems.forEach(function (p) {
      if (p[0] === topics) topics.classList.add('is-invalid');
      else p[0].setAttribute('aria-invalid', 'true');
    });

    if (!problems.length) return null;
    var first = problems[0][0];
    (first === topics ? topics.querySelector('input') : first).focus();
    return problems[0][1];
  }

  function setBusy(busy) {
    submit.disabled = busy;
    submitLabel.textContent = busy ? 'Sending…' : 'Send message';
  }

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    status.textContent = '';

    var problem = validate();
    if (problem) {
      status.textContent = problem;
      return;
    }

    var payload = {
      name: nameInput.value.trim(),
      email: emailInput.value.trim(),
      topic: selectedTopic(),
      message: messageInput.value.trim(),
      website: form.elements.website.value
    };

    setBusy(true);
    fetch(API_BASE + '/api/support/contact', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })
      .then(function (response) {
        return response.json().catch(function () { return null; }).then(function (body) {
          if (response.ok && body && body.success) return;
          throw new Error((body && body.message) || FALLBACK);
        });
      })
      .then(function () {
        sentEmail.textContent = payload.email;
        form.hidden = true;
        sent.hidden = false;
        sent.scrollIntoView({ behavior: 'smooth', block: 'center' });
      })
      .catch(function (err) {
        // A network failure surfaces as a TypeError with a browser-specific message.
        status.textContent = err instanceof TypeError ? FALLBACK : err.message;
      })
      .then(function () { setBusy(false); });
  });

  again.addEventListener('click', function () {
    messageInput.value = '';
    count.textContent = '0';
    sent.hidden = true;
    form.hidden = false;
    messageInput.focus();
  });
})(window);
