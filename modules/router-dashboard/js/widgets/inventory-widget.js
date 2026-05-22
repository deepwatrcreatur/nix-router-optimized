class InventoryWidget extends BaseWidget {
  constructor(config = {}) {
    super({
      title: 'Inventory Browser',
      refreshInterval: 60000,
      ...config
    });
    this.widgetClass = 'widget-full inventory-widget';
    this.inventory = null;
    this.filter = '';
    this.statusFilter = null;
    this.selectedHostId = null;
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>Inventory Browser</h2>
        <span class="inventory-badge">Read-only</span>
      </div>
      <div class="widget-body inventory-body">
        <div class="inventory-toolbar">
          <div class="inventory-toolbar-copy">
            <p>Browse declared subnets, reserved addresses, and host labels exported from router configuration.</p>
          </div>
          <label class="inventory-filter">
            <span class="sr-only">Filter inventory</span>
            <input type="search" id="${this.id}-filter" placeholder="Search host, IP, subnet, or label">
          </label>
        </div>
        <div class="inventory-status-filters" id="${this.id}-status-filters"></div>
        <div class="inventory-status" id="${this.id}-status">Loading inventory…</div>
        <div class="inventory-layout">
          <div class="inventory-subnets" id="${this.id}-subnets"></div>
          <div class="inventory-detail" id="${this.id}-detail">
            <div class="inventory-empty-detail">Select a host or subnet to inspect details.</div>
          </div>
        </div>
      </div>
    `;
  }

  onMounted() {
    const filterInput = this.container?.querySelector(`#${this.id}-filter`);
    if (filterInput) {
      filterInput.addEventListener('input', event => {
        this.filter = event.target.value.trim().toLowerCase();
        this.renderInventory();
      });
    }

    this.container?.addEventListener('click', event => {
      const statusBtn = event.target.closest('[data-inventory-status-filter]');
      if (statusBtn) {
        const value = statusBtn.dataset.inventoryStatusFilter;
        this.statusFilter = this.statusFilter === value ? null : value;
        this.renderStatusFilters();
        this.renderInventory();
        return;
      }

      const hostButton = event.target.closest('[data-inventory-host-id]');
      if (hostButton) {
        this.selectedHostId = hostButton.dataset.inventoryHostId;
        this.renderInventory();
        return;
      }

      const subnetButton = event.target.closest('[data-inventory-subnet-id]');
      if (subnetButton) {
        this.selectedHostId = null;
        this.renderSubnetDetail(subnetButton.dataset.inventorySubnetId);
        return;
      }

      const drillBtn = event.target.closest('[data-inventory-drill-subnet]');
      if (drillBtn) {
        const subnetId = drillBtn.dataset.inventoryDrillSubnet;
        const status = drillBtn.dataset.inventoryDrillStatus || null;
        this.statusFilter = status;
        this.filter = '';
        const filterInput = this.container?.querySelector(`#${this.id}-filter`);
        if (filterInput) filterInput.value = '';
        this.renderStatusFilters();
        this.renderInventory();
        // scroll subnet into view
        const card = this.container?.querySelector(`[data-inventory-subnet-id="${subnetId}"]`);
        if (card) card.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      }
    });
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/inventory');
      this.inventory = data;

      if (!this.selectedHostId && (data.hosts || []).length > 0) {
        this.selectedHostId = data.hosts[0].id;
      }

      this.renderStatusFilters();
      this.renderInventory();
      this.hideLoading();
    } catch (error) {
      this.hideLoading();
      this.showError(`Unable to load inventory: ${error.message}`);
    }
  }

  renderStatusFilters() {
    const el = this.container?.querySelector(`#${this.id}-status-filters`);
    if (!el || !this.inventory) return;

    const summary = this.inventory.runtimeSummary || {};
    const states = summary.reconciliationStates || [];
    const hosts = this.inventory.hosts || [];

    const counts = {};
    for (const host of hosts) {
      const s = host.status || 'declared';
      counts[s] = (counts[s] || 0) + 1;
    }

    el.innerHTML = states.map(state => {
      const count = counts[state] || 0;
      const active = this.statusFilter === state ? ' is-active' : '';
      return `<button type="button" class="inventory-status-filter-btn inventory-sf-${this.escape(state)}${active}" data-inventory-status-filter="${this.escape(state)}">${this.escape(state)} <span class="inventory-sf-count">${count}</span></button>`;
    }).join('');
  }

  renderInventory() {
    const statusEl = this.container?.querySelector(`#${this.id}-status`);
    const subnetsEl = this.container?.querySelector(`#${this.id}-subnets`);
    if (!statusEl || !subnetsEl) return;

    if (!this.inventory || this.inventory.available === false) {
      statusEl.textContent = this.inventory?.message || 'Inventory unavailable';
      subnetsEl.innerHTML = '';
      this.renderEmptyDetail(this.inventory?.message || 'Inventory unavailable');
      return;
    }

    const subnets = this.inventory.subnets || [];
    const hosts = this.inventory.hosts || [];
    const reservations = this.inventory.reservedAddresses || [];
    const runtimeSummary = this.inventory.runtimeSummary || {};

    const parts = [
      `${subnets.length} subnets`,
      `${hosts.length} hosts`,
      `${reservations.length} reserved`,
      `${runtimeSummary.liveLeaseCount || 0} live leases`,
    ];
    if (runtimeSummary.neighborOnlyCount > 0) {
      parts.push(`${runtimeSummary.neighborOnlyCount} neighbors`);
    }
    statusEl.textContent = parts.join(' \u00b7 ');

    const visibleGroups = subnets
      .map(subnet => ({
        subnet,
        hosts: this.filterHostsForSubnet(subnet.id)
      }))
      .filter(group => this.groupMatches(group));

    const unassignedHosts = this.filterUnassignedHosts();
    if (unassignedHosts.length > 0) {
      visibleGroups.push({
        subnet: {
          id: "unassigned",
          label: "Unassigned",
          cidr: "No matching subnet",
          gatewayAddress: null,
          dhcpBackend: null,
          dynamicPools: [ ],
          runtimeSummary: { }
        },
        hosts: unassignedHosts
      });
    }

    if (visibleGroups.length === 0) {
      subnetsEl.innerHTML = '<div class="inventory-empty-list">No inventory entries match the current filter.</div>';
      this.renderEmptyDetail('No matching hosts or subnets.');
      return;
    }

    subnetsEl.innerHTML = visibleGroups.map(group => this.renderSubnetGroup(group)).join('');

    if (this.selectedHostId) {
      const allVisible = visibleGroups.flatMap(g => g.hosts);
      if (allVisible.some(h => h.id === this.selectedHostId)) {
        this.renderHostDetail(this.selectedHostId);
      } else if (allVisible.length > 0) {
        this.selectedHostId = allVisible[0].id;
        this.renderHostDetail(this.selectedHostId);
      } else {
        this.renderSubnetDetail(visibleGroups[0].subnet.id);
      }
    } else {
      this.renderSubnetDetail(visibleGroups[0].subnet.id);
    }
  }

  filterHostsForSubnet(subnetId) {
    let hosts = (this.inventory?.hosts || []).filter(host => host.subnetRef === subnetId);
    if (this.statusFilter) {
      hosts = hosts.filter(host => host.status === this.statusFilter);
    }
    return this.filter ? hosts.filter(host => this.hostMatches(host)) : hosts;
  }

  filterUnassignedHosts() {
    let hosts = (this.inventory?.hosts || []).filter(host => !host.subnetRef);
    if (this.statusFilter) {
      hosts = hosts.filter(host => host.status === this.statusFilter);
    }
    return this.filter ? hosts.filter(host => this.hostMatches(host)) : hosts;
  }

  groupMatches(group) {
    if (this.statusFilter && group.hosts.length === 0) return false;
    if (!this.filter) return true;

    const subnetText = [
      group.subnet.label,
      group.subnet.cidr,
      group.subnet.gatewayAddress,
      group.subnet.dhcpBackend || ''
    ].join(' ').toLowerCase();

    return subnetText.includes(this.filter) || group.hosts.some(host => this.hostMatches(host));
  }

  hostMatches(host) {
    const text = [
      host.label,
      host.hostname || '',
      host.ipv4Address,
      host.macAddress || '',
      host.sourceKind || '',
      host.status || ''
    ].join(' ').toLowerCase();
    return text.includes(this.filter);
  }

  renderSubnetGroup(group) {
    const { subnet, hosts } = group;
    const visibleHosts = this.filter ? hosts.filter(host => this.hostMatches(host)) : hosts;

    return `
      <section class="inventory-subnet-card">
        <button class="inventory-subnet-header" type="button" data-inventory-subnet-id="${this.escape(subnet.id)}">
          <div>
            <div class="inventory-subnet-name">${this.escape(subnet.label)}</div>
            <div class="inventory-subnet-meta">${this.escape(subnet.cidr)} \u00b7 gateway ${this.escape(subnet.gatewayAddress || '--')}</div>
          </div>
          <div class="inventory-subnet-summary">
            <span>${this.escape(subnet.dhcpBackend || 'no-dhcp')}</span>
            <span>${visibleHosts.length} hosts</span>
            ${this.renderSubnetSummary(subnet.runtimeSummary)}
          </div>
        </button>
        <div class="inventory-host-list">
          ${visibleHosts.length > 0
            ? visibleHosts.map(host => this.renderHostRow(host)).join('')
            : '<div class="inventory-empty-subnet">No hosts match the current filter.</div>'}
        </div>
      </section>
    `;
  }

  renderHostRow(host) {
    const selectedClass = host.id === this.selectedHostId ? ' is-selected' : '';
    const mac = host.macAddress ? ` \u00b7 ${host.macAddress}` : '';
    return `
      <button class="inventory-host-row${selectedClass}" type="button" data-inventory-host-id="${this.escape(host.id)}">
        <div class="inventory-host-main">
          <span class="inventory-host-label">${this.escape(host.label)} ${this.renderHostStatusChip(host.status)}</span>
          <span class="inventory-host-ip">${this.escape(host.ipv4Address)}${this.escape(mac)}</span>
        </div>
        <div class="inventory-host-meta">${this.escape(host.sourceKind || 'declared-host')}${this.renderNeighborChip(host.neighbor)}</div>
      </button>
    `;
  }

  renderHostDetail(hostId) {
    const host = (this.inventory?.hosts || []).find(entry => entry.id === hostId);
    if (!host) {
      this.renderEmptyDetail('Select a host or subnet to inspect details.');
      return;
    }

    const subnet = (this.inventory?.subnets || []).find(entry => entry.id === host.subnetRef);
    const detailEl = this.container?.querySelector(`#${this.id}-detail`);
    if (!detailEl) return;

    const lease = host.runtimeLease;
    const neighbor = host.neighbor;

    let leaseSection = '';
    if (lease) {
      leaseSection = `
        <div class="inventory-detail-section">
          <h3>Runtime Lease</h3>
          <dl class="inventory-detail-list">
            <div><dt>Lease Address</dt><dd>${this.escape(lease.address || '—')}</dd></div>
            <div><dt>Lease Hostname</dt><dd>${this.escape(lease.hostname || '—')}</dd></div>
            <div><dt>Hardware Address</dt><dd>${this.escape(lease.hardwareAddress || '—')}</dd></div>
            <div><dt>Expires</dt><dd>${this.escape(lease.leaseExpires || '—')}${this.formatLeaseAge(lease.leaseExpires)}</dd></div>
            <div><dt>Scope</dt><dd>${this.escape(lease.scope || '—')}</dd></div>
            <div><dt>Interface</dt><dd>${this.escape(lease.interface || '—')}</dd></div>
          </dl>
        </div>
      `;
    }

    let neighborSection = '';
    if (neighbor) {
      neighborSection = `
        <div class="inventory-detail-section">
          <h3>ARP/NDP Neighbor</h3>
          <dl class="inventory-detail-list">
            <div><dt>MAC</dt><dd>${this.escape(neighbor.macAddress || '—')}</dd></div>
            <div><dt>Device</dt><dd>${this.escape(neighbor.device || '—')}</dd></div>
            <div><dt>State</dt><dd>${this.renderNeighborState(neighbor.state)}</dd></div>
          </dl>
        </div>
      `;
    }

    detailEl.innerHTML = `
      <div class="inventory-detail-card">
        <div class="inventory-detail-header">
          <div>
            <div class="inventory-detail-title">${this.escape(host.label)}</div>
            <div class="inventory-detail-subtitle">${this.escape(host.sourceKind || 'declared-host')} \u00b7 ${this.renderHostStatusChip(host.status)}</div>
          </div>
          <span class="inventory-badge">Read-only</span>
        </div>
        <dl class="inventory-detail-list">
          <div><dt>IPv4</dt><dd>${this.escape(host.ipv4Address)}</dd></div>
          <div><dt>Hostname</dt><dd>${this.escape(host.hostname || '—')}</dd></div>
          <div><dt>MAC</dt><dd>${this.escape(host.macAddress || '—')}</dd></div>
          <div><dt>Subnet</dt><dd>${this.escape(subnet ? `${subnet.label} (${subnet.cidr})` : host.subnetRef || '—')}</dd></div>
        </dl>
        ${leaseSection}
        ${neighborSection}
        <div class="inventory-provenance">
          <h3>Provenance</h3>
          ${this.renderProvenance(host.provenance || [])}
        </div>
      </div>
    `;
  }

  renderSubnetDetail(subnetId) {
    const subnet = (this.inventory?.subnets || []).find(entry => entry.id === subnetId);
    if (!subnet) {
      this.renderEmptyDetail('Select a host or subnet to inspect details.');
      return;
    }

    const detailEl = this.container?.querySelector(`#${this.id}-detail`);
    if (!detailEl) return;

    const pools = subnet.dynamicPools || [];
    const summary = subnet.runtimeSummary || {};

    let drillButtons = '';
    const drillStates = [
      { key: 'conflictCount', status: 'conflict', label: 'conflicts' },
      { key: 'runtimeOnlyLeaseCount', status: 'runtime-only', label: 'runtime-only' },
      { key: 'neighborOnlyCount', status: 'neighbor-only', label: 'neighbors' },
      { key: 'staleCount', status: 'stale', label: 'stale' },
    ];
    const drillItems = drillStates
      .filter(d => (summary[d.key] || 0) > 0)
      .map(d => `<button type="button" class="inventory-drill-btn inventory-sf-${this.escape(d.status)}" data-inventory-drill-subnet="${this.escape(subnetId)}" data-inventory-drill-status="${this.escape(d.status)}">${summary[d.key]} ${this.escape(d.label)}</button>`);
    if (drillItems.length > 0) {
      drillButtons = `<div class="inventory-drill-bar">${drillItems.join('')}</div>`;
    }

    detailEl.innerHTML = `
      <div class="inventory-detail-card">
        <div class="inventory-detail-header">
          <div>
            <div class="inventory-detail-title">${this.escape(subnet.label)}</div>
            <div class="inventory-detail-subtitle">${this.escape(subnet.cidr)}</div>
          </div>
          <span class="inventory-badge">Read-only</span>
        </div>
        <dl class="inventory-detail-list">
          <div><dt>Gateway</dt><dd>${this.escape(subnet.gatewayAddress || '—')}</dd></div>
          <div><dt>DHCP Backend</dt><dd>${this.escape(subnet.dhcpBackend || 'none')}</dd></div>
          <div><dt>DNS</dt><dd>${this.escape((subnet.dnsServers || []).join(', ') || '—')}</dd></div>
          <div><dt>Search Domains</dt><dd>${this.escape((subnet.searchDomains || []).join(', ') || '—')}</dd></div>
          <div><dt>Dynamic Pools</dt><dd>${this.escape(pools.map(pool => `${pool.start} - ${pool.end}`).join(', ') || '—')}</dd></div>
          <div><dt>Live Leases</dt><dd>${this.escape(String(summary.liveLeaseCount ?? 0))}</dd></div>
          <div><dt>Occupancy</dt><dd>${this.escape(this.formatOccupancy(summary))}</dd></div>
          <div><dt>Declared Hosts</dt><dd>${this.escape(String(summary.declaredHostCount ?? 0))}</dd></div>
        </dl>
        ${drillButtons}
        <div class="inventory-provenance">
          <h3>Provenance</h3>
          ${this.renderProvenance(subnet.provenance || [])}
        </div>
      </div>
    `;
  }

  renderProvenance(entries) {
    if (!entries.length) {
      return '<div class="inventory-empty-detail">No provenance metadata available.</div>';
    }

    return `
      <ul class="inventory-provenance-list">
        ${entries.map(entry => `
          <li>
            <span>${this.escape(entry.module || 'unknown-module')}</span>
            <code>${this.escape(entry.path || 'unknown-path')}</code>
          </li>
        `).join('')}
      </ul>
    `;
  }

  renderEmptyDetail(message) {
    const detailEl = this.container?.querySelector(`#${this.id}-detail`);
    if (detailEl) {
      detailEl.innerHTML = `<div class="inventory-empty-detail">${this.escape(message)}</div>`;
    }
  }

  renderHostStatusChip(status) {
    if (!status) return '';
    return `<span class="inventory-status-chip inventory-status-${this.escape(status)}">${this.escape(status)}</span>`;
  }

  renderNeighborChip(neighbor) {
    if (!neighbor) return '';
    const state = neighbor.state || 'UNKNOWN';
    return ` <span class="inventory-neighbor-chip inventory-neigh-${this.escape(state.toLowerCase())}">${this.escape(state)}</span>`;
  }

  renderNeighborState(state) {
    if (!state) return '—';
    return `<span class="inventory-neighbor-chip inventory-neigh-${this.escape(state.toLowerCase())}">${this.escape(state)}</span>`;
  }

  renderSubnetSummary(summary = {}) {
    const live = summary.liveLeaseCount ?? 0;
    const conflicts = summary.conflictCount ?? 0;
    const neighbors = summary.neighborOnlyCount ?? 0;
    const stale = summary.staleCount ?? 0;
    const occupancy = this.formatOccupancy(summary);
    return `
      <span>${live} live</span>
      <span>${occupancy}</span>
      ${conflicts > 0 ? `<span class="inventory-conflict-text">${conflicts} conflict</span>` : ''}
      ${neighbors > 0 ? `<span class="inventory-neighbor-text">${neighbors} neighbor</span>` : ''}
      ${stale > 0 ? `<span class="inventory-stale-text">${stale} stale</span>` : ''}
    `;
  }

  formatOccupancy(summary = {}) {
    const capacity = summary.dynamicAddressCapacity ?? 0;
    if (capacity <= 0) return 'no pool';
    return `${summary.occupiedAddressCount ?? 0}/${capacity} (${summary.occupancyPercent ?? 0}%)`;
  }

  formatLeaseAge(expiresStr) {
    if (!expiresStr) return '';
    try {
      const expires = new Date(expiresStr);
      const now = new Date();
      const diffMs = expires - now;
      if (isNaN(diffMs)) return '';
      const absDiff = Math.abs(diffMs);
      const minutes = Math.floor(absDiff / 60000);
      const hours = Math.floor(minutes / 60);
      const days = Math.floor(hours / 24);
      let relative;
      if (days > 0) relative = `${days}d ${hours % 24}h`;
      else if (hours > 0) relative = `${hours}h ${minutes % 60}m`;
      else relative = `${minutes}m`;
      return diffMs > 0 ? ` (in ${relative})` : ` (${relative} ago)`;
    } catch {
      return '';
    }
  }

  escape(value) {
    return String(value ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }
}
