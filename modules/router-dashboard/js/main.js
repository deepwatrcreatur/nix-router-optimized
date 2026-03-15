/**
 * Router Dashboard Main
 * Initializes and manages all dashboard widgets
 */

class Dashboard {
  constructor() {
    this.widgets = [];
    this.config = window.DASHBOARD_CONFIG || {};
    this.lastUpdate = null;
    this.grid = null;
    this.layoutStorageKey = 'router-dashboard-layout-v1';
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
    this.setupLayout();
    this.bindLayoutControls();

    // Start header update interval
    setInterval(() => this.updateHeader(), 30000);

    console.log('Dashboard initialized with', this.widgets.length, 'widgets');
  }

  /**
   * Initialize all widgets
   */
  initWidgets() {
    const container = '#dashboard-grid';

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
    links.render(container);
    this.widgets.push(links);

    // System Resources widget
    const system = new SystemWidget({
      id: 'system',
      grid: { w: 4, h: 4 },
      showDisk: true,
      refreshInterval: 5000
    });
    system.render(container);
    this.widgets.push(system);

    // Traffic Graph widget
    const traffic = new TrafficWidget({
      id: 'traffic',
      grid: { w: 6, h: 4 },
      interface: 'wan',
      refreshInterval: 5000
    });
    traffic.render(container);
    this.widgets.push(traffic);

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
        interface: iface.role || iface.device,
        label: iface.label,
        role: iface.role,
        refreshInterval: 5000
      });
      widget.render(container);
      this.widgets.push(widget);
    });

    // Connections widget
    const connections = new ConnectionsWidget({
      id: 'connections',
      grid: { w: 3, h: 3 },
      refreshInterval: 5000
    });
    connections.render(container);
    this.widgets.push(connections);

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
    services.render(container);
    this.widgets.push(services);

    // Gateway health widget
    const gateway = new GatewayWidget({
      id: 'gateway',
      grid: { w: 4, h: 4 },
      refreshInterval: 10000
    });
    gateway.render(container);
    this.widgets.push(gateway);

    // Top connections widget
    const topConns = new TopConnectionsWidget({
      id: 'top-connections',
      grid: { w: 6, h: 5 },
      refreshInterval: 10000,
      limit: 15
    });
    topConns.render(container);
    this.widgets.push(topConns);

    // Firewall widget
    const firewall = new FirewallWidget({
      id: 'firewall',
      grid: { w: 3, h: 3 },
      refreshInterval: 30000
    });
    firewall.render(container);
    this.widgets.push(firewall);

    const firewallLogs = new FirewallLogsWidget({
      id: 'firewall-logs',
      grid: { w: 6, h: 5 }
    });
    firewallLogs.render(container);
    this.widgets.push(firewallLogs);

    const caddy = new CaddyWidget({
      id: 'caddy',
      grid: { w: 4, h: 5 },
      refreshInterval: 30000
    });
    caddy.render(container);
    this.widgets.push(caddy);

    // DNS Statistics widget
    const dns = new DnsWidget({
      id: 'dns',
      grid: { w: 4, h: 4 },
      refreshInterval: 30000
    });
    dns.render(container);
    this.widgets.push(dns);

    // DHCP Leases widget
    const dhcp = new DhcpWidget({
      id: 'dhcp',
      grid: { w: 6, h: 5 },
      refreshInterval: 60000
    });
    dhcp.render(container);
    this.widgets.push(dhcp);

    // Fail2ban widget
    const fail2ban = new Fail2banWidget({
      id: 'fail2ban',
      grid: { w: 4, h: 4 },
      refreshInterval: 30000
    });
    fail2ban.render(container);
    this.widgets.push(fail2ban);

    // Speed test widget
    const speedtest = new SpeedtestWidget({
      id: 'speedtest',
      grid: { w: 4, h: 4 }
    });
    speedtest.render(container);
    this.widgets.push(speedtest);

    if ((this.config.wolDevices || []).length > 0) {
      const wol = new WolWidget({
        id: 'wol',
        grid: { w: 4, h: 4 },
        devices: this.config.wolDevices
      });
      wol.render(container);
      this.widgets.push(wol);
    }
  }

  setupLayout() {
    if (!window.GridStack) {
      console.warn('GridStack not available, using static layout');
      return;
    }

    const container = document.getElementById('dashboard-grid');
    if (!container) return;

    this.applySavedLayout(container);

    this.grid = GridStack.init({
      column: 12,
      cellHeight: 96,
      margin: 10,
      float: true,
      handle: '.widget-header'
    }, container);

    this.grid.on('change', () => this.saveLayout());
    this.grid.on('resizestop', (_event, element) => this.handleWidgetResize(element));
  }

  applySavedLayout(container) {
    const savedLayout = this.loadLayout();
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

  saveLayout() {
    if (!this.grid) return;

    const layout = this.grid.save(false).map(item => ({
      id: item.el?.dataset.widgetId,
      x: item.x,
      y: item.y,
      w: item.w,
      h: item.h
    })).filter(item => item.id);

    localStorage.setItem(this.layoutStorageKey, JSON.stringify(layout));
  }

  loadLayout() {
    try {
      const saved = localStorage.getItem(this.layoutStorageKey);
      return saved ? JSON.parse(saved) : [];
    } catch {
      return [];
    }
  }

  bindLayoutControls() {
    const resetButton = document.getElementById('reset-layout-btn');
    if (resetButton) {
      resetButton.addEventListener('click', () => this.resetLayout());
    }
  }

  resetLayout() {
    localStorage.removeItem(this.layoutStorageKey);
    window.location.reload();
  }

  handleWidgetResize(element) {
    const widgetId = element?.dataset?.widgetId;
    if (!widgetId) return;

    const widget = this.widgets.find(entry => entry.id === widgetId);
    if (!widget) return;

    const width = element.clientWidth;
    const height = element.clientHeight;
    widget.onResize(width, height);
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
    this.widgets.forEach(w => w.onDestroy());
    this.widgets = [];
    if (this.grid) {
      this.grid.destroy(false);
      this.grid = null;
    }
  }
}

// Initialize dashboard when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  window.dashboard = new Dashboard();
  window.dashboard.init();
});
