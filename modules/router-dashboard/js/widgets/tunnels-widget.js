/**
 * Tunnels Status Widget
 * Displays application tunnel status (zrok/ngrok/other).
 */
class TunnelsWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = config.title || 'Tunnels';
    this.widgetClass = 'widget-full tunnels-widget';
    this.refreshInterval = config.refreshInterval || 15000;
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
        <span class="status-badge status-warning" id="${this.id}-summary">Loading</span>
      </div>
      <div class="widget-body no-padding">
        <div class="vpn-summary-row" id="${this.id}-summary-row">
          <div class="metric metric-small">
            <div class="metric-label">Configured</div>
            <div class="metric-value" id="${this.id}-configured">--</div>
          </div>
          <div class="metric metric-small">
            <div class="metric-label">Up</div>
            <div class="metric-value" id="${this.id}-active">--</div>
          </div>
          <div class="metric metric-small">
            <div class="metric-label">Warning</div>
            <div class="metric-value" id="${this.id}-warning">--</div>
          </div>
          <div class="metric metric-small">
            <div class="metric-label">Down</div>
            <div class="metric-value" id="${this.id}-down">--</div>
          </div>
        </div>
        <div class="vpn-list" id="${this.id}-list">
          <div class="dashboard-empty-state">
            <h2>Loading tunnel status</h2>
            <p>Reading router tunnel service state.</p>
          </div>
        </div>
      </div>
    `;
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/api/tunnels/status');
      this.renderSummary(data);
      this.renderTunnelList(data.tunnels || []);
      this.hideLoading();
    } catch (error) {
      console.error('Tunnels widget error:', error);
      this.renderErrorState('Unable to load tunnels status');
    }
  }

  renderSummary(data) {
    const configured = data.configured || 0;
    const active = data.active || 0;
    const warning = data.warning || 0;
    const down = data.down || 0;

    this.updateElement(`#${this.id}-configured`, configured.toString());
    this.updateElement(`#${this.id}-active`, active.toString());
    this.updateElement(`#${this.id}-warning`, warning.toString());
    this.updateElement(`#${this.id}-down`, down.toString());

    const summaryEl = this.container?.querySelector(`#${this.id}-summary`);
    if (!summaryEl) return;

    summaryEl.textContent = configured === 0 ? 'No tunnels' : `${active}/${configured} up`;
    summaryEl.className = 'status-badge ' + this.getSummaryClass(configured, warning, down);
  }

  getSummaryClass(configured, warning, down) {
    if (configured === 0) return 'status-warning';
    if (down > 0) return 'status-down';
    if (warning > 0) return 'status-warning';
    return 'status-up';
  }

  renderTunnelList(tunnels) {
    const list = this.container?.querySelector(`#${this.id}-list`);
    if (!list) return;

    if (tunnels.length === 0) {
      list.innerHTML = `
        <div class="dashboard-empty-state">
          <h2>No declarative tunnels configured</h2>
          <p>Define services.router-tunnels.tunnels entries (e.g., zrok/ngrok) to populate this tab.</p>
        </div>
      `;
      return;
    }

    list.innerHTML = tunnels.map(tunnel => this.renderTunnelRow(tunnel)).join('');
  }

  renderTunnelRow(tunnel) {
    const status = this.normalizeStatus(tunnel.status);
    const service = tunnel.service || {};
    const publicUrl = tunnel.publicUrl || (tunnel.details && tunnel.details.publicUrl) || '';

    return `
      <article class="vpn-row vpn-row-${status}">
        <div class="vpn-row-main">
          <div>
            <div class="vpn-name">${this.escape(tunnel.name || 'tunnel')}</div>
            <div class="vpn-kind">${this.escape(tunnel.provider || 'other')}</div>
          </div>
          <span class="status-badge ${this.statusClass(status)}">${status}</span>
        </div>
        <div class="vpn-row-grid">
          <div>
            <div class="vpn-label">Unit</div>
            <div class="vpn-value">${this.escape(tunnel.unit || service.unit || '--')}</div>
          </div>
          <div>
            <div class="vpn-label">Service</div>
            <div class="vpn-value">${this.escape(service.status || 'unknown')}</div>
          </div>
          <div>
            <div class="vpn-label">Public URL</div>
            <div class="vpn-value">${publicUrl ? `<a href="${this.escape(publicUrl)}" target="_blank" rel="noopener">${this.escape(publicUrl)}</a>` : '--'}</div>
          </div>
          <div>
            <div class="vpn-label">Details</div>
            <div class="vpn-value">${this.escape((tunnel.details && tunnel.details.description) || '')}</div>
          </div>
        </div>
      </article>
    `;
  }

  statusClass(status) {
    if (status === 'up') return 'status-up';
    if (status === 'warning') return 'status-warning';
    return 'status-down';
  }

  normalizeStatus(status) {
    return [ 'up', 'warning', 'down' ].includes(status) ? status : 'down';
  }

  renderErrorState(message) {
    const summaryEl = this.container?.querySelector(`#${this.id}-summary`);
    if (summaryEl) {
      summaryEl.textContent = 'Error';
      summaryEl.className = 'status-badge status-down';
    }

    const list = this.container?.querySelector(`#${this.id}-list`);
    if (list) {
      list.innerHTML = `<div class="error-message">${this.escape(message)}</div>`;
    }
  }

  escape(value) {
    return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }
}

window.TunnelsWidget = TunnelsWidget;
