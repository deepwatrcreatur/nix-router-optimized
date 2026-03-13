/**
 * Services Widget
 * Displays systemd service status
 */
class ServicesWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = config.title || 'Services';
    this.widgetClass = 'widget-md';
    this.services = config.services || [
      'nftables',
      'caddy',
      'prometheus',
      'grafana',
      'netdata',
      'technitium-dns-server'
    ];
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
        <span class="status-badge status-up" id="${this.id}-summary">--/--</span>
      </div>
      <div class="widget-body no-padding">
        <table class="services-table">
          <thead>
            <tr>
              <th>Service</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody id="${this.id}-tbody">
            <tr><td colspan="2" class="loading">Loading...</td></tr>
          </tbody>
        </table>
      </div>
    `;
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/services/status');
      const services = data.services || [];

      // Count active services
      const active = services.filter(s => s.active).length;
      const total = services.length;

      // Update summary
      const summaryEl = this.container?.querySelector(`#${this.id}-summary`);
      if (summaryEl) {
        summaryEl.textContent = `${active}/${total}`;
        summaryEl.className = `status-badge ${active === total ? 'status-up' : 'status-warning'}`;
      }

      // Build table rows
      const tbody = this.container?.querySelector(`#${this.id}-tbody`);
      if (tbody) {
        tbody.innerHTML = services.map(s => this.renderServiceRow(s)).join('');
      }

      this.hideLoading();
    } catch (error) {
      console.error('Services widget error:', error);
    }
  }

  renderServiceRow(service) {
    const statusClass = service.active ? 'active' : (service.status === 'unknown' ? 'unknown' : 'inactive');
    const statusText = service.status || 'unknown';
    const displayName = this.formatServiceName(service.name);

    return `
      <tr>
        <td>${displayName}</td>
        <td>
          <span class="service-status">
            <span class="service-status-dot ${statusClass}"></span>
            ${statusText}
          </span>
        </td>
      </tr>
    `;
  }

  formatServiceName(name) {
    // Convert service names to readable format
    return name
      .replace('.service', '')
      .replace(/-/g, ' ')
      .replace(/\b\w/g, c => c.toUpperCase());
  }
}

window.ServicesWidget = ServicesWidget;
