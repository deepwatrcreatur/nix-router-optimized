/**
 * Wake-on-LAN Widget
 * Sends magic packets to configured devices
 */
class WolWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = config.title || 'Wake-on-LAN';
    this.widgetClass = 'widget-md';
    this.refreshInterval = 0;
    this.devices = config.devices || [];
  }

  getMarkup() {
    const devicesHtml = this.devices.map((device, index) => `
      <div class="wol-device">
        <div class="wol-device-info">
          <div class="wol-device-name">${device.name}</div>
          <div class="wol-device-meta">${device.macAddress}</div>
        </div>
        <button class="wol-btn" data-device-index="${index}">
          Wake
        </button>
      </div>
    `).join('');

    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
        <span class="status-badge status-up">${this.devices.length} Devices</span>
      </div>
      <div class="widget-body">
        <div class="wol-list">
          ${devicesHtml || '<div class="history-empty">No devices configured</div>'}
        </div>
        <div class="wol-status" id="${this.id}-status">Ready</div>
      </div>
    `;
  }

  onMounted() {
    this.container?.querySelectorAll('.wol-btn').forEach(button => {
      button.addEventListener('click', () => {
        const index = Number.parseInt(button.dataset.deviceIndex || '-1', 10);
        if (index >= 0 && this.devices[index]) {
          this.wakeDevice(this.devices[index], button);
        }
      });
    });
  }

  async wakeDevice(device, button) {
    button.disabled = true;
    button.textContent = 'Waking...';
    this.setStatus(`Sending magic packet to ${device.name}...`);

    try {
      const response = await fetch('/api/wol/wake', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(device)
      });
      const data = await response.json();

      if (!response.ok || data.error) {
        throw new Error(data.error || `Wake request failed (${response.status})`);
      }

      this.setStatus(`Magic packet sent to ${device.name}`, false);
    } catch (error) {
      this.setStatus(error.message || 'Wake request failed', true);
    } finally {
      button.disabled = false;
      button.textContent = 'Wake';
    }
  }

  setStatus(message, isError = false) {
    const statusEl = this.container?.querySelector(`#${this.id}-status`);
    if (!statusEl) return;

    statusEl.textContent = message;
    statusEl.classList.toggle('error', isError);
  }

  async onTick() {
    // Static widget
  }
}

window.WolWidget = WolWidget;
