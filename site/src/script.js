// The site works without JavaScript. This only adds the "Copy" buttons on the code blocks.
(function () {
  var buttons = document.querySelectorAll('button.copy');
  var canCopy = !!(navigator.clipboard && navigator.clipboard.writeText);
  buttons.forEach(function (button) {
    if (!canCopy) { button.hidden = true; return; }
    button.addEventListener('click', function () {
      navigator.clipboard.writeText(button.getAttribute('data-copy')).then(function () {
        button.textContent = 'Copied';
        setTimeout(function () { button.textContent = 'Copy'; }, 2000);
      }, function () {
        button.textContent = 'Press Ctrl+C';
        setTimeout(function () { button.textContent = 'Copy'; }, 2000);
      });
    });
  });
})();
