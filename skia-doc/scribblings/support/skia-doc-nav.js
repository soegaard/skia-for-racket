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
    var content = shell && (shell.closest(".main") || shell);
    var barWidth = parseFloat(window.getComputedStyle(document.body, "::after").width);
    var gap = parseFloat(window.getComputedStyle(root).fontSize);
    var rightMargin = 0;

    if (content) {
      var bounds = content.getBoundingClientRect();
      // Include wide code, tables, figures, and margin notes, not just the header.
      var contentRight = bounds.right + Math.max(content.scrollWidth - content.clientWidth, 0);
      contentRight = Math.max(contentRight, shell.getBoundingClientRect().right);
      rightMargin = viewportWidth - contentRight;
    }

    root.style.setProperty("--skia-doc-edge-wash-inset", scrollbarWidth + "px");
    // Use the CSS bar width plus a 1rem gap, including its scrollbar inset.
    // An unavailable width (for example below the media query) keeps it hidden.
    root.classList.toggle("skia-doc-edge-wash-ready",
      barWidth > 0 && rightMargin >= barWidth + gap + scrollbarWidth);
  }

  var edgeWashUpdatePending = false;

  function scheduleEdgeWashUpdate() {
    if (edgeWashUpdatePending) return;
    edgeWashUpdatePending = true;
    window.requestAnimationFrame(function () {
      edgeWashUpdatePending = false;
      updateEdgeWash();
    });
  }

  function initialize(nav) {
    placeAtMainColumnStart(nav);
  }

  function start() {
    document.querySelectorAll("[role='navigation'][data-skia-doc-section]").forEach(initialize);
    updateEdgeWash();
    window.addEventListener("resize", scheduleEdgeWashUpdate, { passive: true });
    window.addEventListener("scroll", scheduleEdgeWashUpdate, { passive: true });
    document.addEventListener("load", scheduleEdgeWashUpdate, true);
    if (document.fonts) {
      document.fonts.ready.then(scheduleEdgeWashUpdate);
      document.fonts.addEventListener("loadingdone", scheduleEdgeWashUpdate);
    }
    if (window.ResizeObserver) {
      var observer = new window.ResizeObserver(scheduleEdgeWashUpdate);
      observer.observe(document.documentElement);
      var shell = document.querySelector(".skia-doc-nav-shell");
      if (shell) observer.observe(shell.closest(".main") || shell);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
}());
