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
    this.controlBoundary = null;
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
        <span class="status-badge status-up" id="${this.id}-summary">--/--</span>
      </div>
      <div class="service-control-panel">
        <div class="service-control-auth">
          <input type="password" id="${this.id}-token" class="service-control-token" placeholder="Dashboard mutation token">
          <button class="service-control-btn secondary" id="${this.id}-save-token">Unlock</button>
          <button class="service-control-btn secondary" id="${this.id}-clear-token">Clear</button>
        </div>
        <div class="service-control-note" id="${this.id}-control-note">Loading control boundary...</div>
      </div>
      <div class="widget-body no-padding">
        <table class="services-table">
          <thead>
            <tr>
              <th>Service</th>
              <th>Status</th>
              <th>Control</th>
            </tr>
          </thead>
          <tbody id="${this.id}-tbody">
            <tr><td colspan="3" class="loading">Loading...</td></tr>
          </tbody>
        </table>
      </div>
    `;
  }

  onMounted() {
    const tokenInput = this.container?.querySelector(`#${this.id}-token`);
    if (tokenInput) {
      tokenInput.value = this.getMutationToken();
    }

    this.container?.querySelector(`#${this.id}-save-token`)?.addEventListener('click', () => {
      this.setMutationToken(tokenInput?.value.trim() || '');
      this.updateControlNote();
    });

    this.container?.querySelector(`#${this.id}-clear-token`)?.addEventListener('click', () => {
      this.setMutationToken('');
      if (tokenInput) tokenInput.value = '';
      this.updateControlNote();
    });

    this.container?.addEventListener('click', event => {
      const button = event.target.closest('.service-action-btn');
      if (!button) return;

      const service = button.dataset.service;
      const action = button.dataset.action;
      if (service && action) {
        this.runServiceAction(service, action, button);
      }
    });
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/services/status');
      const services = data.services || [];
      this.controlBoundary = data.controlBoundary || null;

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

      this.updateControlNote();

      this.hideLoading();
    } catch (error) {
      console.error('Services widget error:', error);
    }
  }

  renderServiceRow(service) {
    const statusClass = service.active ? 'active' : (service.status === 'unknown' ? 'unknown' : 'inactive');
    const statusText = service.status || 'unknown';
    const displayName = this.formatServiceName(service.name);
    const control = service.control || { allowed: false, actions: [] };
    const controlCell = control.allowed
      ? `
        <button class="service-action-btn" data-service="${this.escape(service.name)}" data-action="restart">
          Restart
        </button>
      `
      : '<span class="service-control-readonly">Read-only</span>';

    return `
      <tr>
        <td>${displayName}</td>
        <td>
          <span class="service-status">
            <span class="service-status-dot ${statusClass}"></span>
            ${statusText}
          </span>
        </td>
        <td>${controlCell}</td>
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

  updateControlNote(message = '') {
    const noteEl = this.container?.querySelector(`#${this.id}-control-note`);
    if (!noteEl) return;

    if (message) {
      noteEl.textContent = message;
      return;
    }

    if (!this.controlBoundary) {
      noteEl.textContent = 'Loading control boundary...';
      return;
    }

    if (!this.controlBoundary.authConfigured) {
      noteEl.textContent = 'Mutations disabled: no dashboard mutation token is configured on this router.';
      return;
    }

    const unlocked = Boolean(this.getMutationToken());
    const controlled = (this.controlBoundary.serviceControl?.services || []).length;
    noteEl.textContent = unlocked
      ? `Mutations unlocked for this browser session. Restart is supported for ${controlled} allowlisted service${controlled === 1 ? '' : 's'}.`
      : `Mutations stay locked until you provide the dashboard token. Restart is supported for ${controlled} allowlisted service${controlled === 1 ? '' : 's'}.`;
  }

  async runServiceAction(service, action, button) {
    button.disabled = true;
    const previousLabel = button.textContent;
    button.textContent = 'Working...';
    this.updateControlNote(`Running ${action} on ${this.formatServiceName(service)}...`);

    try {
      await this.fetchMutationAPI('/services/control', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ service, action })
      });
      this.updateControlNote(`${this.formatServiceName(service)} ${action} requested successfully.`);
      await this.onTick();
    } catch (error) {
      this.updateControlNote(error.message || 'Service control failed');
    } finally {
      button.disabled = false;
      button.textContent = previousLabel;
    }
  }

  escape(value) {
    return String(value)
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }
}

window.ServicesWidget = ServicesWidget;
