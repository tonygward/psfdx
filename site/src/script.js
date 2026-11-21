// The page works without JavaScript. This adds the copy buttons and the typing console, and nothing else.
(function () {
  var root = document.documentElement;
  root.classList.remove('no-js');
  root.classList.add('js');

  var reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---- Copy to the clipboard ------------------------------------------------------------------
  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    return new Promise(function (resolve, reject) {
      var area = document.createElement('textarea');
      area.value = text;
      area.setAttribute('readonly', '');
      area.className = 'sr-only';
      document.body.appendChild(area);
      area.select();
      var ok = false;
      try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
      document.body.removeChild(area);
      if (ok) { resolve(); } else { reject(new Error('copy failed')); }
    });
  }

  function flash(chip, label, done) {
    chip.textContent = label;
    chip.classList.toggle('done', !!done);
    setTimeout(function () { chip.textContent = 'COPY'; chip.classList.remove('done'); }, 1600);
  }

  function enhance(target, chip) {
    var text = target.getAttribute('data-copy');
    function run() {
      copyText(text).then(function () { flash(chip, 'COPIED', true); }, function () { flash(chip, 'PRESS CTRL+C', false); });
    }
    chip.addEventListener('click', function (event) { event.stopPropagation(); run(); });
    return run;
  }

  // The yellow install command: the whole pill is the button.
  document.querySelectorAll('.install[data-copy]').forEach(function (install) {
    var chip = document.createElement('span');
    chip.className = 'chip';
    chip.textContent = 'COPY';
    chip.setAttribute('aria-live', 'polite');
    install.appendChild(chip);
    var run = enhance(install, chip);
    install.setAttribute('role', 'button');
    install.setAttribute('tabindex', '0');
    install.setAttribute('aria-label', 'Copy the install command: ' + install.getAttribute('data-copy'));
    install.addEventListener('click', run);
    install.addEventListener('keydown', function (event) {
      if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); run(); }
    });
  });

  // Code boxes get a copy button.
  document.querySelectorAll('.code-box[data-copy]').forEach(function (box) {
    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'chip copy-btn';
    button.textContent = 'COPY';
    button.setAttribute('aria-label', 'Copy these commands');
    box.appendChild(button);
    var chip = button;
    var text = box.getAttribute('data-copy');
    button.addEventListener('click', function () {
      copyText(text).then(function () { flash(chip, 'COPIED', true); }, function () { flash(chip, 'PRESS CTRL+C', false); });
    });
  });

  // ---- The console: type the second command, show the results, loop -------------------------------
  var consoleEl = document.getElementById('console');
  if (!consoleEl || reduceMotion) { return; }
  var typed = consoleEl.querySelector('.typed');
  var results = consoleEl.querySelector('.results');
  var cursor = consoleEl.querySelector('.cursor');
  if (!typed || !results) { return; }

  var parts = Array.prototype.map.call(typed.children, function (el) { return { el: el, text: el.textContent }; });
  // Whitespace between the coloured pieces is a text node, so keep it by typing it through the following piece.
  var spaces = [];
  typed.childNodes.forEach(function (node) { if (node.nodeType === 3) { spaces.push(node); } });
  spaces.forEach(function (node) { node.textContent = ''; });

  var CHAR_MS = 55;
  var FADE_MS = 250;
  var HOLD_MS = 3300;
  var timer = null;

  function reset() {
    parts.forEach(function (p) { p.el.textContent = ''; });
    results.classList.remove('show');
  }

  function typeAll(done) {
    var piece = 0, index = 0;
    (function step() {
      if (piece >= parts.length) { done(); return; }
      var p = parts[piece];
      if (index < p.text.length) {
        p.el.textContent = p.text.slice(0, ++index);
        timer = setTimeout(step, CHAR_MS);
      } else {
        piece++; index = 0;
        if (spaces[piece - 1]) { spaces[piece - 1].textContent = ' '; }
        step();
      }
    })();
  }

  function cycle() {
    reset();
    spaces.forEach(function (n) { n.textContent = ''; });
    timer = setTimeout(function () {
      typeAll(function () {
        results.classList.add('show');
        timer = setTimeout(cycle, FADE_MS + HOLD_MS);
      });
    }, 600);
  }

  root.classList.add('js-anim');
  // Stop the loop while the tab is hidden, so it does not run in the background.
  document.addEventListener('visibilitychange', function () {
    if (document.hidden) { clearTimeout(timer); } else { cycle(); }
  });
  cycle();
  if (cursor) { cursor.setAttribute('aria-hidden', 'true'); }
})();
