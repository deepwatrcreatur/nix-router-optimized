/**
 * Router Dashboard Main
 * Initializes and manages all dashboard widgets
 */

class Dashboard {
  constructor() {
    this.widgets = [];
    this.config = window.DASHBOARD_CONFIG || {};
    this.lastUpdate = null;
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
      showDisk: true,
      refreshInterval: 5000
    });
    system.render(container);
    this.widgets.push(system);

    // Traffic Graph widget
    const traffic = new TrafficWidget({
      id: 'traffic',
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
        interface: iface.device,
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
      refreshInterval: 5000
    });
    connections.render(container);
    this.widgets.push(connections);

    // Services widget
    const services = new ServicesWidget({
      id: 'services',
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
      refreshInterval: 10000
    });
    gateway.render(container);
    this.widgets.push(gateway);

    // Top connections widget
    const topConns = new TopConnectionsWidget({
      id: 'top-connections',
      refreshInterval: 10000,
      limit: 15
    });
    topConns.render(container);
    this.widgets.push(topConns);

    // Firewall widget
    const firewall = new FirewallWidget({
      id: 'firewall',
      refreshInterval: 30000
    });
    firewall.render(container);
    this.widgets.push(firewall);
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
  }
}

// Initialize dashboard when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  window.dashboard = new Dashboard();
  window.dashboard.init();
});
