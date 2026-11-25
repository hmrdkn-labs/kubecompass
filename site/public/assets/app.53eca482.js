// Enhances the finished page: evidence-level filter, node and row linking, the one survey pass.
// Everything it shows is already in the HTML; with JavaScript off the page reads the same.
(() => {
  const svg = document.querySelector(".chart");
  const graphEl = document.getElementById("graph-data");
  if (!svg || !graphEl) return;
  const graph = JSON.parse(graphEl.textContent);
  const edgeEls = new Map([...svg.querySelectorAll(".edge")].map((e) => [Number(e.dataset.i), e]));
  const nodeEls = new Map([...svg.querySelectorAll(".node")].map((n) => [n.dataset.id, n]));
  const rows = [...document.querySelectorAll(".rels tbody tr")].map((r) => ({ el: r, ids: r.dataset.i.split(" ").map(Number) }));
  const area = svg.querySelector(".ns-area");
  const nsLabel = svg.querySelector(".ns-label");
  const boundary = svg.querySelector(".boundary");
  const readout = document.getElementById("readout");
  const count = document.getElementById("count");
  const empty = document.getElementById("rels-empty");
  const legend = [...document.querySelectorAll(".lg")];
  const levelName = { observed: "Observed", declared: "Declared", inferred: "Inferred", unavailable: "Unavailable" };
  const nodeById = new Map(graph.nodes.map((n) => [n.id, n]));
  const label = (id) => { const n = nodeById.get(id); return n.virtual ? n.name : `${n.kind} ${n.name}`; };

  const pick = (ids) => (ids.length > 1 ? { type: "group" } : { type: "edge", id: ids[0] });
  const same = (a, b) => !!a && !!b && a.type === b.type && a.id === b.id;
  let selected = graph.defaultSelected == null ? null : { type: "edge", id: graph.defaultSelected };
  let hover = null;
  const levels = new Set();

  const esc = (s) => s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]);

  function edgeText(e) {
    let h = `<b>${esc(label(e.from))} → ${esc(label(e.to))}</b> · ${esc(e.rel)} · <span class="sel">${levelName[e.level]}</span>`;
    h += `<br>Source field: ${esc(e.field)}<br>Join: ${esc(e.join)}`;
    if (e.assume) h += `<br>Assumption: ${esc(e.assume)}`;
    return h;
  }
  function groupText() {
    const e = graph.edges[graph.contained[0]];
    const names = graph.contained.map((i) => label(graph.edges[i].from)).join(", ");
    return `<b>${esc(e.rel)}</b> · <span class="sel">${levelName[e.level]}</span> · ${graph.contained.length} resources in namespace ${esc(label(e.to).replace(/^Namespace /, ""))}<br>${esc(names)}<br>Source field: ${esc(e.field)}<br>Join: ${esc(e.join)}`;
  }
  function nodeText(id) {
    const n = nodeById.get(id);
    if (n.virtual) return `<b>${esc(n.name)}</b> · <span class="sel">Unavailable</span><br>Nothing is drawn into it. The app says what it cannot see.`;
    const mine = graph.edges.filter((e) => e.from === id || e.to === id);
    const parts = mine.map((e) => (e.from === id ? `${e.rel} ${label(e.to)}` : `${label(e.from)} ${e.rel} it`));
    return `<b>${esc(label(id))}</b> · ${mine.length} relationship${mine.length === 1 ? "" : "s"}<br>${esc(parts.join("; "))}`;
  }

  function render() {
    const filtering = levels.size > 0;
    const levelOf = (a) => (a.type === "edge" ? graph.edges[a.id].level : graph.edges[graph.contained[0]].level);
    const selectedShown = selected && (selected.type === "node" || !filtering || levels.has(levelOf(selected)));
    const act = hover || (selectedShown ? selected : null);
    const lit = new Set();
    const litNodes = new Set();
    let inArea = false;
    if (act && act.type === "edge") {
      const e = graph.edges[act.id];
      lit.add(act.id); litNodes.add(e.from); litNodes.add(e.to);
    } else if (act && act.type === "group") {
      graph.contained.forEach((i) => { lit.add(i); litNodes.add(graph.edges[i].from); });
      inArea = true;
    } else if (act && act.type === "node") {
      litNodes.add(act.id);
      graph.edges.forEach((e, i) => { if (e.from === act.id || e.to === act.id) { lit.add(i); litNodes.add(e.from); litNodes.add(e.to); } });
    }
    litNodes.delete(graph.edges[graph.contained[0]].to); // the namespace is the area, not a box
    graph.edges.forEach((e, i) => {
      const el = edgeEls.get(i);
      if (el) { el.classList.toggle("is-on", lit.has(i)); el.classList.toggle("is-off", filtering && !levels.has(e.level)); } // containedIn is the border, not a line
    });
    let shown = 0;
    rows.forEach((r) => {
      const off = filtering && !levels.has(graph.edges[r.ids[0]].level);
      if (!off) shown += r.ids.length;
      r.el.hidden = off;
      r.el.classList.toggle("is-on", r.ids.some((i) => lit.has(i)));
      r.el.querySelector(".rowbtn")?.setAttribute("aria-pressed", String(same(selected, pick(r.ids))));
    });
    nodeEls.forEach((el, id) => {
      el.classList.toggle("is-on", litNodes.has(id) || (el === boundary && levels.has("unavailable")));
      el.setAttribute("aria-pressed", String(!!selected && selected.type === "node" && selected.id === id));
    });
    const nsOff = filtering && !levels.has("observed"); // the border stands for seven Observed lines
    area.classList.toggle("is-off", nsOff);
    nsLabel.classList.toggle("is-off", nsOff);
    area.classList.toggle("is-on", inArea || (act && act.type === "node" && nodeById.get(act.id).kind === "Namespace"));
    svg.classList.toggle("has-active", !!hover || (!!selected && selected.type === "node") || levels.has("unavailable"));
    count.hidden = !filtering;
    count.textContent = `Showing ${shown} of ${graph.edges.length} relationships.`;
    empty.hidden = !filtering || shown !== 0;
    readout.innerHTML = act
      ? (act.type === "edge" ? edgeText(graph.edges[act.id]) : act.type === "group" ? groupText() : nodeText(act.id))
      : "Choose a node or a row to see how each line is known.";
  }

  rows.forEach((r) => {
    const cell = r.el.querySelector(".pair");
    const b = document.createElement("button");
    b.type = "button"; b.className = "rowbtn"; b.setAttribute("aria-pressed", "false");
    b.append(...cell.childNodes);
    cell.append(b);
    b.addEventListener("click", () => { const p = pick(r.ids); selected = same(selected, p) ? null : p; render(); });
    const on = () => { hover = pick(r.ids); render(); };
    const off = () => { hover = null; render(); };
    r.el.addEventListener("mouseenter", on); r.el.addEventListener("mouseleave", off);
    b.addEventListener("focus", on); b.addEventListener("blur", off);
  });
  edgeEls.forEach((el, i) => {
    el.addEventListener("mouseenter", () => { hover = { type: "edge", id: i }; render(); });
    el.addEventListener("mouseleave", () => { hover = null; render(); });
    el.addEventListener("click", () => { selected = { type: "edge", id: i }; render(); });
  });
  nodeEls.forEach((el, id) => {
    const toggle = () => { const p = { type: "node", id }; selected = same(selected, p) ? null : p; render(); };
    el.addEventListener("mouseenter", () => { hover = { type: "node", id }; render(); });
    el.addEventListener("mouseleave", () => { hover = null; render(); });
    el.addEventListener("focus", () => { hover = { type: "node", id }; render(); });
    el.addEventListener("blur", () => { hover = null; render(); });
    el.addEventListener("click", toggle);
    el.addEventListener("keydown", (ev) => { if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); toggle(); } });
  });
  legend.forEach((b) => {
    b.disabled = false;
    b.addEventListener("click", () => {
      const lv = b.dataset.level;
      if (levels.has(lv)) levels.delete(lv); else levels.add(lv);
      b.setAttribute("aria-pressed", String(levels.has(lv)));
      render();
    });
  });
  render();

  // On a phone the list is the object and the map sits behind a disclosure; on a wide screen the list is the disclosure.
  const wrap = document.querySelector(".mapwrap");
  const phone = matchMedia("(max-width: 699.98px)");
  const place = () => { wrap.open = !phone.matches; };
  place();
  phone.addEventListener("change", place);

  // Header: borderless over the hero, a surface and rule once scrolled.
  const top = document.getElementById("top");
  const onScroll = () => top.classList.toggle("scrolled", scrollY > 8);
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  // The survey: once, by evidence level, no loop. Reduced motion keeps the finished map.
  if (!matchMedia("(prefers-reduced-motion: reduce)").matches && "IntersectionObserver" in window) {
    svg.classList.add("pre-survey");
    const io = new IntersectionObserver((entries) => {
      if (!entries.some((e) => e.isIntersecting)) return;
      io.disconnect();
      svg.classList.remove("pre-survey");
      svg.classList.add("surveying");
      setTimeout(() => svg.classList.remove("surveying"), 2000);
    }, { rootMargin: "0px 0px -15% 0px", threshold: 0.1 });
    io.observe(svg);
  }
})();
