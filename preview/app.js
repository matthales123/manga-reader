const $ = (id) => document.getElementById(id);

const THEME_OPTIONS = ["system", "light", "dark"];

const state = {
  apiBase: localStorage.getItem("preview_api_base") || "http://127.0.0.1:8080",
  mockMode: localStorage.getItem("preview_mock_mode") === "true",
  singlePageMode: localStorage.getItem("preview_single_page") === "true",
  themeMode: localStorage.getItem("preview_theme_mode") || "system",
  currentView: "library",
  history: [],
  selectedSeries: null,
  selectedVolume: null,
  series: [],
  volumes: [],
  pages: [],
  currentPage: 0,
  imageRefreshNonce: 0,
  progressByVolume: JSON.parse(localStorage.getItem("preview_progress") || "{}"),
};

const mockData = {
  series: [
    {
      id: "s1",
      title: "One Piece",
      volume_count: 3,
      cover_url:
        "https://images.unsplash.com/photo-1515879218367-8466d910aaa4?auto=format&fit=crop&w=640&q=60",
    },
    {
      id: "s2",
      title: "Dandadan",
      volume_count: 2,
      cover_url:
        "https://images.unsplash.com/photo-1517976547714-720226b864c1?auto=format&fit=crop&w=640&q=60",
    },
    {
      id: "s3",
      title: "Berserk",
      volume_count: 4,
      cover_url:
        "https://images.unsplash.com/photo-1516541196182-6bdb0516ed27?auto=format&fit=crop&w=640&q=60",
    },
  ],
  volumesBySeries: {
    s1: [
      { id: "s1-v1", title: "Vol 001", kind: "archive" },
      { id: "s1-v2", title: "Vol 002", kind: "archive" },
      { id: "s1-v3", title: "Vol 003", kind: "archive" },
    ],
    s2: [
      { id: "s2-v1", title: "Vol 001", kind: "directory" },
      { id: "s2-v2", title: "Vol 002", kind: "directory" },
    ],
    s3: [
      { id: "s3-v1", title: "Deluxe 01", kind: "archive" },
      { id: "s3-v2", title: "Deluxe 02", kind: "archive" },
      { id: "s3-v3", title: "Deluxe 03", kind: "archive" },
      { id: "s3-v4", title: "Deluxe 04", kind: "archive" },
    ],
  },
  pagesByVolume: (volumeId) =>
    Array.from({ length: 12 }, (_, i) => ({
      index: i,
      name: `${String(i + 1).padStart(3, "0")}.jpg`,
      url: `mock://${volumeId}/${i}`,
    })),
};

const el = {
  apiBaseInput: $("api-base"),
  connectBtn: $("connect-btn"),
  mockToggle: $("mock-toggle"),
  singlePageToggle: $("single-page-toggle"),
  themeBtn: $("theme-btn"),
  status: $("status"),
  content: $("content"),
  screenTitle: $("screen-title"),
  screenSubtitle: $("screen-subtitle"),
  screen: document.querySelector(".phone-screen"),
  backBtn: $("back-btn"),
  refreshBtn: $("refresh-btn"),
  tabLibrary: $("tab-library"),
  tabReader: $("tab-reader"),
  rowTemplate: $("row-template"),
};

const systemThemeQuery = window.matchMedia("(prefers-color-scheme: dark)");

function joinUrl(base, path) {
  return `${base.replace(/\/$/, "")}${path.startsWith("/") ? path : `/${path}`}`;
}

function resolveCoverUrl(coverUrl) {
  if (!coverUrl) {
    return null;
  }
  if (coverUrl.startsWith("http://") || coverUrl.startsWith("https://")) {
    return coverUrl;
  }
  return joinUrl(state.apiBase, coverUrl);
}

function setStatus(message, kind = "muted") {
  el.status.className = `status ${kind}`;
  el.status.textContent = message;
}

function setLoadingSkeleton(rows = 5) {
  el.content.innerHTML = "";
  for (let i = 0; i < rows; i += 1) {
    const sk = document.createElement("div");
    sk.className = "skeleton";
    el.content.appendChild(sk);
  }
}

