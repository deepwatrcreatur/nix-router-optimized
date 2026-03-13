/**
 * Interface Status Widget
 * Displays a single network interface with stats and sparkline
 */
class InterfaceWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.interface = config.interface || 'wan';
    this.label = config.label || this.interface.toUpperCase();
    this.role = config.role || 'wan';
    this.title = this.label;
    this.widgetClass = `widget-sm interface-card ${this.role}`;
    this.sparkChart = null;
    this.sparkHistory = { rx: [], tx: [] };
    this.sparkPoints = 20;
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>${this.label}</h2>
        <span class="status-badge status-down" id="${this.id}-status">--</span>
      </div>
      <div class="widget-body">
        <div class="metric metric-small">
          <div class="metric-label">IPv4 Address</div>
          <div class="metric-value" id="${this.id}-ipv4">--</div>
        </div>
        <div class="stat-grid">
          <div class="metric metric-small">
            <div class="metric-label">RX</div>
            <div class="metric-value" id="${this.id}-rx" style="color: #10b981;">--</div>
          </div>
          <div class="metric metric-small">
            <div class="metric-label">TX</div>
            <div class="metric-value" id="${this.id}-tx" style="color: #3b82f6;">--</div>
          </div>
        </div>
        <div class="interface-sparkline">
          <canvas id="${this.id}-spark"></canvas>
        </div>
        <div class="stat-grid" style="margin-top: 10px;">
          <div class="metric metric-small">
            <div class="metric-label">Total RX</div>
            <div class="metric-value" id="${this.id}-rx-total" style="font-size: 0.9rem;">--</div>
          </div>
          <div class="metric metric-small">
            <div class="metric-label">Total TX</div>
            <div class="metric-value" id="${this.id}-tx-total" style="font-size: 0.9rem;">--</div>
          </div>
        </div>
      </div>
    `;
  }

  onMounted() {
    const ctx = document.getElementById(`${this.id}-spark`);
    if (!ctx) return;

    this.sparkChart = new Chart(ctx, {
      type: 'line',
      data: {
        labels: Array(this.sparkPoints).fill(''),
        datasets: [
          {
            data: this.sparkHistory.rx,
            borderColor: '#10b981',
            backgroundColor: 'rgba(16, 185, 129, 0.2)',
            fill: true,
            tension: 0.4,
            pointRadius: 0,
            borderWidth: 1.5
          },
          {
            data: this.sparkHistory.tx,
            borderColor: '#3b82f6',
            backgroundColor: 'rgba(59, 130, 246, 0.2)',
            fill: true,
            tension: 0.4,
            pointRadius: 0,
            borderWidth: 1.5
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: { display: false },
          y: {
            display: false,
            beginAtZero: true
          }
        },
        plugins: {
          legend: { display: false },
          tooltip: { enabled: false }
        },
        animation: { duration: 0 }
      }
    });
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/interfaces/stats');
      const stats = data[this.interface];

      if (!stats) {
        this.updateStatus('unknown', 'UNKNOWN');
        return;
      }

      // Update status badge
      const state = stats.state || 'UNKNOWN';
      const isUp = state === 'UP';
      this.updateStatus(isUp ? 'up' : 'down', state);

      // Update IP
      this.updateElement(`#${this.id}-ipv4`, stats.ipv4 || 'N/A');

      // Update current rates
      this.updateElement(`#${this.id}-rx`, this.formatBytes(stats.rx_rate, true));
      this.updateElement(`#${this.id}-tx`, this.formatBytes(stats.tx_rate, true));

      // Update totals
      this.updateElement(`#${this.id}-rx-total`, this.formatBytes(stats.rx_bytes));
      this.updateElement(`#${this.id}-tx-total`, this.formatBytes(stats.tx_bytes));

      // Update sparkline
      this.sparkHistory.rx.push(stats.rx_rate || 0);
      this.sparkHistory.tx.push(stats.tx_rate || 0);
      while (this.sparkHistory.rx.length > this.sparkPoints) {
        this.sparkHistory.rx.shift();
        this.sparkHistory.tx.shift();
      }
      if (this.sparkChart) {
        this.sparkChart.update('none');
      }

      this.hideLoading();
    } catch (error) {
      console.error('Interface widget error:', error);
    }
  }

  updateStatus(type, text) {
    const statusEl = this.container?.querySelector(`#${this.id}-status`);
    if (statusEl) {
      statusEl.className = `status-badge status-${type}`;
      statusEl.textContent = text;
    }
  }

  onDestroy() {
    super.onDestroy();
    if (this.sparkChart) {
      this.sparkChart.destroy();
      this.sparkChart = null;
    }
  }
}

window.InterfaceWidget = InterfaceWidget;
