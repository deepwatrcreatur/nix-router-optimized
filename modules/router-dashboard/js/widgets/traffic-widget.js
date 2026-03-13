/**
 * Traffic Graph Widget
 * Displays real-time bandwidth graphs for network interfaces
 */
class TrafficWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = config.title || 'Network Traffic';
    this.interface = config.interface || 'wan';
    this.widgetClass = 'widget-lg';
    this.chart = null;
    this.dataPoints = config.dataPoints || 60; // 5 minutes at 5s refresh
    this.history = {
      labels: [],
      rxData: [],
      txData: []
    };
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
        <select class="interface-select" id="${this.id}-iface">
          <option value="wan">WAN</option>
          <option value="lan">LAN</option>
          <option value="mgmt">MGMT</option>
        </select>
      </div>
      <div class="widget-body no-padding">
        <div class="traffic-chart-container">
          <canvas id="${this.id}-chart"></canvas>
        </div>
        <div class="traffic-legend">
          <div class="traffic-legend-item">
            <span class="traffic-legend-color rx"></span>
            <span>Download: <strong id="${this.id}-rx-rate">-- B/s</strong></span>
          </div>
          <div class="traffic-legend-item">
            <span class="traffic-legend-color tx"></span>
            <span>Upload: <strong id="${this.id}-tx-rate">-- B/s</strong></span>
          </div>
        </div>
      </div>
    `;
  }

  onMounted() {
    const ctx = document.getElementById(`${this.id}-chart`);
    if (!ctx) return;

    // Set initial interface
    const select = document.getElementById(`${this.id}-iface`);
    if (select) {
      select.value = this.interface;
      select.addEventListener('change', (e) => {
        this.interface = e.target.value;
        this.resetHistory();
      });
    }

    // Initialize Chart.js
    this.chart = new Chart(ctx, {
      type: 'line',
      data: {
        labels: this.history.labels,
        datasets: [
          {
            label: 'Download',
            data: this.history.rxData,
            borderColor: '#10b981',
            backgroundColor: 'rgba(16, 185, 129, 0.1)',
            fill: true,
            tension: 0.4,
            pointRadius: 0,
            borderWidth: 2
          },
          {
            label: 'Upload',
            data: this.history.txData,
            borderColor: '#3b82f6',
            backgroundColor: 'rgba(59, 130, 246, 0.1)',
            fill: true,
            tension: 0.4,
            pointRadius: 0,
            borderWidth: 2
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: {
          intersect: false,
          mode: 'index'
        },
        scales: {
          x: {
            display: false
          },
          y: {
            beginAtZero: true,
            grid: {
              color: 'rgba(148, 163, 184, 0.1)'
            },
            ticks: {
              color: '#94a3b8',
              callback: (value) => this.formatBytes(value, true)
            }
          }
        },
        plugins: {
          legend: {
            display: false
          },
          tooltip: {
            backgroundColor: 'rgba(15, 23, 42, 0.9)',
            titleColor: '#e2e8f0',
            bodyColor: '#e2e8f0',
            borderColor: '#334155',
            borderWidth: 1,
            callbacks: {
              label: (context) => {
                const label = context.dataset.label || '';
                const value = this.formatBytes(context.raw, true);
                return `${label}: ${value}`;
              }
            }
          }
        },
        animation: {
          duration: 0
        }
      }
    });
  }

  resetHistory() {
    this.history = {
      labels: [],
      rxData: [],
      txData: []
    };
    if (this.chart) {
      this.chart.data.labels = this.history.labels;
      this.chart.data.datasets[0].data = this.history.rxData;
      this.chart.data.datasets[1].data = this.history.txData;
      this.chart.update('none');
    }
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/interfaces/stats');
      const stats = data[this.interface];

      if (!stats) {
        console.warn(`No stats for interface: ${this.interface}`);
        return;
      }

      // Update history
      const now = new Date().toLocaleTimeString();
      this.history.labels.push(now);
      this.history.rxData.push(stats.rx_rate || 0);
      this.history.txData.push(stats.tx_rate || 0);

      // Keep only last N points
      while (this.history.labels.length > this.dataPoints) {
        this.history.labels.shift();
        this.history.rxData.shift();
        this.history.txData.shift();
      }

      // Update chart
      if (this.chart) {
        this.chart.update('none');
      }

      // Update legend values
      this.updateElement(`#${this.id}-rx-rate`, this.formatBytes(stats.rx_rate, true));
      this.updateElement(`#${this.id}-tx-rate`, this.formatBytes(stats.tx_rate, true));

      this.hideLoading();
    } catch (error) {
      console.error('Traffic widget error:', error);
    }
  }

  onDestroy() {
    super.onDestroy();
    if (this.chart) {
      this.chart.destroy();
      this.chart = null;
    }
  }
}

window.TrafficWidget = TrafficWidget;
