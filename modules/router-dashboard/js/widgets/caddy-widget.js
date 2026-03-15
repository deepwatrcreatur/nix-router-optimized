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
      this.updateElement(`#${this.id}-token-state`, data.cloudflareToken?.readableByService ? 'readable' : 'blocked');
      this.updateElement(`#${this.id}-message`, data.message || 'No recent errors');

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
}

window.CaddyWidget = CaddyWidget;
