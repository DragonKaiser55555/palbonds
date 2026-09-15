#!/usr/bin/env node
// Frame-time analysis for PresentMon CSV captures (microstutter investigation,
// started 2026-09-15). Usage:
//
//   node tools/perf/analyze-presentmon.js perf-captures/runA.csv [perf-captures/runB.csv ...]
//
// For each capture it reports: duration, frame count, average / median frame
// time, 1% and 0.1% lows, the number of hitches, and the repeating STALL
// SERIES. The series are the point of the exercise: the mod's suspected costs
// are timers (nameplate sweep every 2s, personality scan every 8s, Trust tick
// every 1.5s), so a stutter caused by one of them repeats at that period. A
// capture with the mod disabled should not show those periods.
//
// A "hitch" is a frame that took both at least HITCH_RATIO times the local
// median (the surrounding ~1s of frames, so camera changes and scenery do not
// count) and at least HITCH_MIN_EXTRA_MS longer than it. Hitch frames closer
// together than EVENT_MERGE_S are merged into one event, because a single
// stall often shows up as two or three slow frames in a row.
//
// Each event also reports the CPU-busy time of its worst frame. A mod stall
// happens on the game thread, so it shows up as CPU time; a spike with normal
// CPU time points somewhere else (GPU, driver, streaming).
//
// Column names differ between PresentMon builds. PresentMon 2.5.1 as shipped
// in Proyectos\_tools writes TimeInMs / MsBetweenPresents / MsCPUBusy; other
// 2.x builds write CPUStartTime / FrameTime / CPUBusy; 1.x writes
// TimeInSeconds / msBetweenPresents. All are accepted.

const fs = require("fs");
const path = require("path");

const HITCH_RATIO = 1.8;
const HITCH_MIN_EXTRA_MS = 6;
const LOCAL_WINDOW_FRAMES = 30; // each side
const EVENT_MERGE_S = 0.15;

// Series fitting. See find_series below.
const SERIES_MIN_S = 0.9;
const SERIES_MAX_S = 12.0;
const SERIES_STEP_S = 0.005;
const SERIES_TOLERANCE_S = 0.06;
const SERIES_MIN_SLOTS = 8;
const SERIES_MIN_COVERAGE = 0.6;
const SERIES_MAX_REPORT = 8;
const LOOKUP_RES_S = 0.005;

function parseCsv(file) {
  const lines = fs.readFileSync(file, "utf8").split(/\r?\n/).filter(Boolean);
  const header = lines[0].split(",");
  const col = (...names) => {
    for (const n of names) {
      const i = header.indexOf(n);
      if (i !== -1) return i;
    }
    return -1;
  };
  const iApp = col("Application");
  const iSwap = col("SwapChainAddress");
  const iTimeMs = col("TimeInMs");
  const iTime = iTimeMs !== -1 ? iTimeMs : col("CPUStartTime", "TimeInSeconds");
  const timeScale = iTimeMs !== -1 ? 0.001 : 1;
  const iFrame = col("MsBetweenPresents", "FrameTime", "msBetweenPresents");
  const iCpu = col("MsCPUBusy", "CPUBusy");
  if (iTime === -1 || iFrame === -1) {
    throw new Error(`${file}: no time/frame-time columns in header: ${header.join(",")}`);
  }
  // Group by swap chain and keep the busiest one: that is the game's main view.
  const chains = new Map();
  for (let r = 1; r < lines.length; r++) {
    const c = lines[r].split(",");
    const t = parseFloat(c[iTime]) * timeScale;
    const ft = parseFloat(c[iFrame]);
    if (!Number.isFinite(t) || !Number.isFinite(ft) || ft <= 0) continue;
    const cpu = iCpu >= 0 ? parseFloat(c[iCpu]) : NaN;
    const key = `${iApp >= 0 ? c[iApp] : ""}|${iSwap >= 0 ? c[iSwap] : ""}`;
    if (!chains.has(key)) chains.set(key, []);
    chains.get(key).push({ t, ft, cpu });
  }
  let best = null;
  for (const [key, rows] of chains) if (!best || rows.length > best.rows.length) best = { key, rows };
  if (!best) throw new Error(`${file}: no usable rows`);
  best.rows.sort((a, b) => a.t - b.t);
  // --range START-END (seconds from the first frame): analyse only that window,
  // e.g. the standing-still opening of a test run, so runs with different
  // later activity can still be compared like for like.
  if (RANGE) {
    const t0 = best.rows[0].t;
    best.rows = best.rows.filter((r) => r.t - t0 >= RANGE.from && r.t - t0 <= RANGE.to);
    if (!best.rows.length) throw new Error(`${file}: no frames inside --range ${RANGE.from}-${RANGE.to}`);
  }
  return { key: best.key, rows: best.rows, chainCount: chains.size };
}