function setMessage(text) {
  el.content.innerHTML = "";
  const m = document.createElement("div");
  m.className = "message";
  m.textContent = text;
  el.content.appendChild(m);
}

function saveProgressState() {
  localStorage.setItem("preview_progress", JSON.stringify(state.progressByVolume));
}

function readProgress(volumeId) {
  return state.progressByVolume[volumeId] || null;
}

function writeProgress(volumeId, totalPages) {
  if (!volumeId) {
    return;
  }
  const lastPageRead = Math.max(1, state.currentPage + 1);
  const known = state.progressByVolume[volumeId] || { pagesRead: 0, lastPage: 1, totalPages: totalPages || 0 };
  state.progressByVolume[volumeId] = {
    pagesRead: Math.max(known.pagesRead || 0, lastPageRead),
    lastPage: lastPageRead,
    totalPages: totalPages || known.totalPages || 0,
  };
  saveProgressState();
}

function applyTheme() {
  const resolvedTheme =
    state.themeMode === "system" ? (systemThemeQuery.matches ? "dark" : "light") : state.themeMode;

  el.screen.classList.toggle("theme-dark", resolvedTheme === "dark");
  el.themeBtn.textContent = state.themeMode === "system" ? "◐" : state.themeMode === "dark" ? "☾" : "☼";
  el.themeBtn.title = `Theme: ${state.themeMode}`;
}

function cycleThemeMode() {
  const currentIndex = THEME_OPTIONS.indexOf(state.themeMode);
  const next = THEME_OPTIONS[(currentIndex + 1) % THEME_OPTIONS.length];
  state.themeMode = next;
  localStorage.setItem("preview_theme_mode", next);
  applyTheme();
  setStatus(`Theme set to ${next}.`, "success");
}

