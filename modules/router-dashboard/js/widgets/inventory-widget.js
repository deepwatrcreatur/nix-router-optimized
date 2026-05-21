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

    statusEl.textContent = `${subnets.length} subnets • ${hosts.length} hosts • ${reservations.length} reserved addresses`;

    const visibleGroups = subnets
      .map(subnet => ({
        subnet,
        hosts: this.filterHostsForSubnet(subnet.id)
      }))
      .filter(group => this.groupMatches(group));

    if (visibleGroups.length === 0) {
      subnetsEl.innerHTML = '<div class="inventory-empty-list">No inventory entries match the current filter.</div>';
      this.renderEmptyDetail('No matching hosts or subnets.');
      return;
    }

    subnetsEl.innerHTML = visibleGroups.map(group => this.renderSubnetGroup(group)).join('');

    if (this.selectedHostId) {
      this.renderHostDetail(this.selectedHostId);
    } else {
      this.renderSubnetDetail(visibleGroups[0].subnet.id);
    }
  }

  filterHostsForSubnet(subnetId) {
    return (this.inventory?.hosts || []).filter(host => host.subnetRef === subnetId);
  }

  groupMatches(group) {
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
      host.sourceKind || ''
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
            <div class="inventory-subnet-meta">${this.escape(subnet.cidr)} · gateway ${this.escape(subnet.gatewayAddress || '--')}</div>
          </div>
          <div class="inventory-subnet-summary">
            <span>${this.escape(subnet.dhcpBackend || 'no-dhcp')}</span>
            <span>${visibleHosts.length} hosts</span>
          </div>
        </button>
        <div class="inventory-host-list">
          ${visibleHosts.length > 0
            ? visibleHosts.map(host => this.renderHostRow(host)).join('')
            : '<div class="inventory-empty-subnet">No declared hosts in this subnet.</div>'}
        </div>
      </section>
    `;
  }

  renderHostRow(host) {
    const selectedClass = host.id === this.selectedHostId ? ' is-selected' : '';
    return `
      <button class="inventory-host-row${selectedClass}" type="button" data-inventory-host-id="${this.escape(host.id)}">
        <div class="inventory-host-main">
          <span class="inventory-host-label">${this.escape(host.label)}</span>
          <span class="inventory-host-ip">${this.escape(host.ipv4Address)}</span>
        </div>
        <div class="inventory-host-meta">${this.escape(host.sourceKind || 'declared-host')}</div>
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
            <div class="inventory-detail-subtitle">${this.escape(host.sourceKind || 'declared-host')}</div>
          </div>
          <span class="inventory-badge">Read-only</span>
        </div>
        <dl class="inventory-detail-list">
          <div><dt>IPv4</dt><dd>${this.escape(host.ipv4Address)}</dd></div>
          <div><dt>Hostname</dt><dd>${this.escape(host.hostname || '—')}</dd></div>
          <div><dt>MAC</dt><dd>${this.escape(host.macAddress || '—')}</dd></div>
          <div><dt>Subnet</dt><dd>${this.escape(subnet ? `${subnet.label} (${subnet.cidr})` : host.subnetRef || '—')}</dd></div>
        </dl>
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
        </dl>
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

  escape(value) {
    return String(value ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }
}
