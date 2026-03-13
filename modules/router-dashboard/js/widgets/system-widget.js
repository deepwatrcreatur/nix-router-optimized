/**
 * System Resources Widget
 * Displays CPU, Memory, and optionally Disk usage as gauges
 */
class SystemWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = config.title || 'System Resources';
    this.widgetClass = 'widget-md';
    this.cpuChart = null;
    this.memChart = null;
    this.showDisk = config.showDisk || false;
    this.diskChart = null;
  }

  getMarkup() {
    const diskGauge = this.showDisk ? `
      <div class="gauge-item">
        <canvas id="${this.id}-disk-gauge"></canvas>
        <div class="gauge-label">Disk</div>
        <div class="gauge-value" id="${this.id}-disk-value">--%</div>
        <div class="gauge-detail" id="${this.id}-disk-detail">-- / --</div>
      </div>
    ` : '';

    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
      </div>
      <div class="widget-body">
        <div class="gauge-container">
          <div class="gauge-item">
            <canvas id="${this.id}-cpu-gauge"></canvas>
            <div class="gauge-label">CPU</div>
            <div class="gauge-value" id="${this.id}-cpu-value">--%</div>
          </div>
          <div class="gauge-item">
            <canvas id="${this.id}-mem-gauge"></canvas>
            <div class="gauge-label">Memory</div>
            <div class="gauge-value" id="${this.id}-mem-value">--%</div>
            <div class="gauge-detail" id="${this.id}-mem-detail">-- / --</div>
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

  createGauge(elementId, color) {
    const ctx = document.getElementById(elementId);
    if (!ctx) return null;

    return new Chart(ctx, {
      type: 'doughnut',
      data: {
        datasets: [{
          data: [0, 100],
          backgroundColor: [color, '#1e293b'],
          borderWidth: 0,
          cutout: '75%',
          circumference: 180,
          rotation: 270
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: true,
        plugins: {
          legend: { display: false },
          tooltip: { enabled: false }
        },
        animation: {
          duration: 300
        }
      }
    });
  }

  onMounted() {
    this.cpuChart = this.createGauge(`${this.id}-cpu-gauge`, '#3b82f6');
    this.memChart = this.createGauge(`${this.id}-mem-gauge`, '#10b981');
    if (this.showDisk) {
      this.diskChart = this.createGauge(`${this.id}-disk-gauge`, '#f59e0b');
    }
  }

  updateGauge(chart, value) {
    if (!chart) return;
    const clamped = Math.min(100, Math.max(0, value));
    chart.data.datasets[0].data = [clamped, 100 - clamped];

    // Change color based on value
    let color = '#3b82f6'; // blue
    if (clamped > 90) {
      color = '#ef4444'; // red
    } else if (clamped > 70) {
      color = '#f59e0b'; // yellow
    } else if (clamped > 50) {
      color = '#10b981'; // green
    }
    chart.data.datasets[0].backgroundColor[0] = color;
    chart.update('none');
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/system/resources');

      // Update CPU
      const cpu = data.cpu || 0;
      this.updateGauge(this.cpuChart, cpu);
      this.updateElement(`#${this.id}-cpu-value`, this.formatPercent(cpu));

      // Update Memory
      const memory = data.memory || 0;
      this.updateGauge(this.memChart, memory);
      this.updateElement(`#${this.id}-mem-value`, this.formatPercent(memory));

      // Update memory detail (used / total)
      if (data.memory_used_human && data.memory_total_human) {
        this.updateElement(`#${this.id}-mem-detail`,
          `${data.memory_used_human} / ${data.memory_total_human}`);
      }

      // Update Disk if enabled
      if (this.showDisk && data.disk !== undefined) {
        this.updateGauge(this.diskChart, data.disk);
        this.updateElement(`#${this.id}-disk-value`, this.formatPercent(data.disk));

        // Update disk detail (used / total)
        if (data.disk_used_human && data.disk_total_human) {
          this.updateElement(`#${this.id}-disk-detail`,
            `${data.disk_used_human} / ${data.disk_total_human}`);
        }
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

  onDestroy() {
    super.onDestroy();
    if (this.cpuChart) {
      this.cpuChart.destroy();
      this.cpuChart = null;
    }
    if (this.memChart) {
      this.memChart.destroy();
      this.memChart = null;
    }
    if (this.diskChart) {
      this.diskChart.destroy();
      this.diskChart = null;
    }
  }
}

window.SystemWidget = SystemWidget;
