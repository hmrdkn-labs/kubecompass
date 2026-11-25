// Enhances the finished page: evidence-level filter, node and row linking, the one survey pass.
// Everything it shows is already in the HTML; with JavaScript off the page reads the same.
(() => {
  const svg = document.querySelector(".chart");
  const graphEl = document.getElementById("graph-data");
  if (!svg || !graphEl) return;
  const graph = JSON.parse(graphEl.textContent);
  const edgeEls = new Map([...svg.querySelectorAll(".edge")].map((e) => [Number(e.dataset.i), e]));
  const nodeEls = new Map([...svg.querySelectorAll(".node")].map((n) => [n.dataset.id, n]));
  const rowEls = new Map([...document.querySelectorAll(".rels tbody tr")].map((r) => [Number(r.dataset.i), r]));
  const area = svg.querySelector(".ns-area");
  const boundary = svg.querySelector(".boundary");
  const readout = document.getElementById("readout");
  const count = document.getElementById("count");
  const empty = document.getElementById("rels-empty");
  const legend = [...document.querySelectorAll(".lg")];
  const levelName = { observed: "Observed", declared: "Declared", inferred: "Inferred", unavailable: "Unavailable" };
  const nodeById = new Map(graph.nodes.map((n) => [n.id, n]));
  const label = (id) => { const n = nodeById.get(id); return n.virtual ? n.name : `${n.kind} ${n.name}`; };

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
  function nodeText(id) {
    const n = nodeById.get(id);
    if (n.virtual) return `<b>${esc(n.name)}</b> · <span class="sel">Unavailable</span><br>Nothing is drawn into it. The app says what it cannot see.`;
    const mine = graph.edges.filter((e) => e.from === id || e.to === id);
    const parts = mine.map((e) => (e.from === id ? `${e.rel} ${label(e.to)}` : `${label(e.from)} ${e.rel} it`));
    return `<b>${esc(label(id))}</b> · ${mine.length} relationship${mine.length === 1 ? "" : "s"}<br>${esc(parts.join("; "))}`;
  }

  function render() {
    const filtering = levels.size > 0;
    const selectedShown = selected && (selected.type !== "edge" || !filtering || levels.has(graph.edges[selected.id].level));
    const act = hover || (selectedShown ? selected : null);
    const lit = new Set();
    const litNodes = new Set();
    let inArea = false;
    if (act && act.type === "edge") {
      const e = graph.edges[act.id];
      lit.add(act.id); litNodes.add(e.from); litNodes.add(e.to);
      inArea = e.rel === "containedIn";
    } else if (act && act.type === "node") {
      litNodes.add(act.id);
      graph.edges.forEach((e, i) => { if (e.from === act.id || e.to === act.id) { lit.add(i); litNodes.add(e.from); litNodes.add(e.to); } });
    }
    graph.edges.forEach((e, i) => {
      const off = filtering && !levels.has(e.level);
      const el = edgeEls.get(i), row = rowEls.get(i);
      if (el) { el.classList.toggle("is-on", lit.has(i)); el.classList.toggle("is-off", off); } // containedIn is the boundary, not a line
      row.classList.toggle("is-on", lit.has(i));
      row.hidden = off;
      const b = row.querySelector(".rowbtn");
      if (b) b.setAttribute("aria-pressed", String(!!selected && selected.type === "edge" && selected.id === i));
    });
    nodeEls.forEach((el, id) => {
      const isB = el === boundary;
      el.classList.toggle("is-on", litNodes.has(id) || (isB && levels.has("unavailable")));
      el.setAttribute("aria-pressed", String(!!selected && selected.type === "node" && selected.id === id));
    });
    area.classList.toggle("is-on", inArea);
    svg.classList.toggle("has-active", !!hover || (!!selected && selected.type === "node") || levels.has("unavailable"));
    const shown = graph.edges.filter((e) => !filtering || levels.has(e.level)).length;
    count.textContent = filtering ? `Showing ${shown} of ${graph.edges.length} relationships.` : `All ${graph.edges.length} relationships.`;
    empty.hidden = shown !== 0;
    readout.innerHTML = act
      ? (act.type === "edge" ? edgeText(graph.edges[act.id]) : nodeText(act.id))
      : "Choose a node or a row to see how each line is known.";
  }

  rowEls.forEach((row, i) => {
    const cell = row.querySelector(".pair");
    const b = document.createElement("button");
    b.type = "button"; b.className = "rowbtn"; b.setAttribute("aria-pressed", "false");
    b.append(...cell.childNodes);
    cell.append(b);
    b.addEventListener("click", () => { selected = selected && selected.type === "edge" && selected.id === i ? null : { type: "edge", id: i }; render(); });
    const on = () => { hover = { type: "edge", id: i }; render(); };
    const off = () => { hover = null; render(); };
    row.addEventListener("mouseenter", on); row.addEventListener("mouseleave", off);
    b.addEventListener("focus", on); b.addEventListener("blur", off);
  });
  edgeEls.forEach((el, i) => {
    el.addEventListener("mouseenter", () => { hover = { type: "edge", id: i }; render(); });
    el.addEventListener("mouseleave", () => { hover = null; render(); });
    el.addEventListener("click", () => { selected = { type: "edge", id: i }; render(); });
  });
  nodeEls.forEach((el, id) => {
    const toggle = () => { selected = selected && selected.type === "node" && selected.id === id ? null : { type: "node", id }; render(); };
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

  // On a phone the list is the object and the map sits behind a disclosure.
  const wrap = document.querySelector(".mapwrap");
  const phone = matchMedia("(max-width: 699.98px)");
  const place = () => { wrap.open = !phone.matches; };
  place();
  phone.addEventListener("change", place);

  // The survey pass: once, left to right, no loop. Motion preference decides; reduced motion keeps the finished sheet.
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
