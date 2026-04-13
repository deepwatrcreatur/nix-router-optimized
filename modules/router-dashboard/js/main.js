/**
 * Router Dashboard Main
 * Initializes and manages all dashboard widgets
 */

class Dashboard {
  constructor() {
    this.widgets = [];
    this.config = window.DASHBOARD_CONFIG || {};
    this.lastUpdate = null;
    this.grids = new Map();
    this.layoutStorageKey = 'router-dashboard-layout-v2';
    this.legacyLayoutStorageKey = 'router-dashboard-layout-v1';
    this.activePageStorageKey = 'router-dashboard-active-page';
    this.pageOrder = [ 'overview', 'network', 'services', 'security', 'vpn' ];
    this.activePage = this.getInitialPage();
  }

  /**
   * Initialize the dashboard
   */
  async init() {
    console.log('Initializing Router Dashboard...');

    // Fetch initial system info for header
    await this.updateHeader();

    // Initialize widgets based on config
    this.initWidgets();
    this.initTabs();
    this.setupLayouts();
    this.bindLayoutControls();
    this.bindSearchControls();

    // Start header update interval
    setInterval(() => this.updateHeader(), 30000);

    console.log('Dashboard initialized with', this.widgets.length, 'widgets');
  }

  /**
   * Initialize all widgets
   */
  initWidgets() {
    // Quick Links widget
    const links = new LinksWidget({
      id: 'links',
      grid: { w: 4, h: 3 },
      links: this.config.links || [
        { label: 'Netdata', url: '/netdata/', icon: '📊' },
        { label: 'Grafana', url: '/grafana/', icon: '📈' },
        { label: 'DNS Admin', url: '/dns/', icon: '🌍' },
        { label: 'Prometheus', url: '/prometheus/', icon: '🎯' }
      ]
    });
    this.renderWidget('overview', links);

    // System Resources widget
    const system = new SystemWidget({
      id: 'system',
      grid: { w: 4, h: 4 },
      showDisk: true,
      refreshInterval: 5000
    });
    this.renderWidget('overview', system);

    const systemInfo = new SystemInfoWidget({
      id: 'system-info',
      grid: { w: 4, h: 4 },
      refreshInterval: 120000
    });
    this.renderWidget('overview', systemInfo);

    // Traffic Graph widget
    const traffic = new TrafficWidget({
      id: 'traffic',
      grid: { w: 6, h: 4 },
      interface: 'wan',
      refreshInterval: 5000
    });
    this.renderWidget('overview', traffic);

    // Interface widgets
    const interfaces = this.config.interfaces || [
      { device: 'wan', label: 'WAN', role: 'wan' },
      { device: 'lan', label: 'LAN', role: 'lan' },
      { device: 'mgmt', label: 'Management', role: 'mgmt' }
    ];

    interfaces.forEach(iface => {
      const widget = new InterfaceWidget({
        id: `iface-${iface.device}`,
        grid: { w: 3, h: 4 },
        interface: iface.device,
        label: iface.label,
        role: iface.role,
        refreshInterval: 5000
      });
      this.renderWidget('network', widget);
    });

    // Connections widget
    const connections = new ConnectionsWidget({
      id: 'connections',
      grid: { w: 3, h: 3 },
      refreshInterval: 5000
    });
    this.renderWidget('overview', connections);

    // Services widget
    const services = new ServicesWidget({
      id: 'services',
      grid: { w: 4, h: 4 },
      refreshInterval: 30000,
      services: this.config.services || [
        'nftables',
        'caddy',
        'prometheus',
        'grafana',
        'netdata',
        'technitium-dns-server'
      ]
    });
    this.renderWidget('services', services);

    // Gateway health widget
    const gateway = new GatewayWidget({
      id: 'gateway',
      grid: { w: 4, h: 4 },
      refreshInterval: 10000
    });
    this.renderWidget('overview', gateway);

    // Top connections widget
    const topConns = new TopConnectionsWidget({
      id: 'top-connections',
      grid: { w: 6, h: 4 },
      refreshInterval: 10000,
      limit: 15
    });
    this.renderWidget('network', topConns);

    // Firewall widget
    const firewall = new FirewallWidget({
      id: 'firewall',
      grid: { w: 3, h: 3 },
      refreshInterval: 30000
    });
    this.renderWidget('security', firewall);

    const firewallLogs = new FirewallLogsWidget({
      id: 'firewall-logs',
      grid: { w: 6, h: 4 }
    });
    this.renderWidget('security', firewallLogs);

    const caddy = new CaddyWidget({
      id: 'caddy',
      grid: { w: 4, h: 4 },
      refreshInterval: 30000
    });
    this.renderWidget('services', caddy);

    // DNS Statistics widget
    const dns = new DnsWidget({
      id: 'dns',
      grid: { w: 4, h: 4 },
      refreshInterval: 30000
    });
    this.renderWidget('services', dns);

    // DHCP Leases widget
    const dhcp = new DhcpWidget({
      id: 'dhcp',
      grid: { w: 6, h: 4 },
      refreshInterval: 60000
    });
    this.renderWidget('network', dhcp);

    // Fail2ban widget
    const fail2ban = new Fail2banWidget({
      id: 'fail2ban',
      grid: { w: 4, h: 4 },
      refreshInterval: 30000
    });
    this.renderWidget('security', fail2ban);

    // Speed test widget
    const speedtest = new SpeedtestWidget({
      id: 'speedtest',
      grid: { w: 4, h: 4 }
    });
    this.renderWidget('services', speedtest);

    if ((this.config.wolDevices || []).length > 0) {
      const wol = new WolWidget({
        id: 'wol',
        grid: { w: 4, h: 4 },
        devices: this.config.wolDevices
      });
      this.renderWidget('security', wol);
    }

    const vpn = new VpnWidget({
      id: 'vpn-status',
      grid: { w: 12, h: 5 },
      refreshInterval: 15000
    });
    this.renderWidget('vpn', vpn);
  }

