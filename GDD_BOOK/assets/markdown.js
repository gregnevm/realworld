/* Minimal, dependency-free Markdown renderer with GDD link extensions.
 * Supports: headings, bold/italic, inline + fenced code, lists, blockquotes,
 * rules, standard links, [[wikilinks]], and section:/mechanic: cross-refs.
 *
 * MD.render(text, resolvers) -> HTML string.
 * resolvers = { wiki:Map(keyLower->{id,title}), sections:Map(id->title),
 *               mechanics:Map(id->title) }   (all optional)
 */
(function (global) {
  function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }
  function escAttr(s) { return esc(s).replace(/"/g, "&quot;"); }

  function inline(text, R) {
    // Split into code spans vs. the rest so markdown rules never touch code and
    // there is no placeholder token to collide with prose (the old " C0 " token
    // broke text like "grade C0").
    return text.split(/(`[^`]+`)/).map(function (seg) {
      if (seg.length >= 2 && seg[0] === "`" && seg[seg.length - 1] === "`") {
        return "<code>" + esc(seg.slice(1, -1)) + "</code>";
      }
      var t = esc(seg);

      // [[wikilink]] or [[id|Label]]
      t = t.replace(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g, function (_, target, label) {
        var key = target.trim().toLowerCase();
        var hit = R && R.wiki && R.wiki.get(key);
        var disp = (label || (hit ? hit.title : target)).trim();
        if (hit) return '<span class="wikilink" data-wiki="' + escAttr(hit.id) + '">' + esc(disp) + '</span>';
        return '<span class="wikilink broken" data-wiki="' + escAttr(target.trim()) + '" title="No wiki entry yet">' + esc(disp) + '</span>';
      });

      // section:id / mechanic:id  (word-bounded)
      t = t.replace(/\b(section|mechanic):([a-z0-9_-]+)/gi, function (m, kind, id) {
        var map = kind.toLowerCase() === "section" ? (R && R.sections) : (R && R.mechanics);
        var title = map && map.get(id);
        var label = title || id;
        return '<span class="xref" data-' + kind.toLowerCase() + '="' + escAttr(id) + '">' + esc(label) + '</span>';
      });

      // standard links [text](url) — text is already esc()'d so it is injection-safe
      t = t.replace(/\[([^\]]+)\]\((https?:[^)]+)\)/g, function (_, txt, url) {
        return '<a href="' + escAttr(url) + '" target="_blank" rel="noopener">' + txt + '</a>';
      });

      // bold then italic
      t = t.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
      t = t.replace(/(^|[^*])\*([^*]+)\*/g, "$1<em>$2</em>");
      return t;
    }).join("");
  }

  function render(src, R) {
    if (!src) return "";
    R = R || {};
    const lines = String(src).replace(/\r\n/g, "\n").split("\n");
    const out = [];
    let i = 0;

    while (i < lines.length) {
      let line = lines[i];

      // fenced code
      const fence = line.match(/^```(.*)$/);
      if (fence) {
        const buf = [];
        i++;
        while (i < lines.length && !/^```/.test(lines[i])) { buf.push(lines[i]); i++; }
        i++; // closing fence
        out.push("<pre><code>" + esc(buf.join("\n")) + "</code></pre>");
        continue;
      }

      // blank
      if (/^\s*$/.test(line)) { i++; continue; }

      // heading
      const h = line.match(/^(#{1,6})\s+(.*)$/);
      if (h) { out.push(`<h${h[1].length}>${inline(h[2], R)}</h${h[1].length}>`); i++; continue; }

      // hr
      if (/^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(line)) { out.push("<hr/>"); i++; continue; }

      // blockquote (consecutive >)
      if (/^\s*>\s?/.test(line)) {
        const buf = [];
        while (i < lines.length && /^\s*>\s?/.test(lines[i])) { buf.push(lines[i].replace(/^\s*>\s?/, "")); i++; }
        out.push("<blockquote>" + render(buf.join("\n"), R) + "</blockquote>");
        continue;
      }

      // lists
      if (/^\s*([-*+]|\d+\.)\s+/.test(line)) {
        const ordered = /^\s*\d+\.\s+/.test(line);
        const tag = ordered ? "ol" : "ul";
        const items = [];
        while (i < lines.length && /^\s*([-*+]|\d+\.)\s+/.test(lines[i])) {
          items.push(lines[i].replace(/^\s*([-*+]|\d+\.)\s+/, ""));
          i++;
        }
        out.push(`<${tag}>` + items.map(t => `<li>${inline(t, R)}</li>`).join("") + `</${tag}>`);
        continue;
      }

      // paragraph (gather until blank / block start)
      const para = [];
      while (i < lines.length && !/^\s*$/.test(lines[i]) &&
             !/^(#{1,6}\s|```|\s*>|\s*([-*+]|\d+\.)\s|\s*(-{3,}|\*{3,}|_{3,})\s*$)/.test(lines[i])) {
        para.push(lines[i]); i++;
      }
      // flag TODO lines
      let pHtml = inline(para.join(" "), R);
      if (/^todo[:\s]/i.test(para.join(" ").trim())) pHtml = `<span class="todo">${pHtml}</span>`;
      out.push("<p>" + pHtml + "</p>");
    }
    return out.join("\n");
  }

  global.MD = { render: render, inline: inline };
})(window);
