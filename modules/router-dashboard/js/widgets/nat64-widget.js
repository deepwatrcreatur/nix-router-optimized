/**
 * NAT64 & DNS64 diagnostics widget
 * Shows Tayga status, NAT64 prefix, and active translations.
 */
class NAT64Widget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = 'NAT64 / DNS64';
    this.widgetClass = 'widget-md';
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>NAT64 / DNS64</h2>
        <span class="status-badge" id="${this.id}-status">--</span>
      </div>
      <div class="widget-body">
        <div class="diagnostic-grid">
          <div class="metric">
            <div class="metric-label">Prefix</div>
            <div class="metric-value metric-value-sm" id="${this.id}-prefix">--</div>
          </div>
          <div class="metric">
            <div class="metric-label">IPv4 Pool</div>
            <div class="metric-value metric-value-sm" id="${this.id}-pool">--</div>
          </div>
          <div class="metric">
            <div class="metric-label">Active Trans</div>
            <div class="metric-value metric-value-sm" id="${this.id}-active-count">0</div>
          </div>
        </div>

        <div class="metric-label" style="margin-top: 12px;">Active NAT64 Sessions</div>
        <div class="table-container nat64-table-container">
          <table class="nat64-table">
            <thead>
              <tr>
                <th>Proto</th>
                <th>Source</th>
                <th>Destination</th>
              </tr>
            </thead>
            <tbody id="${this.id}-connections">
              <tr><td colspan="3" class="text-center">Loading...</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    `;
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/nat64/connections');
      const statusEl = this.container?.querySelector(`#${this.id}-status`);

      if (statusEl) {
        if (data.enabled) {
          statusEl.className = 'status-badge status-up';
          statusEl.textContent = 'ENABLED';
        } else {
          statusEl.className = 'status-badge';
          statusEl.textContent = 'DISABLED';
        }
      }

      this.updateElement(`#${this.id}-prefix`, data.prefix || '--');
      this.updateElement(`#${this.id}-pool`, data.pool || '--');
      this.updateElement(`#${this.id}-active-count`, (data.connections || []).length);

      const tableBody = this.container?.querySelector(`#${this.id}-connections`);
      if (tableBody) {
        if (!data.enabled) {
          tableBody.innerHTML = '<tr><td colspan="3" class="text-center">NAT64 is not enabled</td></tr>';
        } else if (!data.connections || data.connections.length === 0) {
          tableBody.innerHTML = '<tr><td colspan="3" class="text-center">No active translations</td></tr>';
        } else {
          tableBody.innerHTML = data.connections.map(conn => `
            <tr>
              <td><span class="proto-tag proto-${conn.proto}">${conn.proto.toUpperCase()}</span></td>
              <td class="addr-cell" title="${conn.src}">${conn.src}</td>
              <td class="addr-cell" title="${conn.dst}">${conn.dst}</td>
            </tr>
          `).join('');
        }
      }

      this.hideLoading();
    } catch (error) {
      console.error('NAT64 widget error:', error);
      this.showError(error.message);
    }
  }
}

window.NAT64Widget = NAT64Widget;
