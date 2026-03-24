/**
 * DHCP Leases Widget
 * Displays DHCP lease information from Technitium DNS Server
 */
class DhcpWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = 'DHCP Leases';
    this.widgetClass = 'widget-lg';
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>DHCP Leases</h2>
        <span class="status-badge" id="${this.id}-status">--</span>
      </div>
      <div class="widget-body">
        <div class="dhcp-unavailable" id="${this.id}-unavailable" style="display: none;">
          <div style="text-align: center; color: var(--text-muted); padding: 20px;">
            <div style="font-size: 2rem; margin-bottom: 10px;">🔌</div>
            <div id="${this.id}-message">DHCP info unavailable</div>
          </div>
        </div>
        <div class="dhcp-content" id="${this.id}-content">
          <div class="dhcp-scopes" id="${this.id}-scopes" style="margin-bottom: 15px;"></div>
          <div class="dhcp-sections" id="${this.id}-sections" style="display: none;"></div>
          <div class="dhcp-table-container" style="max-height: 300px; overflow-y: auto;">
            <table class="data-table">
              <thead>
                <tr>
                  <th>IP Address</th>
                  <th>Hostname</th>
                  <th>MAC Address</th>
                  <th>Expires</th>
                </tr>
              </thead>
              <tbody id="${this.id}-leases">
                <tr><td colspan="4" style="text-align: center;">Loading...</td></tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    `;
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/dhcp/leases');

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
        if (msgEl) msgEl.textContent = data.message || 'DHCP info unavailable';
        this.hideLoading();
        return;
      }

      if (unavailableEl) unavailableEl.style.display = 'none';
      if (contentEl) contentEl.style.display = 'block';
      if (statusEl) {
        statusEl.className = 'status-badge status-up';
        statusEl.textContent = `${data.totalLeases || 0} LEASES`;
      }

      // Update scopes
      const scopesEl = this.container?.querySelector(`#${this.id}-scopes`);
      if (scopesEl && data.scopes) {
        scopesEl.innerHTML = data.scopes.map(scope => `
          <div class="dhcp-scope-badge ${scope.enabled ? 'scope-enabled' : 'scope-disabled'}">
            <span class="scope-name">${scope.name}</span>
            <span class="scope-range">${scope.startAddress} - ${scope.endAddress}</span>
            <span class="scope-count">${scope.leaseCount} leases</span>
          </div>
        `).join('');
      }

      // Update leases table
      const leasesEl = this.container?.querySelector(`#${this.id}-leases`);
      const sectionsEl = this.container?.querySelector(`#${this.id}-sections`);
      const hasMultipleSections = (data.sections || []).length > 1;

      if (sectionsEl) {
        if (hasMultipleSections) {
          sectionsEl.style.display = 'grid';
          sectionsEl.innerHTML = data.sections.map(section => `
            <div class="dhcp-section">
              <div class="dhcp-section-header">
                <div>
                  <div class="dhcp-section-title">${section.title}</div>
                  <div class="dhcp-section-meta">
                    Scope: ${section.scope}
                    ${section.startAddress && section.endAddress ? ` • ${section.startAddress} - ${section.endAddress}` : ''}
                  </div>
                </div>
                <span class="scope-count">${section.leaseCount} leases</span>
              </div>
              <div class="dhcp-table-container">
                <table class="data-table">
                  <thead>
                    <tr>
                      <th>IP Address</th>
                      <th>Hostname</th>
                      <th>MAC Address</th>
                      <th>Expires</th>
                    </tr>
                  </thead>
                  <tbody>
                    ${section.leases.length === 0
                      ? '<tr><td colspan="4" style="text-align: center; color: var(--text-muted);">No active leases</td></tr>'
                      : section.leases.map(lease => this.renderLeaseRow(lease)).join('')}
                  </tbody>
                </table>
              </div>
            </div>
          `).join('');
        } else {
          sectionsEl.style.display = 'none';
          sectionsEl.innerHTML = '';
        }
      }

      const tableContainer = this.container?.querySelector('.dhcp-content > .dhcp-table-container');
      if (tableContainer) {
        tableContainer.style.display = hasMultipleSections ? 'none' : 'block';
      }

      if (leasesEl && data.leases && !hasMultipleSections) {
        if (data.leases.length === 0) {
          leasesEl.innerHTML = '<tr><td colspan="4" style="text-align: center; color: var(--text-muted);">No active leases</td></tr>';
        } else {
          leasesEl.innerHTML = data.leases.map(lease => this.renderLeaseRow(lease)).join('');
        }
      }

      this.hideLoading();
    } catch (error) {
      console.error('DHCP widget error:', error);
    }
  }

  formatMac(mac) {
    if (!mac) return '--';
    // Format MAC address consistently
    return mac.toUpperCase().replace(/[:-]/g, ':');
  }

  formatExpiry(expiry) {
    if (!expiry) return '--';
    try {
      const date = new Date(expiry);
      const now = new Date();
      const diff = date - now;

      if (diff < 0) return '<span style="color: #ef4444;">Expired</span>';

      const hours = Math.floor(diff / (1000 * 60 * 60));
      const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));

      if (hours > 24) {
        const days = Math.floor(hours / 24);
        return `${days}d ${hours % 24}h`;
      }
      return `${hours}h ${minutes}m`;
    } catch {
      return expiry;
    }
  }

  renderLeaseRow(lease) {
    return `
      <tr>
        <td><code>${lease.address}</code></td>
        <td>${lease.hostname || '<em style="color: var(--text-muted);">unknown</em>'}</td>
        <td><code style="font-size: 0.85em;">${this.formatMac(lease.hardwareAddress)}</code></td>
        <td>${this.formatExpiry(lease.leaseExpires)}</td>
      </tr>
    `;
  }
}

window.DhcpWidget = DhcpWidget;
