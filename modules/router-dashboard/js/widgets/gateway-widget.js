/**
 * Gateway Health Widget
 * Monitors latency and packet loss to upstream gateways
 */
class GatewayWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = config.title || 'Gateway Health';
    this.widgetClass = 'widget-md';
    this.refreshInterval = config.refreshInterval || 10000; // 10 seconds
    this.latencyChart = null;
    this.historyLength = 30; // 5 minutes at 10s intervals
    this.history = {};
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
        <span class="status-badge status-up" id="${this.id}-status">--</span>
      </div>
      <div class="widget-body">
        <div class="gateway-targets" id="${this.id}-targets">
          <div class="loading">Checking gateways...</div>
        </div>
        <div class="latency-chart-container" style="height: 120px; margin-top: 15px;">
          <canvas id="${this.id}-chart"></canvas>
        </div>
      </div>
    `;
  }

  onMounted() {
    const ctx = document.getElementById(`${this.id}-chart`);
    if (!ctx) return;

    this.latencyChart = new Chart(ctx, {
      type: 'line',
      data: {
        labels: [],
        datasets: []
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: {
          intersect: false,
          mode: 'index'
        },
        scales: {
          x: { display: false },
          y: {
            beginAtZero: true,
            title: {
              display: true,
              text: 'ms',
              color: '#94a3b8'
            },
            grid: { color: 'rgba(148, 163, 184, 0.1)' },
            ticks: { color: '#94a3b8' }
          }
        },
        plugins: {
          legend: {
            display: true,
            position: 'bottom',
            labels: { color: '#94a3b8', boxWidth: 12 }
          },
          tooltip: {
            backgroundColor: 'rgba(15, 23, 42, 0.9)',
            titleColor: '#e2e8f0',
            bodyColor: '#e2e8f0'
          }
        },
        animation: { duration: 0 }
      }
    });
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/gateway/health');

      // Update targets display
      const targetsEl = this.container?.querySelector(`#${this.id}-targets`);
      if (targetsEl && data.targets) {
        targetsEl.innerHTML = data.targets.map(t => this.renderTarget(t)).join('');
      }

      // Update overall status
      const allUp = data.targets?.every(t => t.status === 'up');
      const someUp = data.targets?.some(t => t.status === 'up');
      const statusEl = this.container?.querySelector(`#${this.id}-status`);
      if (statusEl) {
        if (allUp) {
          statusEl.className = 'status-badge status-up';
          statusEl.textContent = 'ALL OK';
        } else if (someUp) {
          statusEl.className = 'status-badge status-warning';
          statusEl.textContent = 'DEGRADED';
        } else {
          statusEl.className = 'status-badge status-down';
          statusEl.textContent = 'DOWN';
        }
      }

      // Update chart
      this.updateChart(data.targets || []);

      this.hideLoading();
    } catch (error) {
      console.error('Gateway widget error:', error);
    }
  }

  renderTarget(target) {
    const statusClass = target.status === 'up' ? 'up' : 'down';
    const latencyColor = target.latency < 20 ? '#10b981' :
                         target.latency < 50 ? '#f59e0b' : '#ef4444';

    return `
      <div class="gateway-target">
        <div class="gateway-target-info">
          <span class="gateway-target-name">${target.name}</span>
          <span class="gateway-target-host">${target.host}</span>
        </div>
        <div class="gateway-target-stats">
          <span class="gateway-latency" style="color: ${latencyColor}">
            ${target.latency !== null ? target.latency.toFixed(1) + ' ms' : '--'}
          </span>
          <span class="gateway-loss ${target.loss > 0 ? 'has-loss' : ''}">
            ${target.loss !== null ? target.loss.toFixed(0) + '% loss' : ''}
          </span>
        </div>
        <span class="status-dot status-${statusClass}"></span>
      </div>
    `;
  }

  updateChart(targets) {
    if (!this.latencyChart) return;

    const now = new Date().toLocaleTimeString();
    const colors = ['#3b82f6', '#10b981', '#f59e0b', '#8b5cf6'];

    // Initialize history for new targets
    targets.forEach((t, i) => {
      if (!this.history[t.name]) {
        this.history[t.name] = [];
      }
      this.history[t.name].push(t.latency || 0);
      if (this.history[t.name].length > this.historyLength) {
        this.history[t.name].shift();
      }
    });

    // Update chart data
    this.latencyChart.data.labels = Array(this.historyLength).fill('').map((_, i) => '');
    this.latencyChart.data.datasets = targets.map((t, i) => ({
      label: t.name,
      data: this.history[t.name] || [],
      borderColor: colors[i % colors.length],
      backgroundColor: 'transparent',
      tension: 0.4,
      pointRadius: 0,
      borderWidth: 2
    }));

    this.latencyChart.update('none');
  }

  onDestroy() {
    super.onDestroy();
    if (this.latencyChart) {
      this.latencyChart.destroy();
      this.latencyChart = null;
    }
  }
}

window.GatewayWidget = GatewayWidget;
