/**
 * Base Widget Class
 * All dashboard widgets extend this class
 */
class BaseWidget {
  constructor(config = {}) {
    this.id = config.id || this.generateId();
    this.title = config.title || 'Widget';
    this.refreshInterval = config.refreshInterval || 5000;
    this.grid = config.grid || null;
    this.container = null;
    this.gridItem = null;
    this.intervalId = null;
    this.isLoading = true;
    this.hasError = false;
    this.errorMessage = '';
  }

  generateId() {
    return 'widget-' + Math.random().toString(36).substr(2, 9);
  }

  /**
   * Returns the HTML structure for the widget
   * Override in subclass
   */
  getMarkup() {
    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
      </div>
      <div class="widget-body">
        <p>Widget content goes here</p>
      </div>
    `;
  }

  /**
   * Called after widget is added to DOM
   * Override for initialization
   */
  onMounted() {}

  /**
   * Called on each refresh cycle
   * Override to fetch and update data
   */
  async onTick() {}

  /**
   * Called when widget is removed
   */
  onDestroy() {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  /**
   * Called when widget is resized
   */
  onResize(width, height) {}

  /**
   * Render the widget to a container element
   */
  render(containerSelector) {
    const container = document.querySelector(containerSelector);
    if (!container) {
      console.error(`Container not found: ${containerSelector}`);
      return;
    }

    const gridItem = document.createElement('div');
    gridItem.className = 'grid-stack-item';
    gridItem.dataset.widgetId = this.id;

    const gridConfig = this.getGridConfig();
    Object.entries(gridConfig).forEach(([key, value]) => {
      gridItem.setAttribute(`gs-${key}`, String(value));
    });

    const wrapper = document.createElement('div');
    wrapper.id = this.id;
    wrapper.className = 'grid-stack-item-content widget ' + (this.widgetClass || '');
    wrapper.innerHTML = this.getMarkup();
    gridItem.appendChild(wrapper);
    container.appendChild(gridItem);

    this.gridItem = gridItem;
    this.container = wrapper;
    this.onMounted();
    this.start();
  }

  getGridConfig() {
    if (this.grid) {
      return this.grid;
    }

    const sizeClass = (this.widgetClass || '').split(' ').find(name =>
      [ 'widget-sm', 'widget-md', 'widget-lg', 'widget-xl', 'widget-full' ].includes(name));

    const defaults = {
      'widget-sm': { w: 3, h: 3 },
      'widget-md': { w: 4, h: 4 },
      'widget-lg': { w: 6, h: 4 },
      'widget-xl': { w: 8, h: 5 },
      'widget-full': { w: 12, h: 4 }
    };

    return defaults[sizeClass] || { w: 4, h: 4 };
  }

  /**
   * Start the refresh cycle
   */
  start() {
    this.onTick();
    if (this.refreshInterval > 0) {
      this.intervalId = setInterval(() => this.onTick(), this.refreshInterval);
    }
  }

  /**
   * Stop the refresh cycle
   */
  stop() {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  }

  /**
   * Helper to fetch from API
   */
  async fetchAPI(endpoint) {
    const response = await fetch(`/api${endpoint}`);
    if (!response.ok) {
      throw new Error(`API error: ${response.status}`);
    }
    return response.json();
  }

  /**
   * Format bytes to human readable
   */
  formatBytes(bytes, rate = false) {
    if (bytes === 0 || bytes === undefined || bytes === null) {
      return rate ? '0 B/s' : '0 B';
    }
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(Math.abs(bytes)) / Math.log(k));
    const value = parseFloat((bytes / Math.pow(k, i)).toFixed(1));
    const suffix = rate ? '/s' : '';
    return value + ' ' + sizes[i] + suffix;
  }

  /**
   * Format percentage
   */
  formatPercent(value, decimals = 1) {
    if (value === undefined || value === null) return '--%';
    return value.toFixed(decimals) + '%';
  }

  /**
   * Show loading state
   */
  showLoading() {
    this.isLoading = true;
    const body = this.container?.querySelector('.widget-body');
    if (body) {
      body.classList.add('loading');
    }
  }

  /**
   * Hide loading state
   */
  hideLoading() {
    this.isLoading = false;
    const body = this.container?.querySelector('.widget-body');
    if (body) {
      body.classList.remove('loading');
    }
  }

  /**
   * Show error state
   */
  showError(message) {
    this.hasError = true;
    this.errorMessage = message;
    const body = this.container?.querySelector('.widget-body');
    if (body) {
      body.innerHTML = `<div class="error-message">${message}</div>`;
    }
  }

  /**
   * Update element text content safely
   */
  updateElement(selector, value) {
    const el = this.container?.querySelector(selector);
    if (el) {
      el.textContent = value;
    }
  }

  /**
   * Update element HTML safely
   */
  updateHTML(selector, html) {
    const el = this.container?.querySelector(selector);
    if (el) {
      el.innerHTML = html;
    }
  }
}

// Export for use in other modules
window.BaseWidget = BaseWidget;
