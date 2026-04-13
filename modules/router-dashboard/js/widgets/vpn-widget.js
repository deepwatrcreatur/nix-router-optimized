/**
 * VPN Status Widget
 * Displays router VPN unit and interface status.
 */
class VpnWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = config.title || 'VPN Status';
    this.widgetClass = 'widget-full vpn-widget';
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
            <h2>Loading VPN status</h2>
            <p>Reading router VPN service and interface state.</p>
          </div>
        </div>
      </div>
    `;
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/vpn/status');
      this.renderSummary(data);
      this.renderVpnList(data.vpns || []);
      this.hideLoading();
    } catch (error) {
      console.error('VPN widget error:', error);
      this.showError('Unable to load VPN status');
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

    summaryEl.textContent = configured === 0 ? 'No VPNs' : `${active}/${configured} up`;
    summaryEl.className = 'status-badge ' + this.getSummaryClass(configured, warning, down);
  }

  getSummaryClass(configured, warning, down) {
    if (configured === 0) return 'status-warning';
    if (down > 0) return 'status-down';
    if (warning > 0) return 'status-warning';
    return 'status-up';
  }

  renderVpnList(vpns) {
    const list = this.container?.querySelector(`#${this.id}-list`);
    if (!list) return;

    if (vpns.length === 0) {
      list.innerHTML = `
        <div class="dashboard-empty-state">
          <h2>No declarative VPNs configured</h2>
          <p>Enable router-wireguard, router-openvpn, router-tailscale, router-headscale, router-netbird, or router-zerotier to populate this tab.</p>
        </div>
      `;
      return;
    }

    list.innerHTML = vpns.map(vpn => this.renderVpnRow(vpn)).join('');
  }

  renderVpnRow(vpn) {
    const status = vpn.status || 'down';
    const service = vpn.service || {};
    const iface = vpn.interface || {};
    const details = vpn.details || {};
    const interfaceLabel = iface.name ? `${iface.name} (${iface.state || 'unknown'})` : 'none';

    return `
      <article class="vpn-row vpn-row-${status}">
        <div class="vpn-row-main">
          <div>
            <div class="vpn-name">${this.escape(vpn.name || vpn.kind || 'vpn')}</div>
            <div class="vpn-kind">${this.escape(vpn.kind || 'unknown')}</div>
          </div>
          <span class="status-badge ${this.statusClass(status)}">${status}</span>
        </div>
        <div class="vpn-row-grid">
          <div>
            <div class="vpn-label">Unit</div>
            <div class="vpn-value">${this.escape(vpn.unit || service.unit || '--')}</div>
          </div>
          <div>
            <div class="vpn-label">Service</div>
            <div class="vpn-value">${this.escape(service.status || 'unknown')}</div>
          </div>
          <div>
            <div class="vpn-label">Interface</div>
            <div class="vpn-value">${this.escape(interfaceLabel)}</div>
          </div>
          <div>
            <div class="vpn-label">Details</div>
            <div class="vpn-value">${this.renderDetails(details)}</div>
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

  renderDetails(details) {
    if (!details || Object.keys(details).length === 0) return '--';
    if (details.available === false) return this.escape(details.message || 'unavailable');

    const parts = [];
    if (details.peerCount !== undefined) parts.push(`${details.peerCount} peers`);
    if (details.backendState) parts.push(this.escape(details.backendState));
    if (details.latestHandshake) parts.push(`last handshake ${this.formatHandshake(details.latestHandshake)}`);
    return parts.length > 0 ? parts.join(' / ') : 'available';
  }

  formatHandshake(timestamp) {
    const date = new Date(timestamp * 1000);
    if (Number.isNaN(date.getTime())) return 'unknown';
    return date.toLocaleString();
  }

  escape(value) {
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }
}

window.VpnWidget = VpnWidget;
