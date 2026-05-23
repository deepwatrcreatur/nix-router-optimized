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
            <div class="metric-label">Counter Rules</div>
            <div class="metric-value" id="${this.id}-counter-rules">--</div>
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
        <div class="widget-section">
          <div class="section-title">Flowtables</div>
          <div class="metric-note" id="${this.id}-flowtable-summary">No flowtable configured</div>
          <div id="${this.id}-flowtable-detail"></div>
        </div>
        <div class="widget-section">
          <div class="section-title">Hot Chains</div>
          <div class="table-wrap">
            <table class="data-table data-table-compact">
              <thead>
                <tr>
                  <th>Chain</th>
                  <th>Packets</th>
                  <th>Rules</th>
                </tr>
              </thead>
              <tbody id="${this.id}-chains"></tbody>
            </table>
          </div>
        </div>
        <div class="widget-section">
          <div class="section-title">Hot Rules</div>
          <div class="table-wrap">
            <table class="data-table data-table-compact">
              <thead>
                <tr>
                  <th>Rule</th>
                  <th>Packets</th>
                  <th>Bytes</th>
                </tr>
              </thead>
              <tbody id="${this.id}-rules-detail"></tbody>
            </table>
          </div>
        </div>
        <div class="widget-section">
          <div class="section-title">Recent Activity</div>
          <div class="metric-note" id="${this.id}-activity-meta">Analyzing recent firewall log activity</div>
          <div class="firewall-activity-grid">
            <div>
              <div class="metric-label">Prefixes</div>
              <div class="firewall-activity-list" id="${this.id}-prefixes"></div>
            </div>
            <div>
              <div class="metric-label">Top Sources</div>
              <div class="firewall-activity-list" id="${this.id}-sources"></div>
            </div>
            <div>
              <div class="metric-label">Top Ports</div>
              <div class="firewall-activity-list" id="${this.id}-ports"></div>
            </div>
          </div>
          <div class="metric-label" style="margin-top: 10px;">Fail2ban Overlap</div>
          <div class="firewall-activity-list" id="${this.id}-banned"></div>
        </div>
      </div>
    `;
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/firewall/stats');

      this.updateElement(`#${this.id}-rules`, data.rules_count?.toString() || '--');
      this.updateElement(`#${this.id}-counter-rules`, data.counter_rules?.toString() || '--');

      const flowtableEl = this.container?.querySelector(`#${this.id}-flowtable`);
      if (flowtableEl) {
        if (data.flowtable_active) {
          flowtableEl.textContent = 'ON';
          flowtableEl.style.color = this.getThemeColor('--accent-green', '#10b981');
        } else {
          flowtableEl.textContent = 'OFF';
          flowtableEl.style.color = this.getThemeColor('--accent-yellow', '#f59e0b');
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

      this.renderFlowtableDetail(data.flowtables || [], data.offloaded_flows);
      this.renderChainRows(data.chains || []);
      this.renderRuleRows(data.top_rules || []);
      await this.loadActivitySummary();

      this.hideLoading();
    } catch (error) {
      console.error('Firewall widget error:', error);
    }
  }

  async loadActivitySummary() {
    try {
      const data = await this.fetchAPI('/firewall/activity-summary?limit=120');
      this.renderActivitySummary(data);
    } catch (error) {
      console.error('Firewall activity summary error:', error);
      this.renderActivityError();
    }
  }

  renderFlowtableDetail(flowtables, offloadedFlows) {
    const summaryEl = this.container?.querySelector(`#${this.id}-flowtable-summary`);
    const detailEl = this.container?.querySelector(`#${this.id}-flowtable-detail`);
    if (!summaryEl || !detailEl) return;

    if (!flowtables.length) {
      summaryEl.textContent = 'No flowtable configured';
      detailEl.innerHTML = '';
      return;
    }

    const offloadLabel = offloadedFlows === -1
      ? 'offload count too large to sample cheaply'
      : `${this.formatNumber(offloadedFlows || 0)} offloaded flows`;

    summaryEl.textContent = `${flowtables.length} flowtable${flowtables.length === 1 ? '' : 's'}, ${offloadLabel}`;
    detailEl.innerHTML = flowtables.map(flowtable => `
      <div class="firewall-flowtable-card">
        <div class="firewall-flowtable-name">${this.escapeHtml(flowtable.table || 'table')}/${this.escapeHtml(flowtable.name || 'flowtable')}</div>
        <div class="firewall-flowtable-meta">
          <span>${this.escapeHtml(flowtable.family || 'inet')}</span>
          <span>${this.escapeHtml(flowtable.hook || 'forward')}</span>
          <span>prio ${this.escapeHtml(String(flowtable.priority ?? '--'))}</span>
        </div>
        <div class="firewall-flowtable-meta">
          <span>dev ${this.escapeHtml((flowtable.devices || []).join(', ') || '--')}</span>
          <span>flags ${this.escapeHtml((flowtable.flags || []).join(', ') || 'none')}</span>
        </div>
      </div>
    `).join('');
  }

  renderChainRows(chains) {
    const tbody = this.container?.querySelector(`#${this.id}-chains`);
    if (!tbody) return;

    const rows = chains.slice(0, 6);
    if (!rows.length) {
      tbody.innerHTML = '<tr><td colspan="3">No chain counter detail</td></tr>';
      return;
    }

    tbody.innerHTML = rows.map(chain => `
      <tr>
        <td><code>${this.escapeHtml(chain.table || 'table')}/${this.escapeHtml(chain.name || 'chain')}</code></td>
        <td>${this.escapeHtml(this.formatNumber(chain.packets || 0))}</td>
        <td>${this.escapeHtml(String(chain.rules || 0))}</td>
      </tr>
    `).join('');
  }

  renderRuleRows(rules) {
    const tbody = this.container?.querySelector(`#${this.id}-rules-detail`);
    if (!tbody) return;

    if (!rules.length) {
      tbody.innerHTML = '<tr><td colspan="3">No counter-bearing rules detected</td></tr>';
      return;
    }

    tbody.innerHTML = rules.slice(0, 6).map(rule => `
      <tr>
        <td>
          <div class="firewall-rule-summary">${this.escapeHtml(rule.summary || `handle ${rule.handle || '?'}`)}</div>
          <div class="firewall-rule-meta">${this.escapeHtml(rule.table || 'table')}/${this.escapeHtml(rule.chain || 'chain')} · handle ${this.escapeHtml(String(rule.handle ?? '?'))}</div>
        </td>
        <td>${this.escapeHtml(this.formatNumber(rule.packets || 0))}</td>
        <td>${this.escapeHtml(this.formatBytes(rule.bytes || 0))}</td>
      </tr>
    `).join('');
  }

  renderActivitySummary(data) {
    const meta = this.container?.querySelector(`#${this.id}-activity-meta`);
    if (meta) {
      const recent = data.mostRecentEvent?.summary || 'no recent event';
      const bans = data.fail2banAvailable
        ? `${data.currentlyBanned || 0} currently banned`
        : 'fail2ban unavailable';
      meta.textContent = `${data.eventsAnalyzed || 0} recent events analyzed, ${bans}, latest: ${recent}`;
    }

    this.renderActivityList(`#${this.id}-prefixes`, data.prefixCounts || [], item =>
      `<code>${this.escapeHtml(item.prefix || 'FW-LOG')}</code><span>${this.escapeHtml(String(item.count || 0))}</span>`
    );
    this.renderActivityList(`#${this.id}-sources`, data.topSources || [], item =>
      `<code>${this.escapeHtml(item.ip || '--')}</code><span>${this.escapeHtml(String(item.count || 0))}</span>`
    );
    this.renderActivityList(`#${this.id}-ports`, data.topDestinationPorts || [], item =>
      `<code>${this.escapeHtml(item.port || '--')}</code><span>${this.escapeHtml(String(item.count || 0))}</span>`
    );
    this.renderActivityList(`#${this.id}-banned`, data.bannedSourceHits || [], item =>
      `<div><code>${this.escapeHtml(item.ip || '--')}</code> <span class="firewall-activity-inline">${this.escapeHtml(item.prefix || 'FW-LOG')}</span></div><div class="firewall-activity-inline">${this.escapeHtml(item.summary || '')}</div>`,
      'No recent firewall events match currently banned fail2ban IPs'
    );
  }

  renderActivityError() {
    const meta = this.container?.querySelector(`#${this.id}-activity-meta`);
    if (meta) {
      meta.textContent = 'Unable to summarize recent firewall activity';
    }
    this.renderActivityList(`#${this.id}-prefixes`, [], () => '', 'Activity summary unavailable');
    this.renderActivityList(`#${this.id}-sources`, [], () => '', 'Activity summary unavailable');
    this.renderActivityList(`#${this.id}-ports`, [], () => '', 'Activity summary unavailable');
    this.renderActivityList(`#${this.id}-banned`, [], () => '', 'Activity summary unavailable');
  }

  renderActivityList(selector, items, renderItem, emptyText = 'No recent activity') {
    const container = this.container?.querySelector(selector);
    if (!container) return;

    if (!items.length) {
      container.innerHTML = `<div class="history-empty">${this.escapeHtml(emptyText)}</div>`;
      return;
    }

    container.innerHTML = items.map(item => `
      <div class="firewall-activity-item">
        ${renderItem(item)}
      </div>
    `).join('');
  }

  formatNumber(num) {
    if (num >= 1000000000) return (num / 1000000000).toFixed(1) + 'B';
    if (num >= 1000000) return (num / 1000000).toFixed(1) + 'M';
    if (num >= 1000) return (num / 1000).toFixed(1) + 'K';
    return num.toString();
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }
}

window.FirewallWidget = FirewallWidget;
