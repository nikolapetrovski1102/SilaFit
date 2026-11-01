// Secure trainer-document viewer. Renders each PDF page onto a canvas with the
// reader's watermark burned in. No text layer is created, so nothing can be
// selected or copied; printing is hidden by CSS and the context menu is off.
(function () {
  'use strict';

  var root = document.getElementById('pages');
  var status = document.getElementById('status');
  if (!root || !window.pdfjsLib) {
    return;
  }

  var fileUrl = root.getAttribute('data-file');
  var watermark = root.getAttribute('data-watermark') || '';
  window.pdfjsLib.GlobalWorkerOptions.workerSrc = root.getAttribute('data-worker');

  ['contextmenu', 'copy', 'cut', 'dragstart', 'selectstart'].forEach(function (name) {
    document.addEventListener(name, function (event) { event.preventDefault(); });
  });
  document.addEventListener('keydown', function (event) {
    var key = (event.key || '').toLowerCase();
    if ((event.ctrlKey || event.metaKey) && (key === 's' || key === 'p' || key === 'c')) {
      event.preventDefault();
    }
  });

  function fail(message) {
    status.textContent = message;
    status.hidden = false;
  }

  function drawWatermark(context, width, height) {
    var size = Math.max(14, Math.round(width / 34));
    context.save();
    context.font = '600 ' + size + 'px -apple-system, "Segoe UI", Roboto, sans-serif';
    context.fillStyle = 'rgba(200, 30, 30, 0.13)';
    context.textAlign = 'center';
    context.textBaseline = 'middle';
    context.translate(width / 2, height / 2);
    context.rotate(-Math.PI / 6);
    var diagonal = Math.sqrt(width * width + height * height);
    var stepY = size * 5;
    var label = watermark + '   ·   ';
    var textWidth = Math.max(1, context.measureText(label).width);
    for (var y = -diagonal / 2; y < diagonal / 2; y += stepY) {
      var offset = (Math.round(y / stepY) % 2) * (textWidth / 2);
      for (var x = -diagonal / 2 - offset; x < diagonal / 2; x += textWidth) {
        context.fillText(label, x + textWidth / 2, y);
      }
    }
    context.restore();

    // A solid footer line too, so a cropped screenshot still says whose copy it is.
    context.save();
    context.font = '500 ' + Math.max(11, Math.round(size * 0.7)) + 'px -apple-system, "Segoe UI", Roboto, sans-serif';
    context.fillStyle = 'rgba(160, 20, 20, 0.55)';
    context.textAlign = 'center';
    context.fillText('SilaFit · ' + watermark + ' · do not share', width / 2, height - size * 0.8);
    context.restore();
  }

  function renderPage(pdf, number) {
    return pdf.getPage(number).then(function (page) {
      var cssWidth = Math.min(root.clientWidth || window.innerWidth, 900);
      var base = page.getViewport({ scale: 1 });
      var ratio = Math.min(window.devicePixelRatio || 1, 2.5);
      var viewport = page.getViewport({ scale: (cssWidth / base.width) * ratio });

      var canvas = document.createElement('canvas');
      canvas.width = Math.floor(viewport.width);
      canvas.height = Math.floor(viewport.height);
      canvas.setAttribute('aria-label', 'Page ' + number);
      root.appendChild(canvas);

      var context = canvas.getContext('2d');
      return page.render({ canvasContext: context, viewport: viewport }).promise.then(function () {
        drawWatermark(context, canvas.width, canvas.height);
        page.cleanup();
      });
    });
  }

  window.pdfjsLib.getDocument({
    url: fileUrl,
    isEvalSupported: false,
    disableAutoFetch: false,
    withCredentials: true
  }).promise.then(function (pdf) {
    status.hidden = true;
    var chain = Promise.resolve();
    for (var i = 1; i <= pdf.numPages; i += 1) {
      chain = chain.then(renderPage.bind(null, pdf, i));
    }
    return chain;
  }).catch(function () {
    fail('This document could not be opened. Close it and open it again from the app.');
  });
})();
