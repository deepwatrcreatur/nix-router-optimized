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
    this.selectedInterfaceId = null;
    this.selectedPrefixId = null;
    this.activeView = 'hosts';
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>Inventory Browser</h2>
        <span class="inventory-badge">Read-only</span>
      </div>
      <div class="widget-body inventory-body">
        <div class="inventory-toolbar">
          <nav class="inventory-view-tabs" role="tablist">
            <button class="inventory-view-tab is-active" type="button" data-inventory-view="hosts" role="tab">Hosts</button>
            <button class="inventory-view-tab" type="button" data-inventory-view="interfaces" role="tab">Interfaces</button>
            <button class="inventory-view-tab" type="button" data-inventory-view="prefixes" role="tab">Prefixes</button>
          </nav>
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
            <div class="inventory-empty-detail">Select an item to inspect details.</div>
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
        this.renderActiveView();
      });
    }

    this.container?.addEventListener('click', event => {
      const viewTab = event.target.closest('[data-inventory-view]');
      if (viewTab) {
        this.activeView = viewTab.dataset.inventoryView;
        this.container.querySelectorAll('.inventory-view-tab').forEach(tab => {
          tab.classList.toggle('is-active', tab.dataset.inventoryView === this.activeView);
        });
        this.renderActiveView();
        return;
      }

      const hostButton = event.target.closest('[data-inventory-host-id]');
      if (hostButton) {
        this.selectedHostId = hostButton.dataset.inventoryHostId;
        this.renderActiveView();
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
        return;
      }

      const ifaceButton = event.target.closest('[data-inventory-iface-id]');
      if (ifaceButton) {
        this.selectedInterfaceId = ifaceButton.dataset.inventoryIfaceId;
        this.renderInterfaceDetail(this.selectedInterfaceId);
        this.highlightSelected('[data-inventory-iface-id]', this.selectedInterfaceId, 'inventoryIfaceId');
        return;
      }

      const prefixButton = event.target.closest('[data-inventory-prefix-id]');
      if (prefixButton) {
        this.selectedPrefixId = prefixButton.dataset.inventoryPrefixId;
        this.renderPrefixDetail(this.selectedPrefixId);
        this.highlightSelected('[data-inventory-prefix-id]', this.selectedPrefixId, 'inventoryPrefixId');
        return;
      }

      const crossLink = event.target.closest('[data-inventory-cross-link]');
      if (crossLink) {
        const targetId = crossLink.dataset.inventoryCrossLink;
        const targetView = crossLink.dataset.inventoryCrossView;
        if (targetView && targetId) {
          this.activeView = targetView;
          this.container.querySelectorAll('.inventory-view-tab').forEach(tab => {
            tab.classList.toggle('is-active', tab.dataset.inventoryView === this.activeView);
          });
          if (targetView === 'interfaces') this.selectedInterfaceId = targetId;
          if (targetView === 'prefixes') this.selectedPrefixId = targetId;
          if (targetView === 'hosts') this.selectedHostId = targetId;
          this.renderActiveView();
        }
        return;
      }
    });
  }

  highlightSelected(selector, selectedId, dataKey) {
    const listEl = this.container?.querySelector(`#${this.id}-subnets`);
    if (!listEl) return;
    listEl.querySelectorAll(selector).forEach(el => {
      el.classList.toggle('is-selected', el.dataset[dataKey] === selectedId);
    });
  }

  async onTick() {
    try {
      const data = await this.fetchAPI('/inventory');
      this.inventory = data;

      if (!this.selectedHostId && (data.hosts || []).length > 0) {
        this.selectedHostId = data.hosts[0].id;
      }
      if (!this.selectedInterfaceId && (data.interfaces || []).length > 0) {
        this.selectedInterfaceId = data.interfaces[0].id;
      }
      if (!this.selectedPrefixId && (data.prefixes || []).length > 0) {
        this.selectedPrefixId = data.prefixes[0].id;
      }

      this.renderActiveView();
      this.hideLoading();
    } catch (error) {
      this.hideLoading();
      this.showError(`Unable to load inventory: ${error.message}`);
    }
  }

  renderActiveView() {
    if (this.activeView === 'interfaces') {
      this.renderInterfacesView();
    } else if (this.activeView === 'prefixes') {
      this.renderPrefixesView();
    } else {
      this.renderInventory();
    }
  }

  // ── Hosts view (original) ──

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
          <div><dt>Subnet</dt><dd>${subnet
            ? `<a class="inventory-cross-link" data-inventory-cross-link="${this.escape(subnet.id)}" data-inventory-cross-view="hosts">${this.escape(subnet.label)} (${this.escape(subnet.cidr)})</a>`
            : this.escape(host.subnetRef || '—')}</dd></div>
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
    const matchingPrefix = (this.inventory?.prefixes || []).find(p => p.id === `prefix:${subnet.id}`);
    const matchingIface = subnet.interface
      ? (this.inventory?.interfaces || []).find(i => i.device === subnet.interface.device)
      : null;
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
          ${matchingIface ? `<div><dt>Interface</dt><dd><a class="inventory-cross-link" data-inventory-cross-link="${this.escape(matchingIface.id)}" data-inventory-cross-view="interfaces">${this.escape(matchingIface.name)} (${this.escape(matchingIface.device)})</a></dd></div>` : ''}
          ${matchingPrefix ? `<div><dt>Prefix</dt><dd><a class="inventory-cross-link" data-inventory-cross-link="${this.escape(matchingPrefix.id)}" data-inventory-cross-view="prefixes">${this.escape(matchingPrefix.cidr)}</a></dd></div>` : ''}
        </dl>
        ${this.renderSubnetRuntimeCollections(subnetHosts)}
        <div class="inventory-provenance">
          <h3>Provenance</h3>
          ${this.renderProvenance(subnet.provenance || [])}
        </div>
      </div>
    `;
  }

  // ── Interfaces view ──

  renderInterfacesView() {
    const statusEl = this.container?.querySelector(`#${this.id}-status`);
    const listEl = this.container?.querySelector(`#${this.id}-subnets`);
    if (!statusEl || !listEl) return;

    if (!this.inventory || this.inventory.available === false) {
      statusEl.textContent = this.inventory?.message || 'Inventory unavailable';
      listEl.innerHTML = '';
      this.renderEmptyDetail(this.inventory?.message || 'Inventory unavailable');
      return;
    }

    const interfaces = this.inventory.interfaces || [];
    const visible = this.filter
      ? interfaces.filter(iface => this.interfaceMatches(iface))
      : interfaces;

    const byRole = {};
    for (const iface of visible) {
      const role = iface.role || 'other';
      (byRole[role] = byRole[role] || []).push(iface);
    }

    statusEl.textContent = `${interfaces.length} interfaces · ${(this.inventory.prefixes || []).length} prefixes`;

    if (visible.length === 0) {
      listEl.innerHTML = '<div class="inventory-empty-list">No interfaces match the current filter.</div>';
      this.renderEmptyDetail('No matching interfaces.');
      return;
    }

    const roleOrder = ['wan', 'lan', 'management', 'opt', 'vpn', 'other'];
    const roleLabels = { wan: 'WAN', lan: 'LAN', management: 'Management', opt: 'Optional', vpn: 'VPN', other: 'Other' };

    listEl.innerHTML = roleOrder
      .filter(role => byRole[role]?.length > 0)
      .map(role => `
        <section class="inventory-subnet-card">
          <div class="inventory-subnet-header inventory-role-header">
            <div>
              <div class="inventory-subnet-name">${this.escape(roleLabels[role] || role)}</div>
              <div class="inventory-subnet-meta">${byRole[role].length} interface${byRole[role].length !== 1 ? 's' : ''}</div>
            </div>
          </div>
          <div class="inventory-host-list">
            ${byRole[role].map(iface => this.renderInterfaceRow(iface)).join('')}
          </div>
        </section>
      `).join('');

    if (this.selectedInterfaceId) {
      this.renderInterfaceDetail(this.selectedInterfaceId);
      this.highlightSelected('[data-inventory-iface-id]', this.selectedInterfaceId, 'inventoryIfaceId');
    } else if (visible.length > 0) {
      this.selectedInterfaceId = visible[0].id;
      this.renderInterfaceDetail(this.selectedInterfaceId);
      this.highlightSelected('[data-inventory-iface-id]', this.selectedInterfaceId, 'inventoryIfaceId');
    }
  }

  interfaceMatches(iface) {
    const text = [
      iface.name,
      iface.device || '',
      iface.role || '',
      iface.kind || '',
      iface.ipv4Address || '',
      iface.parentDevice || ''
    ].join(' ').toLowerCase();
    return text.includes(this.filter);
  }

  renderInterfaceRow(iface) {
    const selectedClass = iface.id === this.selectedInterfaceId ? ' is-selected' : '';
    const kindBadge = iface.kind && iface.kind !== 'physical'
      ? `<span class="inventory-status-chip inventory-kind-${this.escape(iface.kind)}">${this.escape(iface.kind)}</span>`
      : '';
    return `
      <button class="inventory-host-row${selectedClass}" type="button" data-inventory-iface-id="${this.escape(iface.id)}">
        <div class="inventory-host-main">
          <span class="inventory-host-label">${this.escape(iface.name)} ${kindBadge}</span>
          <span class="inventory-host-ip">${this.escape(iface.device || '—')}</span>
        </div>
        <div class="inventory-host-meta">${this.escape(iface.ipv4Address || iface.role || '—')}</div>
      </button>
    `;
  }

  renderInterfaceDetail(ifaceId) {
    const iface = (this.inventory?.interfaces || []).find(i => i.id === ifaceId);
    if (!iface) {
      this.renderEmptyDetail('Select an interface to inspect details.');
      return;
    }

    const detailEl = this.container?.querySelector(`#${this.id}-detail`);
    if (!detailEl) return;

    const linkedPrefixes = (this.inventory?.prefixes || []).filter(p => p.interfaceRef === iface.id);
    const linkedSubnets = (iface.subnetRefs || []).map(ref =>
      (this.inventory?.subnets || []).find(s => s.id === ref)
    ).filter(Boolean);

    detailEl.innerHTML = `
      <div class="inventory-detail-card">
        <div class="inventory-detail-header">
          <div>
            <div class="inventory-detail-title">${this.escape(iface.name)}</div>
            <div class="inventory-detail-subtitle">${this.escape(iface.role || '—')} · ${this.escape(iface.kind || 'physical')}</div>
          </div>
          <span class="inventory-badge">Read-only</span>
        </div>
        <dl class="inventory-detail-list">
          <div><dt>Device</dt><dd>${this.escape(iface.device || '—')}</dd></div>
          <div><dt>Kind</dt><dd>${this.escape(iface.kind || 'physical')}</dd></div>
          <div><dt>Role</dt><dd>${this.escape(iface.role || '—')}</dd></div>
          <div><dt>IPv4 Address</dt><dd>${this.escape(iface.ipv4Address || '—')}</dd></div>
          <div><dt>IPv6 Prefix</dt><dd>${this.escape(iface.ipv6Prefix || '—')}</dd></div>
          ${iface.vlanId != null ? `<div><dt>VLAN ID</dt><dd>${this.escape(String(iface.vlanId))}</dd></div>` : ''}
          ${iface.parentDevice ? `<div><dt>Parent Device</dt><dd>${this.escape(iface.parentDevice)}</dd></div>` : ''}
          ${iface.mtu != null ? `<div><dt>MTU</dt><dd>${this.escape(String(iface.mtu))}</dd></div>` : ''}
        </dl>
        ${linkedSubnets.length > 0 ? `
          <div class="inventory-related">
            <h3>Subnets</h3>
            <ul class="inventory-related-list">
              ${linkedSubnets.map(subnet => `
                <li><a class="inventory-cross-link" data-inventory-cross-link="${this.escape(subnet.id)}" data-inventory-cross-view="hosts">${this.escape(subnet.label)} — ${this.escape(subnet.cidr)}</a></li>
              `).join('')}
            </ul>
          </div>
        ` : ''}
        ${linkedPrefixes.length > 0 ? `
          <div class="inventory-related">
            <h3>Prefixes</h3>
            <ul class="inventory-related-list">
              ${linkedPrefixes.map(prefix => `
                <li><a class="inventory-cross-link" data-inventory-cross-link="${this.escape(prefix.id)}" data-inventory-cross-view="prefixes">${this.escape(prefix.cidr)} — ${this.escape(prefix.label)}</a></li>
              `).join('')}
            </ul>
          </div>
        ` : ''}
        <div class="inventory-provenance">
          <h3>Provenance</h3>
          ${this.renderProvenance(iface.provenance || [])}
        </div>
      </div>
    `;
  }

  // ── Prefixes view ──

  renderPrefixesView() {
    const statusEl = this.container?.querySelector(`#${this.id}-status`);
    const listEl = this.container?.querySelector(`#${this.id}-subnets`);
    if (!statusEl || !listEl) return;

    if (!this.inventory || this.inventory.available === false) {
      statusEl.textContent = this.inventory?.message || 'Inventory unavailable';
      listEl.innerHTML = '';
      this.renderEmptyDetail(this.inventory?.message || 'Inventory unavailable');
      return;
    }

    const prefixes = this.inventory.prefixes || [];
    const visible = this.filter
      ? prefixes.filter(prefix => this.prefixMatches(prefix))
      : prefixes;

    statusEl.textContent = `${prefixes.length} prefixes · ${(this.inventory.interfaces || []).length} interfaces`;

    if (visible.length === 0) {
      listEl.innerHTML = '<div class="inventory-empty-list">No prefixes match the current filter.</div>';
      this.renderEmptyDetail('No matching prefixes.');
      return;
    }

    listEl.innerHTML = `
      <section class="inventory-subnet-card">
        <div class="inventory-subnet-header inventory-role-header">
          <div>
            <div class="inventory-subnet-name">Declared Prefixes</div>
            <div class="inventory-subnet-meta">${visible.length} prefix${visible.length !== 1 ? 'es' : ''}</div>
          </div>
        </div>
        <div class="inventory-host-list">
          ${visible.map(prefix => this.renderPrefixRow(prefix)).join('')}
        </div>
      </section>
    `;

    if (this.selectedPrefixId) {
      this.renderPrefixDetail(this.selectedPrefixId);
      this.highlightSelected('[data-inventory-prefix-id]', this.selectedPrefixId, 'inventoryPrefixId');
    } else if (visible.length > 0) {
      this.selectedPrefixId = visible[0].id;
      this.renderPrefixDetail(this.selectedPrefixId);
      this.highlightSelected('[data-inventory-prefix-id]', this.selectedPrefixId, 'inventoryPrefixId');
    }
  }

  prefixMatches(prefix) {
    const iface = prefix.interfaceRef
      ? (this.inventory?.interfaces || []).find(i => i.id === prefix.interfaceRef)
      : null;
    const text = [
      prefix.cidr,
      prefix.label,
      prefix.role || '',
      prefix.dhcpBackend || '',
      prefix.gatewayAddress || '',
      iface?.name || '',
      iface?.device || ''
    ].join(' ').toLowerCase();
    return text.includes(this.filter);
  }

  renderPrefixRow(prefix) {
    const selectedClass = prefix.id === this.selectedPrefixId ? ' is-selected' : '';
    const iface = prefix.interfaceRef
      ? (this.inventory?.interfaces || []).find(i => i.id === prefix.interfaceRef)
      : null;
    const ifaceLabel = iface ? iface.name : '—';
    return `
      <button class="inventory-host-row${selectedClass}" type="button" data-inventory-prefix-id="${this.escape(prefix.id)}">
        <div class="inventory-host-main">
          <span class="inventory-host-label">${this.escape(prefix.cidr)}</span>
          <span class="inventory-host-ip">${this.escape(prefix.label)}</span>
        </div>
        <div class="inventory-host-meta">${this.escape(ifaceLabel)} · ${prefix.hostCount} host${prefix.hostCount !== 1 ? 's' : ''} · ${this.escape(prefix.dhcpBackend || 'no-dhcp')}</div>
      </button>
    `;
  }

  renderPrefixDetail(prefixId) {
    const prefix = (this.inventory?.prefixes || []).find(p => p.id === prefixId);
    if (!prefix) {
      this.renderEmptyDetail('Select a prefix to inspect details.');
      return;
    }

    const detailEl = this.container?.querySelector(`#${this.id}-detail`);
    if (!detailEl) return;

    const iface = prefix.interfaceRef
      ? (this.inventory?.interfaces || []).find(i => i.id === prefix.interfaceRef)
      : null;

    const subnet = (this.inventory?.subnets || []).find(s => s.id === prefix.id.replace('prefix:', ''));
    const hostsInPrefix = (this.inventory?.hosts || []).filter(h => h.subnetRef === prefix.id.replace('prefix:', ''));

    const pools = prefix.dynamicPools || [];

    detailEl.innerHTML = `
      <div class="inventory-detail-card">
        <div class="inventory-detail-header">
          <div>
            <div class="inventory-detail-title">${this.escape(prefix.cidr)}</div>
            <div class="inventory-detail-subtitle">${this.escape(prefix.label)}</div>
          </div>
          <span class="inventory-badge">Read-only</span>
        </div>
        <dl class="inventory-detail-list">
          <div><dt>CIDR</dt><dd>${this.escape(prefix.cidr)}</dd></div>
          <div><dt>Gateway</dt><dd>${this.escape(prefix.gatewayAddress || '—')}</dd></div>
          <div><dt>Role</dt><dd>${this.escape(prefix.role || '—')}</dd></div>
          <div><dt>DHCP Backend</dt><dd>${this.escape(prefix.dhcpBackend || 'none')}</dd></div>
          <div><dt>Dynamic Pools</dt><dd>${this.escape(pools.map(pool => `${pool.start} - ${pool.end}`).join(', ') || '—')}</dd></div>
          <div><dt>Declared Hosts</dt><dd>${prefix.hostCount}</dd></div>
          ${iface ? `<div><dt>Interface</dt><dd><a class="inventory-cross-link" data-inventory-cross-link="${this.escape(iface.id)}" data-inventory-cross-view="interfaces">${this.escape(iface.name)} (${this.escape(iface.device)})</a></dd></div>` : ''}
        </dl>
        ${hostsInPrefix.length > 0 ? `
          <div class="inventory-related">
            <h3>Addresses in this prefix</h3>
            <ul class="inventory-related-list">
              ${hostsInPrefix.slice(0, 20).map(host => `
                <li><a class="inventory-cross-link" data-inventory-cross-link="${this.escape(host.id)}" data-inventory-cross-view="hosts">${this.escape(host.ipv4Address)} — ${this.escape(host.label)}</a></li>
              `).join('')}
              ${hostsInPrefix.length > 20 ? `<li class="inventory-related-more">+ ${hostsInPrefix.length - 20} more</li>` : ''}
            </ul>
          </div>
        ` : ''}
        <div class="inventory-provenance">
          <h3>Provenance</h3>
          ${this.renderProvenance(prefix.provenance || [])}
        </div>
      </div>
    `;
  }

  // ── Shared helpers ──

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
