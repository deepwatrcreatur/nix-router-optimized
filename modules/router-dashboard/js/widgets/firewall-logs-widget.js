/**
 * Firewall Logs Widget
 * Streams firewall log events over SSE
 */
class FirewallLogsWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = config.title || 'Firewall Log';
    this.widgetClass = 'widget-lg';
    this.refreshInterval = 0;
    this.eventSource = null;
    this.logs = [];
    this.maxEntries = config.maxEntries || 100;
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
        <span class="status-badge status-warning" id="${this.id}-status">Connecting</span>
      </div>
      <div class="widget-body no-padding">
        <div class="firewall-log-toolbar">
          <button class="firewall-log-btn" id="${this.id}-reconnect">Reconnect</button>
          <div class="firewall-log-meta" id="${this.id}-meta">Waiting for events</div>
        </div>
        <div class="firewall-log-list" id="${this.id}-list">
          <div class="history-empty">No firewall log events yet</div>
        </div>
      </div>
    `;
  }

  onMounted() {
    const reconnect = this.container?.querySelector(`#${this.id}-reconnect`);
    if (reconnect) {
      reconnect.addEventListener('click', () => this.connect());
    }
  }

  async onTick() {
    if (!this.eventSource) {
      this.connect();
    }
  }

  connect() {
    this.disconnect();
    this.setStatus('Connecting', 'warning');
    this.setMeta('Opening live stream');

    this.eventSource = new EventSource('/api/firewall/logs/stream?limit=25');

    this.eventSource.addEventListener('ready', () => {
      this.setStatus('Live', 'up');
      this.setMeta(`Streaming ${this.logs.length} entries`);
    });

    this.eventSource.addEventListener('log', event => {
      const entry = JSON.parse(event.data);
      this.addLog(entry);
      this.setStatus('Live', 'up');
      this.setMeta(`Updated ${new Date().toLocaleTimeString()}`);
    });

    this.eventSource.addEventListener('heartbeat', () => {
      this.setStatus('Live', 'up');
    });

    this.eventSource.addEventListener('error', event => {
      let message = 'Stream disconnected';
      if (event?.data) {
        try {
          const payload = JSON.parse(event.data);
          message = payload.message || message;
        } catch {}
      }
      this.setStatus('Error', 'down');
      this.setMeta(message);
    });

    this.eventSource.onerror = () => {
      this.setStatus('Retrying', 'warning');
      this.setMeta('Waiting for stream to reconnect');
    };
  }

  disconnect() {
    if (this.eventSource) {
      this.eventSource.close();
      this.eventSource = null;
    }
  }

  addLog(entry) {
    this.logs.push(entry);
    this.logs = this.logs.slice(-this.maxEntries);
    this.renderLogs();
  }

  renderLogs() {
    const list = this.container?.querySelector(`#${this.id}-list`);
    if (!list) return;

    if (this.logs.length === 0) {
      list.innerHTML = '<div class="history-empty">No firewall log events yet</div>';
      return;
    }

    list.innerHTML = this.logs.slice().reverse().map(entry => `
      <div class="firewall-log-entry">
        <div class="firewall-log-line">
          <span class="firewall-log-time">${entry.timestamp || '--'}</span>
          <span class="firewall-log-prefix">${entry.prefix || 'FW-LOG'}</span>
          <span class="firewall-log-summary">${entry.summary || entry.raw}</span>
        </div>
        <div class="firewall-log-details">
          <span>${entry.interfaceIn || '--'} -> ${entry.interfaceOut || '--'}</span>
          <span>${entry.protocol || '--'}</span>
          <span>${entry.src || '--'}${entry.srcPort ? `:${entry.srcPort}` : ''}</span>
          <span>${entry.dst || '--'}${entry.dstPort ? `:${entry.dstPort}` : ''}</span>
        </div>
      </div>
    `).join('');
  }

  setStatus(label, variant) {
    const badge = this.container?.querySelector(`#${this.id}-status`);
    if (!badge) return;

    badge.textContent = label;
    badge.classList.remove('status-up', 'status-down', 'status-warning');
    badge.classList.add(`status-${variant}`);
  }

  setMeta(message) {
    const meta = this.container?.querySelector(`#${this.id}-meta`);
    if (meta) {
      meta.textContent = message;
    }
  }

  onDestroy() {
    this.disconnect();
    super.onDestroy();
  }
}

window.FirewallLogsWidget = FirewallLogsWidget;
