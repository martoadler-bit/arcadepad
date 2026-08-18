const PAD_COLORS = ["#FF3333", "#FF8C0D", "#FFD90D", "#26D959", "#1ABFF2", "#BF40FF"];
const COLUMNS_BY_GRID_SIZE = { 4: 2, 8: 4, 12: 4, 16: 4 };

function publicDownloadURL(path) {
  const encoded = path.split("/").map(encodeURIComponent).join("/");
  return `${SUPABASE_PROJECT_URL}/storage/v1/object/public/share/${encoded}`;
}

function shareIDFromLocation() {
  return new URLSearchParams(window.location.search).get("id");
}

class KitPlayer {
  constructor() {
    this.audioContext = null;
    this.buffers = new Map(); // padIndex -> { forward: AudioBuffer, reversed: AudioBuffer|null }
    this.activeSources = new Map(); // padIndex -> AudioBufferSourceNode
  }

  ensureContext() {
    if (!this.audioContext) {
      this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
    }
    return this.audioContext;
  }

  /// iOS Safari/Chrome only let an AudioContext start if it's created/resumed synchronously
  /// inside a user-gesture handler — anything after an `await` (like our fetch+decode) is too
  /// late and gets silently ignored. Call this as the very first thing in the click handler,
  /// before any async work, so the context is already running by the time playback starts.
  unlockSync() {
    const ctx = this.ensureContext();
    if (ctx.state === "suspended") ctx.resume();
    const silent = ctx.createBuffer(1, 1, ctx.sampleRate);
    const source = ctx.createBufferSource();
    source.buffer = silent;
    source.connect(ctx.destination);
    source.start(0);
    return ctx;
  }

  async loadPad(pad) {
    const ctx = this.ensureContext();
    const response = await fetch(pad.audioURL);
    const arrayBuffer = await response.arrayBuffer();
    const forward = await ctx.decodeAudioData(arrayBuffer);
    this.buffers.set(pad.index, { forward, reversed: null });
  }

  reversedBuffer(pad, forward) {
    const ctx = this.ensureContext();
    const reversed = ctx.createBuffer(forward.numberOfChannels, forward.length, forward.sampleRate);
    for (let channel = 0; channel < forward.numberOfChannels; channel++) {
      const src = forward.getChannelData(channel);
      const dst = reversed.getChannelData(channel);
      for (let i = 0; i < src.length; i++) {
        dst[i] = src[src.length - 1 - i];
      }
    }
    return reversed;
  }

  play(pad) {
    const ctx = this.ensureContext();
    if (ctx.state === "suspended") ctx.resume();

    const entry = this.buffers.get(pad.index);
    if (!entry) return;

    this.stop(pad.index);

    let buffer = entry.forward;
    if (pad.mode === "reverse") {
      if (!entry.reversed) {
        entry.reversed = this.reversedBuffer(pad, entry.forward);
      }
      buffer = entry.reversed;
    }

    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.playbackRate.value = Math.pow(2, pad.pitchSemitones / 12);
    source.loop = pad.mode === "loop";

    const gain = ctx.createGain();
    gain.gain.value = pad.volume;
    source.connect(gain).connect(ctx.destination);

    const duration = buffer.duration;
    const startOffset = duration * pad.trimStart;
    const trimDuration = duration * (pad.trimEnd - pad.trimStart);

    if (source.loop) {
      source.loopStart = startOffset;
      source.loopEnd = duration * pad.trimEnd;
      source.start(0, startOffset);
    } else {
      source.start(0, startOffset, trimDuration);
    }

    this.activeSources.set(pad.index, source);
    source.onended = () => {
      if (this.activeSources.get(pad.index) === source) {
        this.activeSources.delete(pad.index);
      }
    };
  }

  stop(padIndex) {
    const existing = this.activeSources.get(padIndex);
    if (existing) {
      try { existing.stop(); } catch (e) { /* already stopped */ }
      this.activeSources.delete(padIndex);
    }
  }
}

async function main() {
  const content = document.getElementById("content");
  const shareID = shareIDFromLocation();

  if (!shareID) {
    content.innerHTML = '<div class="state">No kit ID in the URL.</div>';
    return;
  }

  const manifestURL = publicDownloadURL(`${shareID}/manifest.json`);

  let manifest;
  try {
    const response = await fetch(manifestURL);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    manifest = await response.json();
  } catch (err) {
    content.innerHTML = '<div class="state">Couldn\'t load this kit. The link may be wrong or expired.</div>';
    return;
  }

  document.getElementById("kit-name").textContent = manifest.name.toUpperCase();
  document.title = `ArcadePad — ${manifest.name}`;

  const columns = COLUMNS_BY_GRID_SIZE[manifest.gridSize] || 4;
  const grid = document.createElement("div");
  grid.className = "grid";
  grid.style.setProperty("--cols", columns);
  content.innerHTML = "";
  content.appendChild(grid);

  const player = new KitPlayer();
  const padsByIndex = new Map(manifest.pads.map((p) => [p.index, p]));

  for (let i = 0; i < manifest.gridSize; i++) {
    const pad = padsByIndex.get(i);
    const el = document.createElement("div");
    el.className = "pad";

    if (!pad) {
      el.style.background = "rgba(255,255,255,0.05)";
      el.style.opacity = "0.35";
      el.innerHTML = `<div class="name">EMPTY</div><div class="index">${i + 1}</div>`;
      grid.appendChild(el);
      continue;
    }

    el.style.background = PAD_COLORS[pad.colorIndex % PAD_COLORS.length];
    el.innerHTML = `
      <div class="name">${escapeHTML(pad.name)}</div>
      <div class="index">${i + 1}</div>
      <div class="mode">${pad.mode.toUpperCase()}</div>
    `;
    grid.appendChild(el);

    let loaded = false;
    el.addEventListener("click", () => {
      player.unlockSync(); // must run synchronously in the click handler, before any await
      el.classList.add("playing");
      setTimeout(() => el.classList.remove("playing"), 150);

      (async () => {
        if (!loaded) {
          loaded = true;
          try {
            await player.loadPad(pad);
          } catch (err) {
            loaded = false;
            return;
          }
        }
        player.play(pad);
      })();
    });
  }
}

function escapeHTML(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

main();
