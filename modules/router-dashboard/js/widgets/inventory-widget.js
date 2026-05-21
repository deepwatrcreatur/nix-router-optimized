/**
 * Inventory Browser Widget
 * Displays read-only subnet and host inventory derived from declarative router state.
 */
class InventoryWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = config.title || 'Inventory';
    this.widgetClass = 'widget-full inventory-widget';
    this.refreshInterval = config.refreshInterval || 60000;
    this.inventory = null;
    this.query = '';
    this.selectedHostId = null;
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
        <span class="status-badge status-warning" id="${this.id}-summary">Loading</span>
      </div>
      <div class="widget-body inventory-body">
        <div class="inventory-toolbar">
          <div class="inventory-toolbar-copy">
            <div class="inventory-title">Read-only declarative inventory</div>
            <div class="inventory-subtitle">Browse subnets, reserved addresses, and declared host records without introducing mutable IPAM state.</div>
          </div>
          <label class="inventory-search-wrap" for="${this.id}-search">
            <span>Filter</span>
            <input id="${this.id}-search" class="inventory-search" type="search" placeholder="Search host, IP, subnet, label">
          </label>
        </div>
        <div class="inventory-summary-grid" id="${this.id}-summary-grid">
          <div class="metric metric-small">
            <div class="metric-label">Subnets</div>
            <div class="metric-value" id="${this.id}-subnets">--</div>
          </div>
          <div class="metric metric-small">
            <div class="metric-label">Hosts</div>
            <div class="metric-value" id="${this.id}-hosts">--</div>
          </div>
          <div class="metric metric-small">
            <div class="metric-label">Reserved</div>
            <div class="metric-value" id="${this.id}-reserved">--</div>
          </div>
          <div class="metric metric-small">
            <div class="metric-label">Authority</div>
            <div class="metric-value inventory-authority" id="${this.id}-authority">--</div>
          </div>
        </div>
        <div class="inventory-layout">
          <section class="inventory-subnets-panel">
            <div class="inventory-section-title">Subnets</div>
            <div class="inventory-subnets-list" id="${this.id}-subnets-list">
              <div class="dashboard-empty-state">
                <h2>Loading inventory</h2>
                <p>Reading the declarative inventory reduction for router-dashboard.</p>
              </div>
            </div>
          </section>
          <section class="inventory-detail-panel">
            <div class="inventory-section-title">Host Detail</div>
            <div class="inventory-detail-card" id="${this.id}-detail-card">
              <div class="dashboard-empty-state">
                <h2>No host selected</h2>
                <p>Choose a host or reserved address entry to inspect its declarative metadata.</p>
              </div>
            </div>
          </section>
        </div>
      </div>
    `;
  }

  onMounted() {
    const search = this.container?.querySelector(`#${this.id}-search`);
    if (search) {
      search.addEventListener('input', event => {
        this.query = event.target.value.trim().toLowerCase();
        this.renderInventory();
      });
    }

    const subnetList = this.container?.querySelector(`#${this.id}-subnets-list`);
    if (subnetList) {
      subnetList.addEventListener('click', event => {
        const button = event.target.closest('[data-inventory-host-id]');
        if (!button) return;
        this.selectedHostId = button.dataset.inventoryHostId;
        this.renderInventory();
      });
    }
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/inventory');
      this.inventory = data;
      if (!this.selectedHostId && (data.hosts || []).length > 0) {
        this.selectedHostId = data.hosts[0].id;
      }
      this.renderInventory();
      this.hideLoading();
    } catch (error) {
      console.error('Inventory widget error:', error);
      this.hideLoading();
      this.renderErrorState('Unable to load inventory data');
    }
  }

  renderInventory() {
    if (!this.inventory) return;

    const filteredGroups = this.buildSubnetGroups();
    const visibleHosts = filteredGroups.flatMap(group => group.hosts);
    const selectedHost = visibleHosts.find(host => host.id === this.selectedHostId) || visibleHosts[0] || null;
    if (selectedHost) {
      this.selectedHostId = selectedHost.id;
    }

    this.updateElement(`#${this.id}-subnets`, String((this.inventory.subnets || []).length));
    this.updateElement(`#${this.id}-hosts`, String((this.inventory.hosts || []).length));
    this.updateElement(`#${this.id}-reserved`, String((this.inventory.reservedAddresses || []).length));
    this.updateElement(`#${this.id}-authority`, this.inventory.authoritySurface || 'declarative');

    const summaryEl = this.container?.querySelector(`#${this.id}-summary`);
    if (summaryEl) {
      summaryEl.textContent = `${filteredGroups.length} subnet groups`;
      summaryEl.className = 'status-badge status-up';
    }

    const list = this.container?.querySelector(`#${this.id}-subnets-list`);
    if (list) {
      if (filteredGroups.length === 0) {
        list.innerHTML = `
          <div class="dashboard-empty-state">
            <h2>No inventory matches</h2>
            <p>Try a different subnet, host, or IP search.</p>
          </div>
        `;
      } else {
        list.innerHTML = filteredGroups.map(group => this.renderSubnetGroup(group, selectedHost)).join('');
      }
    }

    const detail = this.container?.querySelector(`#${this.id}-detail-card`);
    if (detail) {
      detail.innerHTML = selectedHost
        ? this.renderHostDetail(selectedHost)
        : `
          <div class="dashboard-empty-state">
            <h2>No host selected</h2>
            <p>The current filter returned only subnet metadata.</p>
          </div>
        `;
    }
  }

  buildSubnetGroups() {
    const subnets = this.inventory?.subnets || [];
    const hosts = this.inventory?.hosts || [];
    const query = this.query;

    const hostMap = new Map();
    hosts.forEach(host => {
      const subnetRef = host.subnetRef || 'unassigned';
      if (!hostMap.has(subnetRef)) hostMap.set(subnetRef, []);
      hostMap.get(subnetRef).push(host);
    });

    const groups = subnets.map(subnet => {
      const subnetHosts = (hostMap.get(subnet.id) || []).sort((a, b) =>
        (a.ipv4Address || '').localeCompare(b.ipv4Address || '')
      );
      return {
        subnet,
        hosts: subnetHosts.filter(host => this.matchesQuery(host, subnet, query)),
        subnetMatches: this.matchesQuery(subnet, subnet, query)
      };
    });

    const unassignedHosts = (hostMap.get('unassigned') || []).filter(host =>
      this.matchesQuery(host, null, query)
    );

    if (unassignedHosts.length > 0) {
      groups.push({
        subnet: {
          id: 'unassigned',
          label: 'Unassigned',
          cidr: 'No matching subnet',
          gatewayAddress: null,
          dhcpBackend: null,
          dynamicPools: [ ]
        },
        hosts: unassignedHosts.sort((a, b) =>
          (a.ipv4Address || '').localeCompare(b.ipv4Address || '')
        ),
        subnetMatches: !query || 'unassigned no matching subnet'.includes(query)
      });
    }

    return groups.filter(group => group.subnetMatches || group.hosts.length > 0);
  }

  matchesQuery(item, subnet, query) {
    if (!query) return true;
    const haystack = [
      item.id,
      item.label,
      item.hostname,
      item.ipv4Address,
      item.address,
      item.cidr,
      item.gatewayAddress,
      item.sourceKind,
      subnet?.label,
      subnet?.cidr
    ].filter(Boolean).join(' ').toLowerCase();
    return haystack.includes(query);
  }

  renderSubnetGroup(group, selectedHost) {
    const subnet = group.subnet;
    const hosts = group.hosts;
    const poolText = (subnet.dynamicPools || []).map(pool => `${pool.start} → ${pool.end}`).join(', ') || 'No dynamic pool';

    return `
      <article class="inventory-subnet-card">
        <div class="inventory-subnet-header">
          <div>
            <div class="inventory-subnet-name">${this.escape(subnet.label || subnet.id)}</div>
            <div class="inventory-subnet-cidr">${this.escape(subnet.cidr || '--')}</div>
          </div>
          <div class="inventory-subnet-tags">
            <span class="inventory-tag">${this.escape(subnet.dhcpBackend || 'no-dhcp')}</span>
            <span class="inventory-tag">${hosts.length} hosts</span>
          </div>
        </div>
        <div class="inventory-subnet-meta">
          <div><span>Gateway</span><strong>${this.escape(subnet.gatewayAddress || '--')}</strong></div>
          <div><span>Pool</span><strong>${this.escape(poolText)}</strong></div>
        </div>
        ${hosts.length > 0 ? `
          <div class="inventory-host-list">
            ${hosts.map(host => this.renderHostRow(host, selectedHost)).join('')}
          </div>
        ` : `
          <div class="inventory-subnet-empty">No matching hosts or reservations in this subnet.</div>
        `}
      </article>
    `;
  }

  renderHostRow(host, selectedHost) {
    const selected = selectedHost && selectedHost.id === host.id;
    return `
      <button class="inventory-host-row${selected ? ' is-selected' : ''}" type="button" data-inventory-host-id="${this.escape(host.id)}">
        <div>
          <div class="inventory-host-name">${this.escape(host.label || host.hostname || host.ipv4Address || host.id)}</div>
          <div class="inventory-host-meta">${this.escape(host.sourceKind || 'declared')}</div>
        </div>
        <div class="inventory-host-ip">${this.escape(host.ipv4Address || '--')}</div>
      </button>
    `;
  }

  renderHostDetail(host) {
    const provenance = (host.provenance || []).map(entry => `
      <li><strong>${this.escape(entry.module || '--')}</strong><span>${this.escape(entry.path || '--')}</span></li>
    `).join('');

    return `
      <div class="inventory-detail-heading">
        <div>
          <div class="inventory-detail-title">${this.escape(host.label || host.hostname || host.id)}</div>
          <div class="inventory-detail-subtitle">${this.escape(host.sourceKind || 'declared inventory')}</div>
        </div>
        <span class="inventory-tag">${this.escape(host.ipv4Address || '--')}</span>
      </div>
      <div class="inventory-detail-grid">
        <div><span>Hostname</span><strong>${this.escape(host.hostname || '--')}</strong></div>
        <div><span>MAC</span><strong>${this.escape(host.macAddress || '--')}</strong></div>
        <div><span>Subnet</span><strong>${this.escape(host.subnetRef || '--')}</strong></div>
        <div><span>Record</span><strong>${this.escape(host.id || '--')}</strong></div>
      </div>
      <div class="inventory-detail-provenance">
        <div class="inventory-section-title">Provenance</div>
        <ul>${provenance || '<li><strong>none</strong><span>No provenance recorded.</span></li>'}</ul>
      </div>
    `;
  }

  renderErrorState(message) {
    const summaryEl = this.container?.querySelector(`#${this.id}-summary`);
    if (summaryEl) {
      summaryEl.textContent = 'Error';
      summaryEl.className = 'status-badge status-down';
    }

    const list = this.container?.querySelector(`#${this.id}-subnets-list`);
    if (list) {
      list.innerHTML = `<div class="error-message">${this.escape(message)}</div>`;
    }
  }

  escape(value) {
    return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }
}

window.InventoryWidget = InventoryWidget;
