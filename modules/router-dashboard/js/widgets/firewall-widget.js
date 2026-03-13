/**
 * Firewall Stats Widget
 * Shows nftables statistics and flowtable info
 */
class FirewallWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = config.title || 'Firewall';
    this.widgetClass = 'widget-sm';
    this.refreshInterval = config.refreshInterval || 30000; // 30 seconds
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
        <span class="status-badge status-up" id="${this.id}-status">Active</span>
      </div>
      <div class="widget-body">
        <div class="stat-grid">
          <div class="metric metric-small">
            <div class="metric-label">Rules</div>
            <div class="metric-value" id="${this.id}-rules">--</div>
          </div>
          <div class="metric metric-small">
            <div class="metric-label">Flowtable</div>
            <div class="metric-value" id="${this.id}-flowtable">--</div>
          </div>
        </div>
        <div class="metric" style="margin-top: 10px;">
          <div class="metric-label">Offloaded Flows</div>
          <div class="metric-value" id="${this.id}-offloaded" style="font-size: 1.3rem;">--</div>
        </div>
        <div class="stat-grid" style="margin-top: 10px;">
          <div class="metric metric-small">
            <div class="metric-label">Packets In</div>
            <div class="metric-value" id="${this.id}-pkts-in" style="font-size: 0.95rem;">--</div>
          </div>
          <div class="metric metric-small">
            <div class="metric-label">Packets Out</div>
            <div class="metric-value" id="${this.id}-pkts-out" style="font-size: 0.95rem;">--</div>
          </div>
        </div>
      </div>
    `;
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/firewall/stats');

      this.updateElement(`#${this.id}-rules`, data.rules_count?.toString() || '--');

      const flowtableEl = this.container?.querySelector(`#${this.id}-flowtable`);
      if (flowtableEl) {
        if (data.flowtable_active) {
          flowtableEl.textContent = 'ON';
          flowtableEl.style.color = '#10b981';
        } else {
          flowtableEl.textContent = 'OFF';
          flowtableEl.style.color = '#f59e0b';
        }
      }

      this.updateElement(`#${this.id}-offloaded`,
        data.offloaded_flows?.toLocaleString() || '--');

      // Format packet counts
      if (data.packets_in !== undefined) {
        this.updateElement(`#${this.id}-pkts-in`, this.formatNumber(data.packets_in));
      }
      if (data.packets_out !== undefined) {
        this.updateElement(`#${this.id}-pkts-out`, this.formatNumber(data.packets_out));
      }

      this.hideLoading();
    } catch (error) {
      console.error('Firewall widget error:', error);
    }
  }

  formatNumber(num) {
    if (num >= 1000000000) return (num / 1000000000).toFixed(1) + 'B';
    if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
    if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
    return num.toString();
  }
}

window.FirewallWidget = FirewallWidget;
