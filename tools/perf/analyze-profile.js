#!/usr/bin/env node
// Summarises palbonds-profile.log (written by Scripts/Profiler.lua when its
// PROFILING switch is on) by play phase.
//
//   node tools/perf/analyze-profile.js <palbonds-profile.log> [--phase "HH:MM:SS label" ...] [--top N]
//
// Phases are wall-clock start times, taken from the tester's own timeline
// (e.g. "12:47:41 idle", "12:49:41 walking", "12:54:41 fight"). Each report in
// the log is stamped with the wall time it was written, covering the ~10s
// before it, so a report belongs to the phase its stamp falls in.
//
// For each phase it prints, per system: total ms, total ms per minute of that
// phase, call count, worst single call, and how many calls were stalls
// (>= 8ms / >= 16ms as the profiler counted them). Then the STALL lines grouped
// by system: count, mean, max. Times are INCLUSIVE (a timer includes the world
// searches it made, which also appear on their own lines), so totals across
// systems overlap and must not be summed.

const fs = require("fs");

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith("--") && !isFlagValue(a));
function isFlagValue(a) {
  const i = args.indexOf(a);
  return i > 0 && (args[i - 1] === "--phase" || args[i - 1] === "--top");
}
if (!file) {
  console.error('usage: node analyze-profile.js <palbonds-profile.log> [--phase "HH:MM:SS label" ...] [--top N]');
  process.exit(1);
}
const phases = [];
let top = 15;
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--phase") {
    const m = /^(\d{1,2}):(\d{2}):(\d{2})\s+(.+)$/.exec(args[i + 1] || "");
    if (!m) throw new Error(`bad --phase "${args[i + 1]}", expected "HH:MM:SS label"`);
    phases.push({ at: +m[1] * 3600 + +m[2] * 60 + +m[3], label: m[4] });
  }
  if (args[i] === "--top") top = parseInt(args[i + 1], 10);
}
phases.sort((a, b) => a.at - b.at);

const text = fs.readFileSync(file, "utf8");
const reports = [];
let cur = null;
const headerRe = /^\[(\d{2}):(\d{2}):(\d{2})\] os\.clock elapsed ([0-9.]+)s \| wall elapsed (\d+)s \| window ([0-9.]+)s/;
const statRe = /^\s{2}(.+?)\s+calls\s+(\d+) \| total\s+([0-9.]+) ms \| avg\s+([0-9.]+) ms \| max\s+([0-9.]+) ms \| >=8ms\s+(\d+) \| >=16ms\s+(\d+)$/;
const stallRe = /^\s{2}STALL at ([0-9.]+)s\s+([0-9.]+) ms\s+(.+)$/;
for (const line of text.split(/\r?\n/)) {
  const h = headerRe.exec(line);
  if (h) {
    cur = { at: +h[1] * 3600 + +h[2] * 60 + +h[3], clock: +h[4], wall: +h[5], window: +h[6], stats: [], stalls: [] };
    reports.push(cur);
    continue;
  }
  if (!cur) continue;
  const s = statRe.exec(line);
  if (s) {
    cur.stats.push({ name: s[1].trim(), calls: +s[2], total: +s[3], max: +s[5], over8: +s[6], over16: +s[7] });
    continue;
  }
  const st = stallRe.exec(line);
  if (st) cur.stalls.push({ t: +st[1], ms: +st[2], name: st[3].trim() });
}
if (!reports.length) {
  console.error("no reports found in " + file);
  process.exit(1);
}

// Clock sanity: os.clock and wall elapsed must agree, or durations are suspect.
const last = reports[reports.length - 1];
const drift = Math.abs(last.clock - last.wall);
console.log(`${reports.length} reports, ${last.clock.toFixed(1)}s os.clock vs ${last.wall}s wall (drift ${drift.toFixed(1)}s${drift > 3 ? " — DURATIONS SUSPECT" : ", clock OK"})`);

const hms = (s) => `${String(Math.floor(s / 3600)).padStart(2, "0")}:${String(Math.floor((s % 3600) / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
const groups = phases.length
  ? phases.map((p, i) => ({ label: p.label, from: p.at, to: i + 1 < phases.length ? phases[i + 1].at : Infinity }))
  : [{ label: "whole session", from: -Infinity, to: Infinity }];
if (phases.length) groups.unshift({ label: "before first phase (loading)", from: -Infinity, to: phases[0].at });

for (const g of groups) {
  const rs = reports.filter((r) => r.at > g.from && r.at <= g.to + (g.to === Infinity ? 0 : 0));
  if (!rs.length) continue;
  const minutes = rs.reduce((a, r) => a + r.window, 0) / 60;
  const agg = new Map();
  for (const r of rs) {
    for (const s of r.stats) {
      const a = agg.get(s.name) || { name: s.name, calls: 0, total: 0, max: 0, over8: 0, over16: 0 };
      a.calls += s.calls;
      a.total += s.total;
      a.max = Math.max(a.max, s.max);
      a.over8 += s.over8;
      a.over16 += s.over16;
      agg.set(s.name, a);
    }
  }
  const stallAgg = new Map();
  for (const r of rs) {
    for (const st of r.stalls) {
      const a = stallAgg.get(st.name) || { name: st.name, n: 0, sum: 0, max: 0 };
      a.n++;
      a.sum += st.ms;
      a.max = Math.max(a.max, st.ms);
      stallAgg.set(st.name, a);
    }
  }
  const fromTxt = g.from === -Infinity ? "start" : hms(g.from);
  const toTxt = g.to === Infinity ? "end" : hms(g.to);
  console.log(`\n===== ${g.label}  [${fromTxt} -> ${toTxt}]  ${rs.length} reports, ${minutes.toFixed(1)} min`);
  console.log(`  ${"system".padEnd(74)} ${"ms/min".padStart(8)} ${"total ms".padStart(9)} ${"calls".padStart(7)} ${"max ms".padStart(7)} ${">=8".padStart(5)} ${">=16".padStart(5)}`);
  for (const a of [...agg.values()].sort((x, y) => y.total - x.total).slice(0, top)) {
    console.log(`  ${a.name.slice(0, 74).padEnd(74)} ${(a.total / minutes).toFixed(0).padStart(8)} ${a.total.toFixed(0).padStart(9)} ${String(a.calls).padStart(7)} ${a.max.toFixed(0).padStart(7)} ${String(a.over8).padStart(5)} ${String(a.over16).padStart(5)}`);
  }
  const stalls = [...stallAgg.values()].sort((x, y) => y.sum - x.sum).slice(0, top);
  if (stalls.length) {
    console.log(`  -- stall calls (>= 8ms) by system: count, per minute, mean, max`);
    for (const a of stalls) {
      console.log(`     ${a.name.slice(0, 72).padEnd(72)} ${String(a.n).padStart(5)} ${(a.n / minutes).toFixed(1).padStart(6)}/min  mean ${(a.sum / a.n).toFixed(0).padStart(4)} ms  max ${a.max.toFixed(0).padStart(4)} ms`);
    }
  }
}
