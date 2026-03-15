/**
 * Caddy diagnostics widget
 * Shows service state, config validation, and recent startup errors.
 */
class CaddyWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = 'Caddy';
    this.widgetClass = 'widget-md';
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>Caddy</h2>
        <span class="status-badge" id="${this.id}-status">--</span>
      </div>
      <div class="widget-body">
        <div class="diagnostic-grid">
          <div class="metric">
            <div class="metric-label">Unit</div>
            <div class="metric-value metric-value-sm" id="${this.id}-unit-state">--</div>
          </div>
          <div class="metric">
            <div class="metric-label">Config</div>
            <div class="metric-value metric-value-sm" id="${this.id}-config-state">--</div>
          </div>
          <div class="metric">
            <div class="metric-label">Env File</div>
            <div class="metric-value metric-value-sm" id="${this.id}-env-state">--</div>
          </div>
          <div class="metric">
            <div class="metric-label">Cloudflare Token</div>
            <div class="metric-value metric-value-sm" id="${this.id}-token-state">--</div>
          </div>
        </div>

        <div class="metric-label" style="margin-top: 12px;">Dynamic DNS</div>
        <div class="caddy-dns-summary" id="${this.id}-dns-summary">Loading...</div>
        <div class="caddy-dns-list" id="${this.id}-dns-list">Loading...</div>

        <div class="metric-label" style="margin-top: 12px;">Last Error</div>
        <div class="diagnostic-message" id="${this.id}-message">Loading...</div>

        <div class="metric-label" style="margin-top: 12px;">Recent Logs</div>
        <div class="diagnostic-log" id="${this.id}-logs">Loading...</div>
      </div>
    `;
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/caddy/status');
      const statusEl = this.container?.querySelector(`#${this.id}-status`);

      if (statusEl) {
        if (data.active) {
          statusEl.className = 'status-badge status-up';
          statusEl.textContent = 'ACTIVE';
        } else if (data.result === 'exit-code' || data.result === 'failed') {
          statusEl.className = 'status-badge status-down';
          statusEl.textContent = 'FAILED';
        } else {
          statusEl.className = 'status-badge status-warning';
          statusEl.textContent = (data.activeState || 'unknown').toUpperCase();
        }
      }

      this.updateElement(`#${this.id}-unit-state`, `${data.activeState || '--'} / ${data.subState || '--'}`);
      this.updateElement(`#${this.id}-config-state`, data.configValid ? 'valid' : 'invalid');
      this.updateElement(`#${this.id}-env-state`, data.environmentFile?.present ? 'present' : 'missing');
      this.updateElement(
        `#${this.id}-token-state`,
        data.cloudflareToken?.usableForValidation ? 'available' : (data.cloudflareToken?.exists ? 'present' : 'missing')
      );
      this.updateElement(`#${this.id}-message`, data.message || 'No current errors');
      this.renderDnsStatus(data.dnsStatus);

      const logsEl = this.container?.querySelector(`#${this.id}-logs`);
      if (logsEl) {
        logsEl.textContent = (data.logs || []).join('\n') || 'No recent logs';
      }

      this.hideLoading();
    } catch (error) {
      console.error('Caddy widget error:', error);
      this.showError(error.message);
    }
  }

  renderDnsStatus(dnsStatus) {
    const summaryEl = this.container?.querySelector(`#${this.id}-dns-summary`);
    const listEl = this.container?.querySelector(`#${this.id}-dns-list`);
    if (!summaryEl || !listEl) {
      return;
    }

    if (!dnsStatus?.available) {
      summaryEl.textContent = dnsStatus?.message || 'Dynamic DNS unavailable';
      listEl.innerHTML = '';
      return;
    }

    const wanIpv4 = dnsStatus.wanIpv4 || '--';
    const wanIpv6 = (dnsStatus.wanIpv6 || []).slice(0, 2).join(', ') || '--';
    summaryEl.innerHTML = `
      <div><strong>WAN IPv4:</strong> ${wanIpv4}</div>
      <div><strong>WAN IPv6:</strong> ${wanIpv6}</div>
    `;

    listEl.innerHTML = (dnsStatus.domains || []).map(domain => {
      const statusClass = this.getDnsStatusClass(domain.status);
      const records = (domain.records || []).map(record => `${record.type} ${record.content}`).join(' | ') || 'No records';
      return `
        <div class="caddy-dns-row">
          <div class="caddy-dns-row-main">
            <span class="status-dot ${statusClass}"></span>
            <span class="caddy-dns-name">${domain.name}</span>
            <span class="caddy-dns-state">${domain.status}</span>
          </div>
          <div class="caddy-dns-records">${records}</div>
        </div>
      `;
    }).join('') || '<div class="caddy-dns-empty">No managed domains</div>';
  }

  getDnsStatusClass(status) {
    switch (status) {
      case 'current':
        return 'status-up';
      case 'partial':
        return 'status-warning';
      case 'stale':
      case 'missing':
      case 'zone-missing':
        return 'status-down';
      default:
        return '';
    }
  }
}

window.CaddyWidget = CaddyWidget;