function median(sorted) {
  const n = sorted.length;
  return n % 2 ? sorted[(n - 1) / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
}

// A timer that stalls the game produces events at anchor + k*period. Fitting
// (period, anchor) by coverage alone ranks a timer's MULTIPLES above the timer
// itself (every 2nd slot of a 1.53s timer is a 3.06s series with the same or
// better coverage), so this is greedy on explained events instead:
//
//   1. For every candidate period and every remaining event as anchor, count
//      the slots across the capture that hold a remaining event.
//   2. Score = hits minus the hits chance alone would give (slots times the
//      probability that a random slot window contains a remaining event).
//      Among series with coverage >= SERIES_MIN_COVERAGE, take the best score.
//   3. Remove that series' events and repeat.
//
// Because a base period explains more events than any of its multiples, and
// its events are removed before the next round, a multiple cannot be reported
// on its own. The mod's timers reschedule after their work finishes, so their
// measured period is their delay plus their own stall.
function find_series(events, duration) {
  const remaining = new Set(events.map((_, i) => i));
  const found = [];
  const lookupLen = Math.ceil(duration / LOOKUP_RES_S) + 2;
  while (found.length < SERIES_MAX_REPORT && remaining.size >= SERIES_MIN_SLOTS) {
    // nearest[k] = index of a remaining event within tolerance of k*res, or -1.
    const nearest = new Int32Array(lookupLen).fill(-1);
    const tolCells = Math.round(SERIES_TOLERANCE_S / LOOKUP_RES_S);
    for (const i of remaining) {
      const c = Math.round(events[i].t / LOOKUP_RES_S);
      for (let d = -tolCells; d <= tolCells; d++) {
        const k = c + d;
        if (k < 0 || k >= lookupLen) continue;
        const cur = nearest[k];
        if (cur === -1 || Math.abs(events[i].t - k * LOOKUP_RES_S) < Math.abs(events[cur].t - k * LOOKUP_RES_S)) {
          nearest[k] = i;
        }
      }
    }
    const chance = Math.min(1, (remaining.size * 2 * SERIES_TOLERANCE_S) / duration);
    let best = null;
    const anchors = [...remaining].map((i) => events[i].t);
    for (let p = SERIES_MIN_S; p <= SERIES_MAX_S + 1e-9; p += SERIES_STEP_S) {
      const seenPhase = new Set();
      for (const anchor of anchors) {
        const phase = anchor % p;
        const phaseKey = Math.round(phase / SERIES_TOLERANCE_S);
        if (seenPhase.has(phaseKey)) continue;
        seenPhase.add(phaseKey);
        const slots = Math.floor((duration - phase) / p) + 1;
        if (slots < SERIES_MIN_SLOTS) continue;
        let hits = 0;
        for (let k = 0; k < slots; k++) {
          if (nearest[Math.round((phase + k * p) / LOOKUP_RES_S)] !== -1) hits++;
        }
        const coverage = hits / slots;
        if (coverage < SERIES_MIN_COVERAGE) continue;
        const score = hits - slots * chance;
        if (!best || score > best.score) best = { p, phase, slots, hits, coverage, score };
      }
    }
    if (!best) break;
    const members = [];
    for (let k = 0; k < best.slots; k++) {
      const idx = nearest[Math.round((best.phase + k * best.p) / LOOKUP_RES_S)];
      if (idx !== -1 && remaining.has(idx)) members.push(idx);
    }
    if (!members.length) break;
    for (const idx of members) remaining.delete(idx);
    const ev = members.map((i) => events[i]);
    found.push({
      p: best.p,
      phase: best.phase,
      slots: best.slots,
      hits: members.length,
      coverage: members.length / best.slots,
      expectedByChance: best.slots * chance,
      meanWorst: ev.reduce((a, e) => a + e.worst, 0) / ev.length,
      meanExtra: ev.reduce((a, e) => a + e.extra, 0) / ev.length,
    });
  }
  return { series: found, unexplained: [...remaining].sort((a, b) => a - b).map((i) => events[i]) };
}

function analyse(file) {
  const { key, rows, chainCount } = parseCsv(file);
  const fts = rows.map((r) => r.ft);
  const sorted = [...fts].sort((a, b) => a - b);
  const duration = rows[rows.length - 1].t - rows[0].t;
  const avgFt = fts.reduce((a, b) => a + b, 0) / fts.length;
  const cpus = rows.map((r) => r.cpu).filter(Number.isFinite).sort((a, b) => a - b);

  // Lows: the average FPS of the slowest 1% / 0.1% of frames.
  const lowFps = (fraction) => {
    const n = Math.max(1, Math.floor(sorted.length * fraction));
    const worst = sorted.slice(sorted.length - n);
    return 1000 / (worst.reduce((a, b) => a + b, 0) / worst.length);
  };

  // Hitches against the local median.
  const hitches = [];
  for (let i = 0; i < rows.length; i++) {
    const lo = Math.max(0, i - LOCAL_WINDOW_FRAMES);
    const hi = Math.min(rows.length, i + LOCAL_WINDOW_FRAMES + 1);
    const local = fts.slice(lo, hi).sort((a, b) => a - b);
    const m = median(local);
    if (fts[i] >= m * HITCH_RATIO && fts[i] - m >= HITCH_MIN_EXTRA_MS) {
      hitches.push({ t: rows[i].t - rows[0].t, ft: fts[i], extra: fts[i] - m, cpu: rows[i].cpu });
    }
  }

  // Merge adjacent hitch frames into events.
  const events = [];
  for (const h of hitches) {
    const last = events[events.length - 1];
    if (last && h.t - last.tEnd <= EVENT_MERGE_S) {
      last.tEnd = h.t;
      last.frames++;
      last.extra += h.extra;
      if (h.ft > last.worst) {
        last.worst = h.ft;
        last.cpu = h.cpu;
      }
    } else {
      events.push({ t: h.t, tEnd: h.t, frames: 1, extra: h.extra, worst: h.ft, cpu: h.cpu });
    }
  }

  const { series, unexplained } = find_series(events, duration);

  return {
    file: path.basename(file),
    swapChain: key,
    chainCount,
    durationS: duration,
    frames: rows.length,
    avgFps: 1000 / avgFt,
    avgFtMs: avgFt,
    medianFtMs: median(sorted),
    p99FtMs: sorted[Math.floor(sorted.length * 0.99)],
    worstFtMs: sorted[sorted.length - 1],
    medianCpuMs: cpus.length ? median(cpus) : NaN,
    low1Fps: lowFps(0.01),
    low01Fps: lowFps(0.001),
    hitchFrames: hitches.length,
    hitchEvents: events.length,
    hitchEventsPerMin: events.length / (duration / 60),
    events,
    series,
    unexplained,
  };
}

const args = process.argv.slice(2);
const showEvents = args.includes("--events");
let RANGE = null;
const rangeAt = args.indexOf("--range");
if (rangeAt !== -1) {
  const m = /^(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)$/.exec(args[rangeAt + 1] || "");
  if (!m) {
    console.error('--range expects START-END in seconds from the first frame, e.g. --range 0-120');
    process.exit(1);
  }
  RANGE = { from: Number(m[1]), to: Number(m[2]) };
}
const files = args.filter((a, i) => a !== "--events" && a !== "--range" && !(rangeAt !== -1 && i === rangeAt + 1));
if (!files.length) {
  console.error("usage: node analyze-presentmon.js [--events] [--range START-END] <capture.csv> [more.csv ...]");
  process.exit(1);
}
if (RANGE) console.log(`(analysing only ${RANGE.from}s-${RANGE.to}s from each capture's first frame)`);
const f = (x, d = 1) => (Number.isFinite(x) ? x.toFixed(d) : "NA");
for (const file of files) {
  const a = analyse(file);
  console.log(`\n===== ${a.file}`);
  console.log(`swap chain: ${a.swapChain}  (${a.chainCount} chain(s) in file)`);
  console.log(`duration ${f(a.durationS)}s, ${a.frames} frames`);
  console.log(`avg ${f(a.avgFps)} fps (${f(a.avgFtMs, 2)} ms) | median ${f(a.medianFtMs, 2)} ms | p99 ${f(a.p99FtMs, 2)} ms | worst ${f(a.worstFtMs, 1)} ms | median CPU busy ${f(a.medianCpuMs, 2)} ms`);
  console.log(`1% low ${f(a.low1Fps)} fps | 0.1% low ${f(a.low01Fps)} fps`);
  console.log(`hitches: ${a.hitchFrames} frames in ${a.hitchEvents} events (${f(a.hitchEventsPerMin)}/min)`);
  console.log(`repeating stall series, strongest first (period | first at | stalled slots / expected | by chance alone | mean worst frame | mean extra):`);
  if (!a.series.length) console.log(`  none`);
  for (const s of a.series) {
    console.log(`  ${f(s.p, 3)}s | ${f(s.phase, 2)}s | ${s.hits}/${s.slots} (${f(s.coverage * 100, 0)}%) | ~${f(s.expectedByChance, 1)} | ${f(s.meanWorst, 0)} ms | +${f(s.meanExtra, 0)} ms`);
  }
  const ux = a.unexplained;
  console.log(`events in no series: ${ux.length} (${f(ux.length / (a.durationS / 60))}/min), mean worst ${f(ux.reduce((x, e) => x + e.worst, 0) / Math.max(1, ux.length), 0)} ms`);
  if (showEvents) {
    console.log(`events (t s | frames | worst ms | extra ms over local median | CPU busy ms of worst frame):`);
    console.log(a.events.map((e) => `${f(e.t, 2)}|${e.frames}|${f(e.worst, 0)}|${f(e.extra, 0)}|${f(e.cpu, 0)}`).join("  "));
  }
}
