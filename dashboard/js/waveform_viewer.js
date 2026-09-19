/**
 * waveform_viewer.js - Interactive In-Browser Digital Waveform Timing Viewer
 * Renders cycle-accurate logic transitions and multi-bit data buses on HTML5 Canvas.
 */

class WaveformViewer {
  constructor(canvasId, containerId) {
    this.canvas = document.getElementById(canvasId);
    this.container = document.getElementById(containerId);
    this.ctx = this.canvas.getContext('2d');

    this.waveData = null;
    this.zoomScale = 1.0; // pixels per timeunit
    this.minZoom = 0.1;
    this.maxZoom = 15.0;
    this.scrollX = 0;
    this.cursorTime = 0;

    this.labelWidth = 140;
    this.headerHeight = 32;
    this.rowHeight = 30;
    this.signalHeight = 16;

    this.setupEventListeners();
  }

  setupEventListeners() {
    this.canvas.addEventListener('mousemove', (e) => {
      const rect = this.canvas.getBoundingClientRect();
      const mouseX = e.clientX - rect.left;
      if (mouseX >= this.labelWidth) {
        const timePx = mouseX - this.labelWidth + this.scrollX;
        this.cursorTime = Math.max(0, Math.round(timePx / this.zoomScale));
        this.updateCursorDisplay();
        this.render();
      }
    });

    document.getElementById('btn-wave-zoom-in')?.addEventListener('click', () => {
      this.setZoom(this.zoomScale * 1.4);
    });

    document.getElementById('btn-wave-zoom-out')?.addEventListener('click', () => {
      this.setZoom(this.zoomScale / 1.4);
    });

    document.getElementById('btn-wave-zoom-reset')?.addEventListener('click', () => {
      this.fitToScreen();
    });
  }

  loadWaveform(data) {
    this.waveData = data;
    if (!data || !data.signals || data.signals.length === 0) {
      this.renderEmpty("No signal data found in waveform.");
      return;
    }

    const durationEl = document.getElementById('wave-max-time');
    const signalsEl = document.getElementById('wave-signals-count');
    if (durationEl) durationEl.textContent = `Duration: ${data.max_time} ${data.timescale}`;
    if (signalsEl) signalsEl.textContent = `Signals: ${data.signals.length}`;

    this.fitToScreen();
  }

  setZoom(newZoom) {
    this.zoomScale = Math.max(this.minZoom, Math.min(this.maxZoom, newZoom));
    this.render();
  }

  fitToScreen() {
    if (!this.waveData || !this.waveData.max_time) return;
    const availableWidth = this.container.clientWidth - this.labelWidth - 40;
    this.zoomScale = Math.max(this.minZoom, availableWidth / this.waveData.max_time);
    this.scrollX = 0;
    this.render();
  }

  updateCursorDisplay() {
    const el = document.getElementById('wave-time-cursor');
    if (el && this.waveData) {
      el.textContent = `Cursor: ${this.cursorTime} ${this.waveData.timescale}`;
    }
  }

  renderEmpty(msg = "Select and load a waveform above.") {
    const width = this.container.clientWidth || 800;
    const height = 360;
    this.canvas.width = width;
    this.canvas.height = height;

    this.ctx.fillStyle = '#080C14';
    this.ctx.fillRect(0, 0, width, height);
    this.ctx.fillStyle = '#64748B';
    this.ctx.font = '13px Inter, sans-serif';
    this.ctx.textAlign = 'center';
    this.ctx.fillText(msg, width / 2, height / 2);
  }

  render() {
    if (!this.waveData || !this.waveData.signals) {
      this.renderEmpty();
      return;
    }

    const signals = this.waveData.signals;
    const maxTime = this.waveData.max_time || 1000;
    const totalWaveWidth = Math.max(this.container.clientWidth, this.labelWidth + (maxTime * this.zoomScale) + 60);
    const totalHeight = this.headerHeight + (signals.length * this.rowHeight) + 20;

    this.canvas.width = totalWaveWidth;
    this.canvas.height = totalHeight;

    const ctx = this.ctx;
    ctx.clearRect(0, 0, totalWaveWidth, totalHeight);

    // Background
    ctx.fillStyle = '#080C14';
    ctx.fillRect(0, 0, totalWaveWidth, totalHeight);

    // Render Timeline Header
    ctx.fillStyle = '#0F1626';
    ctx.fillRect(0, 0, totalWaveWidth, this.headerHeight);
    ctx.strokeStyle = '#1E293B';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, this.headerHeight);
    ctx.lineTo(totalWaveWidth, this.headerHeight);
    ctx.stroke();

    // Time ticks
    const tickInterval = this.calculateTickInterval();
    ctx.fillStyle = '#64748B';
    ctx.font = '10px JetBrains Mono, monospace';
    ctx.textAlign = 'center';

    for (let t = 0; t <= maxTime; t += tickInterval) {
      const x = this.labelWidth + (t * this.zoomScale);
      ctx.beginPath();
      ctx.moveTo(x, this.headerHeight - 6);
      ctx.lineTo(x, this.headerHeight);
      ctx.strokeStyle = '#334155';
      ctx.stroke();

      // Grid line through canvas
      ctx.beginPath();
      ctx.moveTo(x, this.headerHeight);
      ctx.lineTo(x, totalHeight);
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.03)';
      ctx.stroke();

