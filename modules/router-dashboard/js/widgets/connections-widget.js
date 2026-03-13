/**
 * Connections Widget
 * Displays connection tracking statistics
 */
class ConnectionsWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = config.title || 'Connections';
    this.widgetClass = 'widget-sm';
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
      </div>
      <div class="widget-body">
        <div class="metric">
          <div class="metric-label">Active Connections</div>
          <div class="metric-value" id="${this.id}-count">--</div>
        </div>
        <div class="metric metric-small">
          <div class="metric-label">Capacity</div>
          <div class="metric-value" id="${this.id}-max">--</div>
          <div class="progress-bar">
            <div class="progress-fill" id="${this.id}-progress" style="width: 0%"></div>
          </div>
        </div>
        <div class="stat-grid" style="margin-top: 15px;">
          <div class="metric metric-small">
            <div class="metric-label">TCP</div>
            <div class="metric-value" id="${this.id}-tcp">--</div>
          </div>
          <div class="metric metric-small">
            <div class="metric-label">UDP</div>
            <div class="metric-value" id="${this.id}-udp">--</div>
          </div>
        </div>
      </div>
    `;
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/connections/summary');

      // Update count
      const count = data.count || 0;
      const max = data.max || 262144;
      const percent = (count / max * 100);

      this.updateElement(`#${this.id}-count`, count.toLocaleString());
      this.updateElement(`#${this.id}-max`, max.toLocaleString());

      // Update progress bar
      const progressEl = this.container?.querySelector(`#${this.id}-progress`);
      if (progressEl) {
        progressEl.style.width = `${percent}%`;
        // Change color based on usage
        progressEl.classList.remove('green', 'yellow', 'red');
        if (percent > 80) {
          progressEl.classList.add('red');
        } else if (percent > 50) {
          progressEl.classList.add('yellow');
        } else {
          progressEl.classList.add('green');
        }
      }

      // Update protocol counts
      if (data.by_protocol) {
        this.updateElement(`#${this.id}-tcp`, (data.by_protocol.tcp || 0).toLocaleString());
        this.updateElement(`#${this.id}-udp`, (data.by_protocol.udp || 0).toLocaleString());
      }

      this.hideLoading();
    } catch (error) {
      console.error('Connections widget error:', error);
    }
  }
}

window.ConnectionsWidget = ConnectionsWidget;
