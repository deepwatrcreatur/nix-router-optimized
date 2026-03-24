/**
 * System Resources Widget
 * Displays CPU, Memory, and optionally Disk usage as CSS progress rings
 */
class SystemWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = config.title || 'System Resources';
    this.widgetClass = 'widget-md';
    this.showDisk = config.showDisk || false;
  }

  getMarkup() {
    const diskGauge = this.showDisk ? `
      <div class="gauge-item">
        <div class="progress-ring" id="${this.id}-disk-ring" style="--progress: 0; --ring-color: var(--gauge-disk);">
          <span class="progress-ring-value" id="${this.id}-disk-value">--%</span>
        </div>
        <div class="gauge-label">Disk</div>
      </div>
    ` : '';

    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
      </div>
      <div class="widget-body">
        <div class="gauge-container">
          <div class="gauge-item">
            <div class="progress-ring" id="${this.id}-cpu-ring" style="--progress: 0; --ring-color: var(--gauge-cpu);">
              <span class="progress-ring-value" id="${this.id}-cpu-value">--%</span>
            </div>
            <div class="gauge-label">CPU</div>
          </div>
          <div class="gauge-item">
            <div class="progress-ring" id="${this.id}-mem-ring" style="--progress: 0; --ring-color: var(--gauge-mem);">
              <span class="progress-ring-value" id="${this.id}-mem-value">--%</span>
            </div>
            <div class="gauge-label">Memory</div>
          </div>
          ${diskGauge}
        </div>
        <div class="stat-grid" style="margin-top: 15px;">
          <div class="metric metric-small">
            <div class="metric-label">Load Avg</div>
            <div class="metric-value" id="${this.id}-load">--</div>
          </div>
          <div class="metric metric-small">
            <div class="metric-label">Processes</div>
            <div class="metric-value" id="${this.id}-procs">--</div>
          </div>
        </div>
      </div>
    `;
  }

  updateRing(id, value) {
    const ring = document.getElementById(id);
    if (!ring) return;

    const clamped = Math.min(100, Math.max(0, value));

    // Color based on value threshold
    let color = '#f97316'; // orange (default)
    if (clamped > 90) {
      color = '#ef4444'; // red
    } else if (clamped > 70) {
      color = '#eab308'; // yellow
    } else if (clamped > 50) {
      color = '#22c55e'; // green
    }

    ring.style.setProperty('--progress', clamped);
    ring.style.setProperty('--ring-color', color);
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/system/resources');

      // Update CPU
      const cpu = data.cpu || 0;
      this.updateRing(`${this.id}-cpu-ring`, cpu);
      this.updateElement(`#${this.id}-cpu-value`, this.formatPercent(cpu));

      // Update Memory
      const memory = data.memory || 0;
      this.updateRing(`${this.id}-mem-ring`, memory);
      this.updateElement(`#${this.id}-mem-value`, this.formatPercent(memory));

      // Update Disk if enabled
      if (this.showDisk && data.disk !== undefined) {
        this.updateRing(`${this.id}-disk-ring`, data.disk);
        this.updateElement(`#${this.id}-disk-value`, this.formatPercent(data.disk));
      }

      // Update load average
      if (data.load_avg) {
        const loadStr = data.load_avg.slice(0, 3).join(' / ');
        this.updateElement(`#${this.id}-load`, loadStr);
      }

      // Update process count
      if (data.processes !== undefined) {
        this.updateElement(`#${this.id}-procs`, data.processes.toString());
      }

      this.hideLoading();
    } catch (error) {
      console.error('System widget error:', error);
    }
  }
}

window.SystemWidget = SystemWidget;
