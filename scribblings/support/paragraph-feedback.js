// Adds per-paragraph feedback controls to Scribble-generated HTML pages.
(() => {
  const installFeedback = () => {
  const meta = name => document.querySelector(`meta[name="${name}"]`)?.content;
  const repo = meta("feedback-github");
  const email = meta("feedback-email");
  if (!repo && !email) return;

  const clip = (text, length) =>
    text.length > length ? text.slice(0, length) + " …" : text;

  function shortHash(text) {
    let hash = 2166136261;
    for (const character of text) {
      hash ^= character.codePointAt(0);
      hash = Math.imul(hash, 16777619) >>> 0;
    }
    const alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    let result = "";
    for (let index = 0; index < 5; index++) {
      result += alphabet[hash % 62];
      hash = Math.floor(hash / 62);
    }
    return result;
  }

  // Avoid IDs that Scribble or other document extensions already assigned.
  const usedIds = new Set([...document.querySelectorAll("[id]")].map(node => node.id));

  document.querySelectorAll(".maincolumn .main p").forEach(paragraph => {
    if (paragraph.closest(
      ".refpara, .tocset, .navsettop, .navsetbottom, .SPretitle, .skia-doc-nav, .skia-ai-notice"
    )) return;
    const text = paragraph.textContent.trim().replace(/\s+/g, " ");
    if (text.length < 20) return;

    if (!paragraph.id) {
      const stem = "a_" + shortHash(text);
      let id = stem;
      let suffix = 2;
      while (usedIds.has(id)) id = `${stem}-${suffix++}`;
      paragraph.id = id;
      usedIds.add(id);
    }
    paragraph.classList.add("fb-paragraph");

    const flag = document.createElement("button");
    flag.className = "fb-flag";
    flag.type = "button";
    flag.textContent = "⚑";
    flag.title = "Comment on this paragraph";
    flag.setAttribute("aria-label", flag.title);
    flag.setAttribute("aria-expanded", "false");
    paragraph.prepend(flag);

    flag.addEventListener("click", () => {
      const next = paragraph.nextElementSibling;
      if (next?.classList.contains("fb-form")) {
        next.remove();
        flag.setAttribute("aria-expanded", "false");
        return;
      }

      const url = location.origin + location.pathname + "#" + paragraph.id;
      const form = document.createElement("div");
      form.className = "fb-form";
      form.innerHTML = `
        <a class="fb-link"></a>
        <label class="fb-label">Comment
          <textarea placeholder="Optional; you can also write it on the next screen"></textarea>
        </label>
        <div class="fb-actions">
          ${repo ? '<button type="button" data-via="github">Open GitHub issue</button>' : ""}
          ${email ? '<button type="button" data-via="email">Email the author</button>' : ""}
        </div>`;
      const link = form.querySelector(".fb-link");
      link.href = url;
      link.textContent = url;

      form.addEventListener("click", event => {
        const via = event.target.dataset?.via;
        if (!via) return;

        const comment = form.querySelector("textarea").value.trim();
        const title = `Docs feedback: ${document.title} (#${paragraph.id})`;

        if (via === "github") {
          const body = `**Paragraph:** ${url}\n\n> ${clip(text, 1500)}\n\n` +
                       (comment || "<!-- your comment here -->");
          const query = new URLSearchParams({ title, body, labels: "docs-feedback" });
          window.open(`https://github.com/${repo}/issues/new?${query}`, "_blank", "noopener");
        } else {
          const body = `${url}\n\n"${clip(text, 600)}"\n\n${comment}`;
          location.href = `mailto:${email}?subject=${encodeURIComponent(title)}` +
                          `&body=${encodeURIComponent(body)}`;
        }
      });

      paragraph.after(form);
      flag.setAttribute("aria-expanded", "true");
      form.querySelector("textarea").focus();
    });
  });
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", installFeedback, { once: true });
  } else {
    installFeedback();
  }
})();
