/**
 * Quick Links Widget
 * Displays links to other services
 */
class LinksWidget extends BaseWidget {
  constructor(config = {}) {
    super(config);
    this.title = config.title || 'Quick Links';
    this.widgetClass = 'widget-md';
    this.refreshInterval = 0; // No refresh needed
    this.links = config.links || [
      { label: 'Netdata', url: 'http://gateway:8080', icon: '📊' },
      { label: 'Grafana', url: 'http://gateway:3001', icon: '📈' },
      { label: 'DNS Admin', url: 'http://gateway:5380', icon: '🌍' },
      { label: 'Prometheus', url: 'http://gateway:9090', icon: '🎯' },
      { label: 'Proxy Manager', url: 'http://gateway:81', icon: '🔀' }
    ];
  }

  getMarkup() {
    const linksHtml = this.links.map(link => `
      <a href="${link.url}" class="link-btn" target="_blank" rel="noopener">
        ${link.icon || ''} ${link.label}
      </a>
    `).join('');

    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
      </div>
      <div class="widget-body">
        <div class="quick-links">
          ${linksHtml}
        </div>
      </div>
    `;
  }

  async onTick() {
    // No refresh needed for static links
  }
}

window.LinksWidget = LinksWidget;
