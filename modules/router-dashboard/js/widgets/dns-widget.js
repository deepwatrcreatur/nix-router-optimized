/**
 * DNS Statistics Widget
 * Displays Technitium DNS Server statistics
 */
class DnsWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = 'DNS Statistics';
    this.widgetClass = 'widget-md';
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>DNS Statistics</h2>
        <span class="status-badge" id="${this.id}-status">--</span>
      </div>
      <div class="widget-body">
        <div class="dns-unavailable" id="${this.id}-unavailable" style="display: none;">
          <div style="text-align: center; color: var(--text-muted); padding: 20px;">
            <div style="font-size: 2rem; margin-bottom: 10px;">🔇</div>
            <div id="${this.id}-message">DNS stats unavailable</div>
          </div>
        </div>
        <div class="dns-stats" id="${this.id}-stats">
          <div class="stat-grid dns-counters">
            <div class="metric">
              <div class="metric-value" id="${this.id}-queries">--</div>
              <div class="metric-label">Queries (1h)</div>
            </div>
            <div class="metric">
              <div class="metric-value" id="${this.id}-blocked" style="color: #ef4444;">--</div>
              <div class="metric-label">Blocked</div>
            </div>
            <div class="metric">
              <div class="metric-value" id="${this.id}-cached" style="color: #10b981;">--</div>
              <div class="metric-label">Cached</div>
            </div>
          </div>

          <div class="dns-rates" style="display: flex; gap: 20px; margin: 15px 0;">
            <div style="flex: 1;">
              <div class="metric-label">Block Rate</div>
              <div class="progress-bar">
                <div class="progress-fill" id="${this.id}-block-bar" style="background: #ef4444; width: 0%;"></div>
              </div>
              <div class="metric-value" id="${this.id}-block-rate" style="font-size: 0.9rem;">0%</div>
            </div>
            <div style="flex: 1;">
              <div class="metric-label">Cache Hit Rate</div>
              <div class="progress-bar">
                <div class="progress-fill" id="${this.id}-cache-bar" style="background: #10b981; width: 0%;"></div>
              </div>
              <div class="metric-value" id="${this.id}-cache-rate" style="font-size: 0.9rem;">0%</div>
            </div>
          </div>

          <div class="dns-lists" style="display: flex; gap: 15px; margin-top: 15px;">
            <div style="flex: 1;">
              <div class="metric-label" style="margin-bottom: 8px;">Top Domains</div>
              <div class="dns-list" id="${this.id}-domains"></div>
            </div>
            <div style="flex: 1;">
              <div class="metric-label" style="margin-bottom: 8px;">Top Clients</div>
              <div class="dns-list" id="${this.id}-clients"></div>
            </div>
          </div>
        </div>
      </div>
    `;
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/dns/stats');

      const unavailableEl = this.container?.querySelector(`#${this.id}-unavailable`);
      const statsEl = this.container?.querySelector(`#${this.id}-stats`);
      const statusEl = this.container?.querySelector(`#${this.id}-status`);

      if (!data.available) {
        if (unavailableEl) unavailableEl.style.display = 'block';
        if (statsEl) statsEl.style.display = 'none';
        if (statusEl) {
          statusEl.className = 'status-badge status-down';
          statusEl.textContent = 'OFFLINE';
        }
        const msgEl = this.container?.querySelector(`#${this.id}-message`);
        if (msgEl) msgEl.textContent = data.message || 'DNS stats unavailable';
        this.hideLoading();
        return;
      }

      if (unavailableEl) unavailableEl.style.display = 'none';
      if (statsEl) statsEl.style.display = 'block';
      if (statusEl) {
        statusEl.className = 'status-badge status-up';
        statusEl.textContent = 'ACTIVE';
      }

      // Update counters
      this.updateElement(`#${this.id}-queries`, this.formatNumber(data.totalQueries));
      this.updateElement(`#${this.id}-blocked`, this.formatNumber(data.totalBlocked));
      this.updateElement(`#${this.id}-cached`, this.formatNumber(data.totalCached));

      // Update rates
      const blockRate = data.blockRate || 0;
      const cacheRate = data.cacheRate || 0;
      this.updateElement(`#${this.id}-block-rate`, `${blockRate.toFixed(1)}%`);
      this.updateElement(`#${this.id}-cache-rate`, `${cacheRate.toFixed(1)}%`);

      const blockBar = this.container?.querySelector(`#${this.id}-block-bar`);
      const cacheBar = this.container?.querySelector(`#${this.id}-cache-bar`);
      if (blockBar) blockBar.style.width = `${Math.min(blockRate, 100)}%`;
      if (cacheBar) cacheBar.style.width = `${Math.min(cacheRate, 100)}%`;

      // Update top domains
      const domainsEl = this.container?.querySelector(`#${this.id}-domains`);
      if (domainsEl && data.topDomains) {
        domainsEl.innerHTML = data.topDomains.slice(0, 5).map(d => `
          <div class="dns-list-item">
            <span class="dns-domain">${this.truncate(d.name || d.domain, 25)}</span>
            <span class="dns-count">${this.formatNumber(d.hits || d.count)}</span>
          </div>
        `).join('') || '<div style="color: var(--text-muted); font-size: 0.85rem;">No data</div>';
      }

      // Update top clients
      const clientsEl = this.container?.querySelector(`#${this.id}-clients`);
      if (clientsEl && data.topClients) {
        clientsEl.innerHTML = data.topClients.slice(0, 5).map(c => `
          <div class="dns-list-item">
            <span class="dns-domain">${c.name || c.clientIpAddress || c.address}</span>
            <span class="dns-count">${this.formatNumber(c.hits || c.count)}</span>
          </div>
        `).join('') || '<div style="color: var(--text-muted); font-size: 0.85rem;">No data</div>';
      }

      this.hideLoading();
    } catch (error) {
      console.error('DNS widget error:', error);
    }
  }

  formatNumber(num) {
    if (num === undefined || num === null) return '--';
    if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
    if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
    return num.toString();
  }

  truncate(str, len) {
    if (!str) return '';
    return str.length > len ? str.substring(0, len) + '...' : str;
  }
}

window.DnsWidget = DnsWidget;