  initTabs() {
    const buttons = Array.from(document.querySelectorAll('[data-dashboard-tab]'));
    buttons.forEach(button => {
      button.addEventListener('click', () => this.setActivePage(button.dataset.dashboardTab));
    });

    this.setActivePage(this.activePage, { persist: false, initializeLayout: false });
  }

  getInitialPage() {
    try {
      const saved = localStorage.getItem(this.activePageStorageKey);
      return this.pageOrder.includes(saved) ? saved : 'overview';
    } catch {
      return 'overview';
    }
  }

  setActivePage(pageId, options = {}) {
    if (!this.pageOrder.includes(pageId)) return;

    this.activePage = pageId;
    document.querySelectorAll('[data-dashboard-tab]').forEach(button => {
      button.classList.toggle('is-active', button.dataset.dashboardTab === pageId);
    });
    document.querySelectorAll('[data-dashboard-page]').forEach(page => {
      page.classList.toggle('is-active', page.dataset.dashboardPage === pageId);
    });

    if (options.persist !== false) {
      try {
        localStorage.setItem(this.activePageStorageKey, pageId);
      } catch (error) {
        console.warn('Failed to persist active dashboard page:', error);
      }
    }

    if (options.initializeLayout !== false) {
      this.initPageLayout(pageId);
    }
    this.resizePageWidgets(pageId);
  }

  renderWidget(pageId, widget) {
    widget.render(`#dashboard-grid-${pageId}`);
    this.widgets.push({ page: pageId, widget });
  }

  setupLayouts() {
    if (!window.GridStack) {
      console.warn('GridStack not available, using static layout');
      return;
    }

    this.initPageLayout(this.activePage);
  }

  initPageLayout(pageId) {
    if (!window.GridStack || this.grids.has(pageId)) return;

    const container = document.getElementById(`dashboard-grid-${pageId}`);
    if (!container) return;

    this.applySavedLayout(container, pageId);

    const grid = GridStack.init({
      column: 12,
      cellHeight: 96,
      margin: 8,
      float: true,
      handle: '.widget-header'
    }, container);

    grid.on('change', () => this.saveLayout(pageId));
    grid.on('resizestop', (_event, element) => this.handleWidgetResize(element));
    this.grids.set(pageId, grid);
  }

  applySavedLayout(container, pageId) {
    const savedLayout = this.loadLayout();
    const pageLayout = savedLayout[pageId] || [];
    if (!pageLayout.length && pageId === 'overview') {
      this.applyLegacySavedLayout(container);
      return;
    }
    if (!pageLayout.length) return;

    pageLayout.forEach(item => {
      const element = container.querySelector(`[data-widget-id="${item.id}"]`);
      if (!element) return;

      [ 'x', 'y', 'w', 'h' ].forEach(key => {
        if (Number.isInteger(item[key])) {
          element.setAttribute(`gs-${key}`, String(item[key]));
        }
      });
    });
  }

