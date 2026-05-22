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
    this.statusFilter = 'all';
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
            <p>Browse declared reservations alongside live leases and neighbor evidence without leaving the router dashboard.</p>
          </div>
          <label class="inventory-filter">
            <span class="sr-only">Filter inventory</span>
            <input type="search" id="${this.id}-filter" placeholder="Search host, IP, subnet, or label">
          </label>
        </div>
        <div class="inventory-filter-bar" id="${this.id}-status-filters">
          ${this.renderStatusFilters()}
        </div>
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

      const statusButton = event.target.closest('[data-inventory-status-filter]');
      if (statusButton) {
        this.statusFilter = statusButton.dataset.inventoryStatusFilter || 'all';
        this.renderInventory();
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

      this.renderInventory();
      this.hideLoading();
    } catch (error) {
      this.hideLoading();
      this.showError(`Unable to load inventory: ${error.message}`);
    }
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

    statusEl.textContent = `${subnets.length} subnets • ${reservations.length} reserved addresses • ${runtimeSummary.liveLeaseCount || 0} live leases • ${runtimeSummary.neighborCount || 0} neighbors • ${runtimeSummary.conflictCount || 0} conflicts`;
    const filterBar = this.container?.querySelector(`#${this.id}-status-filters`);
    if (filterBar) {
      filterBar.innerHTML = this.renderStatusFilters();
    }

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

    const visibleHostIds = visibleGroups.flatMap(group => group.hosts.map(host => host.id));
    if (this.selectedHostId && !visibleHostIds.includes(this.selectedHostId)) {
      this.selectedHostId = visibleHostIds[0] || null;
    }

    if (this.selectedHostId) {
      this.renderHostDetail(this.selectedHostId);
    } else {
      this.renderSubnetDetail(visibleGroups[0].subnet.id);
    }
  }

  filterHostsForSubnet(subnetId) {
    return (this.inventory?.hosts || []).filter(host => (
      host.subnetRef === subnetId
      && this.hostMatchesFilters(host)
    ));
  }

  filterUnassignedHosts() {
    return (this.inventory?.hosts || []).filter(host => !host.subnetRef && this.hostMatchesFilters(host));
  }

  groupMatches(group) {
    if (!this.filter && this.statusFilter === 'all') return true;

    const subnetText = [
      group.subnet.label,
      group.subnet.cidr,
      group.subnet.gatewayAddress,
      group.subnet.dhcpBackend || ''
    ].join(' ').toLowerCase();

    const hostMatches = group.hosts.some(host => this.hostMatchesFilters(host));
    if (!this.filter) {
      return hostMatches;
    }

    return subnetText.includes(this.filter) || hostMatches;
  }

  hostMatches(host) {
    const text = [
      host.label,
      host.hostname || '',
      host.ipv4Address,
      host.macAddress || '',
      host.sourceKind || '',
      host.status || '',
      ...(host.reconciliationTags || [])
    ].join(' ').toLowerCase();
    return text.includes(this.filter);
  }

  hostMatchesStatus(host) {
    if (this.statusFilter === 'all') return true;
    if ((host.reconciliationTags || []).includes(this.statusFilter)) return true;
    return host.status === this.statusFilter;
  }

  hostMatchesFilters(host) {
    return this.hostMatchesStatus(host) && (!this.filter || this.hostMatches(host));
  }

  renderSubnetGroup(group) {
    const { subnet, hosts } = group;
    const visibleHosts = hosts;

    return `
      <section class="inventory-subnet-card">
        <button class="inventory-subnet-header" type="button" data-inventory-subnet-id="${this.escape(subnet.id)}">
          <div>
            <div class="inventory-subnet-name">${this.escape(subnet.label)}</div>
            <div class="inventory-subnet-meta">${this.escape(subnet.cidr)} · gateway ${this.escape(subnet.gatewayAddress || '--')}</div>
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
            : '<div class="inventory-empty-subnet">No hosts in this subnet match the current filters.</div>'}
        </div>
      </section>
    `;
  }

  renderHostRow(host) {
    const selectedClass = host.id === this.selectedHostId ? ' is-selected' : '';
    return `
      <button class="inventory-host-row${selectedClass}" type="button" data-inventory-host-id="${this.escape(host.id)}">
        <div class="inventory-host-main">
          <span class="inventory-host-label">${this.escape(host.label)} ${this.renderHostStatusChip(host.status)}</span>
          <span class="inventory-host-ip">${this.escape(host.ipv4Address)}</span>
        </div>
        <div class="inventory-host-meta">
          ${this.escape(host.sourceKind || 'declared-host')}
          ${this.renderTagList(host.reconciliationTags || [])}
        </div>
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

    detailEl.innerHTML = `
      <div class="inventory-detail-card">
        <div class="inventory-detail-header">
          <div>
            <div class="inventory-detail-title">${this.escape(host.label)}</div>
            <div class="inventory-detail-subtitle">${this.escape(host.sourceKind || 'declared-host')} · ${this.escape(host.status || 'declared')}</div>
          </div>
          <span class="inventory-badge">Read-only</span>
        </div>
        <dl class="inventory-detail-list">
          <div><dt>IPv4</dt><dd>${this.escape(host.ipv4Address)}</dd></div>
          <div><dt>Hostname</dt><dd>${this.escape(host.hostname || '—')}</dd></div>
          <div><dt>MAC</dt><dd>${this.escape(host.macAddress || '—')}</dd></div>
          <div><dt>Subnet</dt><dd>${this.escape(subnet ? `${subnet.label} (${subnet.cidr})` : host.subnetRef || '—')}</dd></div>
          <div><dt>Status</dt><dd>${this.escape(host.status || 'declared')}</dd></div>
          <div><dt>Tags</dt><dd>${this.escape((host.reconciliationTags || []).join(', ') || '—')}</dd></div>
          <div><dt>Lease Expires</dt><dd>${this.escape(host.runtimeLease?.leaseExpires || '—')}</dd></div>
        </dl>
        ${this.renderRuntimeEvidence(host)}
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
    const subnetHosts = (this.inventory?.hosts || []).filter(entry => entry.subnetRef === subnet.id);
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
          <div><dt>Live Leases</dt><dd>${this.escape(String(subnet.runtimeSummary?.liveLeaseCount ?? 0))}</dd></div>
          <div><dt>Visible Neighbors</dt><dd>${this.escape(String(subnet.runtimeSummary?.neighborCount ?? 0))}</dd></div>
          <div><dt>Conflicts</dt><dd>${this.escape(String(subnet.runtimeSummary?.conflictCount ?? 0))}</dd></div>
          <div><dt>Occupancy</dt><dd>${this.escape(this.formatOccupancy(subnet.runtimeSummary))}</dd></div>
        </dl>
        ${this.renderSubnetRuntimeCollections(subnetHosts)}
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

  renderRuntimeEvidence(host) {
    const evidence = host.runtimeEvidence || [];
    if (!evidence.length) {
      return '';
    }

    return `
      <div class="inventory-evidence">
        <h3>Runtime Evidence</h3>
        <div class="inventory-evidence-list">
          ${evidence.map(entry => `
            <div class="inventory-evidence-card">
              <div class="inventory-evidence-title">${this.escape(entry.type || 'runtime')}</div>
              <div class="inventory-evidence-meta">${this.escape(entry.address || '—')} · ${this.escape(entry.hardwareAddress || 'no-mac')}</div>
              <div class="inventory-evidence-meta">${this.escape(entry.interface || 'unknown-interface')}${entry.leaseExpires ? ` · lease ${this.escape(entry.leaseExpires)}` : ''}${entry.state ? ` · ${this.escape(entry.state)}` : ''}</div>
            </div>
          `).join('')}
        </div>
      </div>
    `;
  }

  renderSubnetRuntimeCollections(hosts) {
    const sections = [
      [ 'Reserved', hosts.filter(host => (host.reconciliationTags || []).includes('reserved')) ],
      [ 'Active Leases', hosts.filter(host => (host.reconciliationTags || []).includes('leased')) ],
      [ 'Runtime-only', hosts.filter(host => (host.reconciliationTags || []).includes('runtime-only')) ],
      [ 'Conflicts', hosts.filter(host => (host.reconciliationTags || []).includes('conflict')) ]
    ].filter(([, entries]) => entries.length > 0);

    if (!sections.length) {
      return '';
    }

    return `
      <div class="inventory-related">
        <h3>Subnet Runtime Breakdown</h3>
        <div class="inventory-related-sections">
          ${sections.map(([label, entries]) => `
            <div class="inventory-related-section">
              <div class="inventory-related-title">${this.escape(label)} <span>${entries.length}</span></div>
              <div class="inventory-related-items">
                ${entries.map(host => `
                  <button class="inventory-related-host" type="button" data-inventory-host-id="${this.escape(host.id)}">
                    <span>${this.escape(host.label)}</span>
                    <span>${this.escape(host.ipv4Address)}</span>
                  </button>
                `).join('')}
              </div>
            </div>
          `).join('')}
        </div>
      </div>
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

  renderStatusFilters() {
    const filters = [
      [ 'all', 'All' ],
      [ 'reserved', 'Reserved' ],
      [ 'leased', 'Leased' ],
      [ 'runtime-only', 'Runtime-only' ],
      [ 'conflict', 'Conflict' ],
      [ 'stale', 'Stale' ]
    ];
    return filters.map(([value, label]) => `
      <button
        class="inventory-filter-chip${this.statusFilter === value ? ' is-active' : ''}"
        type="button"
        data-inventory-status-filter="${this.escape(value)}"
      >${this.escape(label)}</button>
    `).join('');
  }

  renderTagList(tags) {
    if (!tags.length) return '';
    return `
      <span class="inventory-tag-list">
        ${tags.map(tag => `<span class="inventory-inline-tag">${this.escape(tag)}</span>`).join('')}
      </span>
    `;
  }

  renderSubnetSummary(summary = {}) {
    const live = summary.liveLeaseCount ?? 0;
    const conflicts = summary.conflictCount ?? 0;
    const occupancy = this.formatOccupancy(summary);
    return `
      <span>${live} live</span>
      <span>${occupancy}</span>
      ${conflicts > 0 ? `<span class="inventory-conflict-text">${conflicts} conflict</span>` : ''}
    `;
  }

  formatOccupancy(summary = {}) {
    const capacity = summary.dynamicAddressCapacity ?? 0;
    if (capacity <= 0) return 'no pool';
    return `${summary.occupiedAddressCount ?? 0}/${capacity} (${summary.occupancyPercent ?? 0}%)`;
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
