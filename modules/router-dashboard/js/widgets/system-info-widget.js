/**
 * System Info Widget
 * Compact host identity summary for the current router system.
 */
class SystemInfoWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = config.title || 'System Info';
    this.widgetClass = 'widget-md system-info-widget';
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
      </div>
      <div class="widget-body">
        <div class="system-info-summary">
          <div class="system-info-host" id="${this.id}-host">--</div>
          <div class="system-info-os" id="${this.id}-os">--</div>
        </div>
        <div class="system-info-grid">
          <div class="system-info-item">
            <div class="system-info-label">Platform</div>
            <div class="system-info-value" id="${this.id}-platform">--</div>
          </div>
          <div class="system-info-item">
            <div class="system-info-label">Uptime</div>
            <div class="system-info-value" id="${this.id}-uptime">--</div>
          </div>
          <div class="system-info-item">
            <div class="system-info-label">CPU</div>
            <div class="system-info-value" id="${this.id}-cpu">--</div>
          </div>
          <div class="system-info-item">
            <div class="system-info-label">Memory</div>
            <div class="system-info-value" id="${this.id}-memory">--</div>
          </div>
          <div class="system-info-item">
            <div class="system-info-label">Swap</div>
            <div class="system-info-value" id="${this.id}-swap">--</div>
          </div>
          <div class="system-info-item">
            <div class="system-info-label">Root FS</div>
            <div class="system-info-value" id="${this.id}-root">--</div>
          </div>
          <div class="system-info-item">
            <div class="system-info-label">Default Route</div>
            <div class="system-info-value" id="${this.id}-route">--</div>
          </div>
          <div class="system-info-item">
            <div class="system-info-label">IPv6</div>
            <div class="system-info-value" id="${this.id}-ipv6">--</div>
          </div>
          <div class="system-info-item system-info-item-wide">
            <div class="system-info-label">Generation</div>
            <div class="system-info-value system-info-mono" id="${this.id}-generation">--</div>
          </div>
        </div>
      </div>
    `;
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/system/info');

      const cpuSummary = [data.cpuModel, data.cpuCores ? `${data.cpuCores} cores` : '']
        .filter(Boolean)
        .join(' • ');
      const platformSummary = [data.kernel, data.virtualization].filter(Boolean).join(' • ');
      const routeSummary = [data.defaultInterface, data.defaultIpv4].filter(Boolean).join(' • ');
      const ipv6Summary = (data.defaultIpv6 || []).slice(0, 2).join(', ') || '--';

      this.updateElement(`#${this.id}-host`, data.hostname || '--');
      this.updateElement(`#${this.id}-os`, data.nixosVersion || data.os || '--');
      this.updateElement(`#${this.id}-platform`, platformSummary || '--');
      this.updateElement(`#${this.id}-uptime`, data.uptime || '--');
      this.updateElement(`#${this.id}-cpu`, cpuSummary || '--');
      this.updateElement(`#${this.id}-memory`, data.memoryTotalHuman || '--');
      this.updateElement(`#${this.id}-swap`, data.swapTotalHuman || '--');
      this.updateElement(`#${this.id}-root`, data.rootTotalHuman || '--');
      this.updateElement(`#${this.id}-route`, routeSummary || '--');
      this.updateElement(`#${this.id}-ipv6`, ipv6Summary);
      this.updateElement(`#${this.id}-generation`, data.systemGeneration || '--');

      this.hideLoading();
    } catch (error) {
      console.error('System info widget error:', error);
    }
  }
}

window.SystemInfoWidget = SystemInfoWidget;