async function request(path) {
  const url = joinUrl(state.apiBase, path);
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} on ${path}`);
  }
  return res.json();
}

async function loadSeries() {
  setLoadingSkeleton();
  state.currentView = "library";

  if (state.mockMode) {
    await sleep(140);
    state.series = mockData.series;
    renderSeries();
    setStatus("Loaded demo library.", "success");
    return;
  }

  const data = await request("/api/library/series");
  state.series = data.items || [];
  renderSeries();
  setStatus(`Connected to ${state.apiBase}`, "success");
}

async function loadVolumes(series, options = {}) {
  const { preserveHistory = false } = options;

  setLoadingSkeleton();
  state.selectedSeries = series;
  state.currentView = "volumes";
  state.selectedVolume = null;

  if (!preserveHistory) {
    state.history.push("library");
  }

  if (state.mockMode) {
    await sleep(100);
    state.volumes = mockData.volumesBySeries[series.id] || [];
    renderVolumes();
    return;
  }

  const data = await request(`/api/library/series/${series.id}/volumes`);
  state.volumes = data.items || [];
  renderVolumes();
}

async function loadPages(volume, options = {}) {
  const {
    preserveHistory = false,
    preservePage = false,
    refreshCurrentPageOnly = false,
  } = options;

  if (!refreshCurrentPageOnly) {
    setLoadingSkeleton(3);
  }

  state.selectedVolume = volume;
  state.currentView = "reader";

  if (!preserveHistory) {
    state.history.push("volumes");
  }

  const previousPage = state.currentPage;

  if (refreshCurrentPageOnly) {
    // Keep position and force image reload cache-bust
    state.imageRefreshNonce += 1;
    writeProgress(volume.id, state.pages.length);
    renderReader();
    setStatus("Current page refreshed.", "success");
    return;
  }

  if (state.mockMode) {
    await sleep(100);
    state.pages = mockData.pagesByVolume(volume.id);
  } else {
    const data = await request(`/api/library/volumes/${volume.id}/pages`);
    state.pages = data.items || [];
  }

  if (preservePage) {
    state.currentPage = Math.min(previousPage, Math.max(state.pages.length - 1, 0));
  } else {
    const saved = readProgress(volume.id);
    state.currentPage = saved ? Math.min(Math.max(saved.lastPage - 1, 0), Math.max(state.pages.length - 1, 0)) : 0;
  }

  writeProgress(volume.id, state.pages.length);
  renderReader();
}

function makeRow(main, meta, coverUrl, onClick) {
  const row = el.rowTemplate.content.firstElementChild.cloneNode(true);
  const img = row.querySelector(".row-cover");

  row.querySelector(".row-main").textContent = main;
  row.querySelector(".row-meta").textContent = meta;

  if (coverUrl) {
    img.src = coverUrl;
    img.alt = `${main} cover`;
  } else {
    img.src = coverPlaceholder(main);
    img.alt = `${main} placeholder cover`;
  }

  img.onerror = () => {
    img.src = coverPlaceholder(main);
  };

  row.addEventListener("click", onClick);
  return row;
}

function coverPlaceholder(title) {
  const label = title.slice(0, 24);
  const svg = `<svg xmlns='http://www.w3.org/2000/svg' width='280' height='280'>
    <defs>
      <linearGradient id='g' x1='0' x2='1' y1='0' y2='1'>
        <stop offset='0' stop-color='#f5d5b1' />
        <stop offset='1' stop-color='#d9c0a1' />
      </linearGradient>
    </defs>
    <rect width='100%' height='100%' fill='url(#g)' />
    <text x='140' y='146' text-anchor='middle' font-family='Georgia' font-size='28' fill='#2c3d40'>${label}</text>
  </svg>`;
  return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
}

function updateHeader() {
  const backVisible = state.history.length > 0;
  el.backBtn.classList.toggle("is-hidden", !backVisible);
  el.backBtn.setAttribute("aria-hidden", String(!backVisible));

  if (state.currentView === "library") {
    el.screenTitle.textContent = "Manga";
    el.screenSubtitle.textContent = state.mockMode ? "Demo Library" : "Library";
  } else if (state.currentView === "volumes") {
    el.screenTitle.textContent = state.selectedSeries?.title || "Volumes";
    el.screenSubtitle.textContent = `${state.volumes.length} volumes`;
  } else {
    el.screenTitle.textContent = state.selectedVolume?.title || "Reader";
    el.screenSubtitle.textContent = `${state.pages.length} pages`;
  }

  el.tabLibrary.classList.toggle("active", state.currentView !== "reader");
  el.tabReader.classList.toggle("active", state.currentView === "reader");
  el.tabReader.disabled = !state.selectedVolume;
}

function renderSeries() {
  updateHeader();
  el.content.innerHTML = "";

  if (!state.series.length) {
    setMessage(
      "No series found. Check MANGA_ROOT in backend/.env or toggle demo mode to preview the UI without server data."
    );
    return;
  }

  state.series.forEach((series) => {
    const meta = `${series.volume_count ?? series.volumeCount ?? 0} volumes`;
    const cover = resolveCoverUrl(series.cover_url);
    el.content.appendChild(
      makeRow(series.title, meta, cover, () => {
        loadVolumes(series).catch(handleError);
      })
    );
  });
}

function progressLabelFor(volume) {
  const p = readProgress(volume.id);
  if (!p || !p.totalPages) {
    return volume.kind || "volume";
  }

  if (p.pagesRead >= p.totalPages) {
    return `Complete (${p.totalPages}/${p.totalPages})`;
  }

  return `Read ${p.pagesRead}/${p.totalPages}`;
}

function renderVolumes() {
  updateHeader();
  el.content.innerHTML = "";

  if (!state.volumes.length) {
    setMessage("No volumes were detected for this series.");
    return;
  }

  const cover = resolveCoverUrl(state.selectedSeries?.cover_url || null);

  state.volumes.forEach((volume) => {
    const meta = progressLabelFor(volume);
    el.content.appendChild(
      makeRow(volume.title, meta, cover, () => {
        loadPages(volume).catch(handleError);
      })
    );
  });
}

function resolvePageImageUrl(page) {
  if (!page) {
    return null;
  }

  if (state.mockMode || (typeof page.url === "string" && page.url.startsWith("mock://"))) {
    const palette = ["#f4d6b8", "#d6ede6", "#d9d8f4", "#f3d9dc"];
    const color = palette[page.index % palette.length];
    const label = `Page ${page.index + 1}`;
    const volumeLabel = state.selectedVolume?.title || "Demo Volume";
    const svg = `<svg xmlns='http://www.w3.org/2000/svg' width='1000' height='1400'>
      <rect width='100%' height='100%' fill='${color}' />
      <rect x='60' y='60' width='880' height='1280' rx='36' fill='white' opacity='0.42'/>
      <text x='500' y='700' text-anchor='middle' font-family='Georgia' font-size='84' fill='#1a2a2d'>${label}</text>
      <text x='500' y='786' text-anchor='middle' font-family='monospace' font-size='28' fill='#395256'>${volumeLabel}</text>
    </svg>`;
    return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
  }

  let url = typeof page.url === "string" && page.url.startsWith("http")
    ? page.url
    : joinUrl(state.apiBase, page.url);

  const separator = url.includes("?") ? "&" : "?";
  url += `${separator}r=${state.imageRefreshNonce}`;
  return url;
}

function renderReader() {
  updateHeader();
  el.content.innerHTML = "";

  if (!state.pages.length) {
    setMessage("No pages in this volume.");
    return;
  }

  const reader = document.createElement("div");
  reader.className = "reader";

  const pageShell = document.createElement("div");
  pageShell.className = "page-shell";
  reader.appendChild(pageShell);

  const controls = document.createElement("div");
  controls.className = "reader-controls";

  const prevBtn = document.createElement("button");
  prevBtn.textContent = "Previous";

  const counter = document.createElement("div");
  counter.className = "page-counter";

  const nextBtn = document.createElement("button");
  nextBtn.textContent = "Next";

  controls.append(prevBtn, counter, nextBtn);
  reader.appendChild(controls);
  el.content.appendChild(reader);

  let touchStartX = 0;
  pageShell.addEventListener("touchstart", (event) => {
    touchStartX = event.changedTouches[0].clientX;
  });

  pageShell.addEventListener("touchend", (event) => {
    const deltaX = event.changedTouches[0].clientX - touchStartX;
    if (Math.abs(deltaX) < 35) {
      return;
    }
    if (deltaX < 0) {
      gotoPage(state.currentPage + 1);
    } else {
      gotoPage(state.currentPage - 1);
    }
  });

  const gotoPage = (index) => {
    if (index < 0 || index >= state.pages.length) {
      return;
    }
    state.currentPage = index;
    writeProgress(state.selectedVolume?.id, state.pages.length);
    drawCurrentPage();
  };

  const drawCurrentPage = () => {
    const page = state.pages[state.currentPage];
    const imageUrl = resolvePageImageUrl(page);

    pageShell.innerHTML = "";

    if (imageUrl) {
      const img = document.createElement("img");
      img.src = imageUrl;
      img.alt = page.name || `Page ${page.index + 1}`;
      img.loading = "lazy";
      img.onerror = () => {
        pageShell.innerHTML = `<div class='page-fallback'>Image failed to load for ${page.name || "this page"}.</div>`;
      };
      pageShell.appendChild(img);
    } else {
      pageShell.innerHTML = "<div class='page-fallback'>Missing page URL.</div>";
    }

    counter.textContent = `Page ${state.currentPage + 1} / ${state.pages.length}`;
    prevBtn.disabled = state.currentPage === 0;
    nextBtn.disabled = state.currentPage === state.pages.length - 1;

    if (state.singlePageMode) {
      pageShell.style.maxHeight = "560px";
    } else {
      pageShell.style.maxHeight = "none";
    }
  };

  prevBtn.addEventListener("click", () => gotoPage(state.currentPage - 1));
  nextBtn.addEventListener("click", () => gotoPage(state.currentPage + 1));

  drawCurrentPage();
}

function handleError(error) {
  console.error(error);
  setStatus(error.message || "Request failed.", "error");
  setMessage(
    "Could not load data from backend. Check API URL and CORS settings, or switch on demo mode to continue UI testing."
  );
}

function goBack() {
  const prev = state.history.pop();
  if (!prev) {
    return;
  }

  if (state.currentView === "reader") {
    writeProgress(state.selectedVolume?.id, state.pages.length);
  }

  if (prev === "library") {
    state.currentView = "library";
    state.selectedSeries = null;
    state.selectedVolume = null;
    renderSeries();
  } else if (prev === "volumes") {
    state.currentView = "volumes";
    state.selectedVolume = null;
    renderVolumes();
  }
}

function connectAndLoad() {
  state.apiBase = el.apiBaseInput.value.trim().replace(/\/$/, "");
  localStorage.setItem("preview_api_base", state.apiBase);

  state.history = [];
  state.selectedSeries = null;
  state.selectedVolume = null;
  loadSeries().catch(handleError);
}

function refreshCurrentView() {
  if (state.currentView === "library") {
    loadSeries().catch(handleError);
    return;
  }

  if (state.currentView === "volumes") {
    loadVolumes(state.selectedSeries, { preserveHistory: true }).catch(handleError);
    return;
  }

  if (state.currentView === "reader") {
    loadPages(state.selectedVolume, {
      preserveHistory: true,
      preservePage: true,
      refreshCurrentPageOnly: true,
    }).catch(handleError);
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function bootstrap() {
  el.apiBaseInput.value = state.apiBase;
  el.mockToggle.checked = state.mockMode;
  el.singlePageToggle.checked = state.singlePageMode;

  applyTheme();

  systemThemeQuery.addEventListener("change", () => {
    if (state.themeMode === "system") {
      applyTheme();
    }
  });

  el.connectBtn.addEventListener("click", connectAndLoad);
  el.refreshBtn.addEventListener("click", refreshCurrentView);
  el.themeBtn.addEventListener("click", cycleThemeMode);
  el.backBtn.addEventListener("click", goBack);

  el.tabLibrary.addEventListener("click", () => {
    if (state.currentView === "reader") {
      writeProgress(state.selectedVolume?.id, state.pages.length);
    }
    state.currentView = "library";
    state.history = [];
    renderSeries();
  });

  el.tabReader.addEventListener("click", () => {
    if (state.selectedVolume && state.pages.length) {
      state.currentView = "reader";
      renderReader();
    }
  });

  el.mockToggle.addEventListener("change", () => {
    state.mockMode = el.mockToggle.checked;
    localStorage.setItem("preview_mock_mode", String(state.mockMode));
    state.history = [];
    state.selectedSeries = null;
    state.selectedVolume = null;
    state.currentView = "library";

    if (state.mockMode) {
      setStatus("Demo mode enabled.", "success");
      loadSeries().catch(handleError);
    } else {
      setStatus("Demo mode disabled. Connecting to backend...", "muted");
      connectAndLoad();
    }
  });

  el.singlePageToggle.addEventListener("change", () => {
    state.singlePageMode = el.singlePageToggle.checked;
    localStorage.setItem("preview_single_page", String(state.singlePageMode));
    if (state.currentView === "reader") {
      renderReader();
    }
  });

  document.addEventListener("keydown", (event) => {
    if (state.currentView !== "reader") {
      return;
    }
    if (event.key === "ArrowRight") {
      state.currentPage = Math.min(state.currentPage + 1, state.pages.length - 1);
      writeProgress(state.selectedVolume?.id, state.pages.length);
      renderReader();
    }
    if (event.key === "ArrowLeft") {
      state.currentPage = Math.max(state.currentPage - 1, 0);
      writeProgress(state.selectedVolume?.id, state.pages.length);
      renderReader();
    }
  });

  setStatus("Connecting...", "muted");
  loadSeries().catch((error) => {
    setStatus(`Backend unavailable (${error.message}). Turn on demo mode to preview UI.`, "error");
    setMessage(
      "Connection failed. You can still test the full interface by toggling 'Use demo data'."
    );
  });
}

bootstrap();
