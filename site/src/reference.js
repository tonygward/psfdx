// Opens the command entry that a link or the address points to (the index at the top of a module page links to each entry).
// The pages work without JavaScript: an entry is simply opened by clicking its name.
(function () {
  function openTarget() {
    var id = decodeURIComponent(window.location.hash.replace(/^#/, ''));
    if (!id) return;
    var el = document.getElementById(id);
    if (el && el.tagName === 'DETAILS') {
      el.open = true;
      el.scrollIntoView();
    }
  }
  window.addEventListener('hashchange', openTarget);
  openTarget();
})();