      ctx.fillText(`${t}ns`, x, this.headerHeight - 10);
    }

    // Render Signal Rows
    signals.forEach((sig, idx) => {
      const y = this.headerHeight + (idx * this.rowHeight);

      // Row alternate highlight
      if (idx % 2 === 1) {
        ctx.fillStyle = 'rgba(255, 255, 255, 0.015)';
        ctx.fillRect(0, y, totalWaveWidth, this.rowHeight);
      }

      // Divider line
      ctx.beginPath();
      ctx.moveTo(0, y + this.rowHeight);
      ctx.lineTo(totalWaveWidth, y + this.rowHeight);
      ctx.strokeStyle = 'rgba(30, 41, 59, 0.6)';
      ctx.stroke();

      // Render Label Sidebar
      ctx.fillStyle = '#0E1322';
      ctx.fillRect(0, y, this.labelWidth, this.rowHeight);
      ctx.fillStyle = sig.is_bus ? '#38BDF8' : '#F8FAFC';
      ctx.font = '12px JetBrains Mono, monospace';
      ctx.textAlign = 'left';
      ctx.fillText(sig.name, 14, y + 20);

      // Draw Waveform Transitions
      this.renderSignalWave(sig, y, maxTime);
    });

    // Left sidebar separator
    ctx.beginPath();
    ctx.moveTo(this.labelWidth, 0);
    ctx.lineTo(this.labelWidth, totalHeight);
    ctx.strokeStyle = '#334155';
    ctx.lineWidth = 1.5;
    ctx.stroke();

    // Render Vertical Time Cursor
    const cursorX = this.labelWidth + (this.cursorTime * this.zoomScale);
    if (cursorX >= this.labelWidth && cursorX <= totalWaveWidth) {
      ctx.beginPath();
      ctx.moveTo(cursorX, 0);
      ctx.lineTo(cursorX, totalHeight);
      ctx.strokeStyle = '#EF4444';
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 3]);
      ctx.stroke();
      ctx.setLineDash([]);
    }
  }

  calculateTickInterval() {
    const minPixelDistance = 60;
    const timePerMinPx = minPixelDistance / this.zoomScale;
    const intervals = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000];
    for (let intv of intervals) {
      if (intv >= timePerMinPx) return intv;
    }
    return 10000;
  }

  renderSignalWave(sig, rowY, maxTime) {
    const ctx = this.ctx;
    const transitions = sig.transitions;
    const topY = rowY + 6;
    const botY = topY + this.signalHeight;
    const midY = (topY + botY) / 2;

    if (!transitions || transitions.length === 0) return;

    if (!sig.is_bus) {
      // 1-Bit Logic Signal (0, 1, x, z)
      ctx.strokeStyle = sig.name.includes("clk") ? '#38BDF8' : (sig.name.includes("rst") ? '#F59E0B' : '#10B981');
      ctx.lineWidth = 1.8;
      ctx.beginPath();

      let currentLevel = botY;
      let lastX = this.labelWidth;

      for (let i = 0; i < transitions.length; i++) {
        const trans = transitions[i];
        const nextX = this.labelWidth + (trans.t * this.zoomScale);

        // Draw horizontal line to transition point
        ctx.lineTo(nextX, currentLevel);

        // Transition level
        const newLevel = (trans.v === '1') ? topY : botY;
        ctx.lineTo(nextX, newLevel);
        currentLevel = newLevel;
        lastX = nextX;
      }

      // Extend to end of time
      const finalX = this.labelWidth + (maxTime * this.zoomScale);
      ctx.lineTo(finalX, currentLevel);
      ctx.stroke();

    } else {
      // Multi-Bit Bus Signal (Hex Bubbles)
      for (let i = 0; i < transitions.length; i++) {
        const trans = transitions[i];
        const nextTrans = transitions[i + 1];
        const startX = this.labelWidth + (trans.t * this.zoomScale);
        const endX = nextTrans ? (this.labelWidth + (nextTrans.t * this.zoomScale)) : (this.labelWidth + (maxTime * this.zoomScale));
        const width = endX - startX;

        if (width <= 0) continue;

        // Draw Bus Hexagon Envelope
        ctx.fillStyle = 'rgba(6, 182, 212, 0.12)';
        ctx.strokeStyle = '#06B6D4';
        ctx.lineWidth = 1.2;

        ctx.beginPath();
        const bevel = Math.min(4, width / 2);
        ctx.moveTo(startX, midY);
        ctx.lineTo(startX + bevel, topY);
        ctx.lineTo(endX - bevel, topY);
        ctx.lineTo(endX, midY);
        ctx.lineTo(endX - bevel, botY);
        ctx.lineTo(startX + bevel, botY);
        ctx.closePath();
        ctx.fill();
        ctx.stroke();

        // Bus Value Text
        if (width > 24) {
          ctx.fillStyle = '#E2E8F0';
          ctx.font = '10px JetBrains Mono, monospace';
          ctx.textAlign = 'center';
          ctx.fillText(trans.v, startX + (width / 2), topY + 12);
        }
      }
    }
  }
}

// Global instance exposed for app.js
window.WaveformViewer = WaveformViewer;