  saveLayout(pageId) {
    const grid = this.grids.get(pageId);
    if (!grid) return;

    const savedLayout = this.loadLayout();
    savedLayout[pageId] = grid.save(false).map(item => ({
      id: item.el?.dataset.widgetId,
      x: item.x,
      y: item.y,
      w: item.w,
      h: item.h
    })).filter(item => item.id);

    localStorage.setItem(this.layoutStorageKey, JSON.stringify(savedLayout));
  }

  loadLayout() {
    try {
      const saved = localStorage.getItem(this.layoutStorageKey);
      return saved ? JSON.parse(saved) : {};
    } catch {
      return {};
    }
  }

  bindLayoutControls() {
    const resetButton = document.getElementById('reset-layout-btn');
    if (resetButton) {
      resetButton.addEventListener('click', () => this.resetLayout());
    }
  }

  bindSearchControls() {
    const searchInput = document.getElementById('dashboard-search');
    if (!searchInput) return;

    searchInput.addEventListener('input', () => this.applySearch(searchInput.value));
    searchInput.addEventListener('keydown', event => {
      if (event.key === 'Escape') {
        searchInput.value = '';
        this.applySearch('');
        searchInput.blur();
      }
    });

    document.addEventListener('keydown', event => {
      const key = event.key.toLowerCase();
      if ((event.ctrlKey || event.metaKey) && key === 'k') {
        event.preventDefault();
        searchInput.focus();
        searchInput.select();
      }
    });
  }

  applySearch(query) {
    const normalizedQuery = query.trim().toLowerCase();
    const matches = [];

    this.widgets.forEach(entry => {
      const element = entry.widget.gridItem;
      if (!element) return;

      const text = [
        entry.widget.id,
        entry.widget.title,
        element.textContent
      ].filter(Boolean).join(' ').toLowerCase();
      const isMatch = normalizedQuery.length > 0 && text.includes(normalizedQuery);

      element.classList.toggle('is-search-match', isMatch);
      element.classList.toggle('is-search-dimmed', normalizedQuery.length > 0 && !isMatch);

      if (isMatch) {
        matches.push(entry.page);
      }
    });

    if (normalizedQuery.length > 0 && matches.length > 0 && !matches.includes(this.activePage)) {
      this.setActivePage(matches[0]);
    }
  }

  resetLayout() {
    localStorage.removeItem(this.layoutStorageKey);
    localStorage.removeItem(this.legacyLayoutStorageKey);
    localStorage.removeItem(this.activePageStorageKey);
    window.location.reload();
  }

  resizePageWidgets(pageId) {
    this.widgets
      .filter(entry => entry.page === pageId)
      .forEach(entry => {
        const element = entry.widget.gridItem;
        if (!element) return;
        entry.widget.onResize(element.clientWidth, element.clientHeight);
      });
  }

  applyLegacySavedLayout(container) {
    const savedLayout = this.loadLegacyLayout();
    if (!savedLayout.length) return;

    savedLayout.forEach(item => {
      const element = container.querySelector(`[data-widget-id="${item.id}"]`);
      if (!element) return;

      [ 'x', 'y', 'w', 'h' ].forEach(key => {
        if (Number.isInteger(item[key])) {
          element.setAttribute(`gs-${key}`, String(item[key]));
        }
      });
    });
  }

  loadLegacyLayout() {
    try {
      const saved = localStorage.getItem(this.legacyLayoutStorageKey);
      return saved ? JSON.parse(saved) : [];
    } catch {
      return [];
    }
  }

  handleWidgetResize(element) {
    const widgetId = element?.dataset?.widgetId;
    if (!widgetId) return;

    const widgetEntry = this.widgets.find(entry => entry.widget.id === widgetId);
    if (!widgetEntry) return;

    const width = element.clientWidth;
    const height = element.clientHeight;
    widgetEntry.widget.onResize(width, height);
  }

  /**
   * Update header information
   */
  async updateHeader() {
    try {
      const response = await fetch('/api/system/status');
      const data = await response.json();

      document.getElementById('hostname').textContent = data.hostname || 'Router';
      document.getElementById('uptime').textContent = data.uptime || '--';
      document.getElementById('kernel').textContent = data.kernel || '--';

      this.lastUpdate = new Date();
      document.getElementById('last-update').textContent =
        'Updated: ' + this.lastUpdate.toLocaleTimeString();
    } catch (error) {
      console.error('Failed to update header:', error);
    }
  }

  /**
   * Destroy all widgets
   */
  destroy() {
    this.widgets.forEach(entry => entry.widget.onDestroy());
    this.widgets = [];
    this.grids.forEach(grid => grid.destroy(false));
    this.grids.clear();
  }
}

// Initialize dashboard when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  window.dashboard = new Dashboard();
  window.dashboard.init();
});
