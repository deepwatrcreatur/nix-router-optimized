/**
 * Fail2ban Widget
 * Displays Fail2ban jail status and banned IPs
 */
class Fail2banWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = 'Fail2ban';
    this.widgetClass = 'widget-md';
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>Fail2ban</h2>
        <span class="status-badge" id="${this.id}-status">--</span>
      </div>
      <div class="widget-body">
        <div class="f2b-unavailable" id="${this.id}-unavailable" style="display: none;">
          <div style="text-align: center; color: var(--text-muted); padding: 20px;">
            <div style="font-size: 2rem; margin-bottom: 10px;">🛡️</div>
            <div id="${this.id}-message">Fail2ban not available</div>
          </div>
        </div>
        <div class="f2b-content" id="${this.id}-content">
          <div class="f2b-summary" style="display: flex; gap: 15px; margin-bottom: 15px;">
            <div class="metric" style="flex: 1; text-align: center;">
              <div class="metric-value" id="${this.id}-banned" style="color: #ef4444;">--</div>
              <div class="metric-label">Currently Banned</div>
            </div>
            <div class="metric" style="flex: 1; text-align: center;">
              <div class="metric-value" id="${this.id}-jails" style="color: #10b981;">--</div>
              <div class="metric-label">Active Jails</div>
            </div>
          </div>

          <div class="f2b-jails" id="${this.id}-jails-list" style="margin-bottom: 15px;"></div>

          <div class="f2b-banned-section">
            <div class="metric-label" style="margin-bottom: 8px;">Banned IPs</div>
            <div class="f2b-banned-list" id="${this.id}-banned-list"></div>
          </div>
        </div>
      </div>
    `;
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/fail2ban/status');

      const unavailableEl = this.container?.querySelector(`#${this.id}-unavailable`);
      const contentEl = this.container?.querySelector(`#${this.id}-content`);
      const statusEl = this.container?.querySelector(`#${this.id}-status`);

      if (!data.available) {
        if (unavailableEl) unavailableEl.style.display = 'block';
        if (contentEl) contentEl.style.display = 'none';
        if (statusEl) {
          statusEl.className = 'status-badge status-down';
          statusEl.textContent = 'OFFLINE';
        }
        const msgEl = this.container?.querySelector(`#${this.id}-message`);
        if (msgEl) msgEl.textContent = data.message || 'Fail2ban not available';
        this.hideLoading();
        return;
      }

      if (unavailableEl) unavailableEl.style.display = 'none';
      if (contentEl) contentEl.style.display = 'block';
      if (statusEl) {
        const bannedCount = data.totalCurrentlyBanned || 0;
        statusEl.className = bannedCount > 0 ? 'status-badge status-warning' : 'status-badge status-up';
        statusEl.textContent = bannedCount > 0 ? `${bannedCount} BLOCKED` : 'ACTIVE';
      }

      // Update summary
      this.updateElement(`#${this.id}-banned`, data.totalCurrentlyBanned || 0);
      this.updateElement(`#${this.id}-jails`, data.jails?.length || 0);

      // Update jails list
      const jailsListEl = this.container?.querySelector(`#${this.id}-jails-list`);
      if (jailsListEl && data.jails) {
        jailsListEl.innerHTML = data.jails.map(jail => `
          <div class="f2b-jail-card">
            <div class="f2b-jail-header">
              <span class="f2b-jail-name">${jail.name}</span>
              <span class="f2b-jail-banned ${jail.currentlyBanned > 0 ? 'has-banned' : ''}">${jail.currentlyBanned} banned</span>
            </div>
            <div class="f2b-jail-stats">
              <span>Failed: ${jail.currentlyFailed}/${jail.totalFailed}</span>
              <span>Total bans: ${jail.totalBanned}</span>
            </div>
          </div>
        `).join('');
      }

      // Update banned IPs list
      const bannedListEl = this.container?.querySelector(`#${this.id}-banned-list`);
      if (bannedListEl) {
        const ips = data.allBannedIPs || [];
        if (ips.length === 0) {
          bannedListEl.innerHTML = '<div class="f2b-no-bans">No IPs currently banned</div>';
        } else {
          bannedListEl.innerHTML = ips.map(ip => `
            <div class="f2b-banned-ip">
              <span class="f2b-ip-badge">🚫</span>
              <code>${ip}</code>
            </div>
          `).join('');
        }
      }

      this.hideLoading();
    } catch (error) {
      console.error('Fail2ban widget error:', error);
    }
  }
}

window.Fail2banWidget = Fail2banWidget;
