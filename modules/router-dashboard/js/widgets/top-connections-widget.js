/**
 * Top Connections Widget
 * Shows the most active network connections
 */
class TopConnectionsWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = config.title || 'Active Connections';
    this.widgetClass = 'widget-lg';
    this.refreshInterval = config.refreshInterval || 10000;
    this.limit = config.limit || 10;
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
        <div class="widget-controls">
          <select id="${this.id}-filter" class="widget-select">
            <option value="all">All</option>
            <option value="tcp">TCP</option>
            <option value="udp">UDP</option>
          </select>
        </div>
      </div>
      <div class="widget-body no-padding">
        <div class="connections-table-wrapper">
          <table class="connections-table" id="${this.id}-table">
            <thead>
              <tr>
                <th>Protocol</th>
                <th>Source</th>
                <th>Destination</th>
                <th>State</th>
                <th>Age</th>
              </tr>
            </thead>
            <tbody id="${this.id}-tbody">
              <tr><td colspan="5" class="loading">Loading...</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    `;
  }

  onMounted() {
    const filterEl = this.container?.querySelector(`#${this.id}-filter`);
    if (filterEl) {
      filterEl.addEventListener('change', () => this.onTick());
    }
  }

  async onTick() {
    try {
      const filterEl = this.container?.querySelector(`#${this.id}-filter`);
      const filter = filterEl?.value || 'all';

      const data = await this.fetchAPI(`/connections/top?limit=${this.limit}&filter=${filter}`);

      const tbody = this.container?.querySelector(`#${this.id}-tbody`);
      if (tbody && data.connections) {
        if (data.connections.length === 0) {
          tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--text-muted);">No connections</td></tr>';
        } else {
          tbody.innerHTML = data.connections.map(c => this.renderConnection(c)).join('');
        }
      }

      this.hideLoading();
    } catch (error) {
      console.error('Top connections widget error:', error);
    }
  }

  renderConnection(conn) {
    const protoClass = conn.protocol === 'tcp' ? 'proto-tcp' :
                       conn.protocol === 'udp' ? 'proto-udp' : 'proto-other';

    const stateClass = conn.state === 'ESTABLISHED' ? 'state-established' :
                       conn.state === 'TIME_WAIT' ? 'state-timewait' : '';

    return `
      <tr>
        <td><span class="proto-badge ${protoClass}">${conn.protocol.toUpperCase()}</span></td>
        <td class="conn-endpoint">
          <span class="conn-ip">${conn.src_ip}</span>
          <span class="conn-port">:${conn.src_port}</span>
        </td>
        <td class="conn-endpoint">
          <span class="conn-ip">${conn.dst_ip}</span>
          <span class="conn-port">:${conn.dst_port}</span>
        </td>
        <td><span class="conn-state ${stateClass}">${conn.state || '-'}</span></td>
        <td class="conn-age">${this.formatAge(conn.timeout)}</td>
      </tr>
    `;
  }

  formatAge(seconds) {
    if (seconds === undefined || seconds === null) return '-';
    if (seconds < 60) return `${seconds}s`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
    return `${Math.floor(seconds / 3600)}h`;
  }
}

window.TopConnectionsWidget = TopConnectionsWidget;
