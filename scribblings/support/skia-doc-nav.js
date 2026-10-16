/* Progressive enhancement for placement and the non-interactive edge cue. */
(function () {
  "use strict";

  function placeAtMainColumnStart(nav) {
    var shell = nav.closest(".skia-doc-nav-shell");
    var main = shell && shell.closest(".main");
    if (!shell || !main || main.firstElementChild === shell) return;

    var wrapper = shell.parentElement;
    main.insertBefore(shell, main.firstChild);
    if (wrapper.classList.contains("skia-doc-nav-pretitle") && !wrapper.firstElementChild) {
      wrapper.remove();
    }
  }

  function updateEdgeWash() {
    var root = document.documentElement;
    var viewportWidth = root.clientWidth;
    var scrollbarWidth = Math.max(window.innerWidth - viewportWidth, 0);
    var shell = document.querySelector(".skia-doc-nav-shell");
    var rightMargin = shell ? viewportWidth - shell.getBoundingClientRect().right : 0;

    root.style.setProperty("--skia-doc-edge-wash-inset", scrollbarWidth + "px");
    root.classList.toggle("skia-doc-edge-wash-ready", rightMargin >= 24);
  }

  function initialize(nav) {
    placeAtMainColumnStart(nav);
  }

  function start() {
    document.querySelectorAll("[role='navigation'][data-skia-doc-section]").forEach(initialize);
    updateEdgeWash();
    window.addEventListener("resize", updateEdgeWash, { passive: true });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
}());
