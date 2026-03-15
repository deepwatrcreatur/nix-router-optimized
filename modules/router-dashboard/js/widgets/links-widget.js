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
    const linksHtml = this.links.map(link => {
      if (link.kind === 'copy') {
        return `
          <button type="button" class="link-btn link-btn-copy" data-copy-text="${this.escapeAttr(link.copyText || '')}">
            ${link.icon || ''} ${link.label}
          </button>
        `;
      }

      return `
        <a href="${link.url}" class="link-btn" target="_blank" rel="noopener">
          ${link.icon || ''} ${link.label}
        </a>
      `;
    }).join('');

    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
      </div>
      <div class="widget-body">
        <div class="quick-links">
          ${linksHtml}
        </div>
        <div class="quick-links-feedback" id="${this.id}-feedback"></div>
      </div>
    `;
  }

  onMounted() {
    this.container?.querySelectorAll('.link-btn-copy').forEach(button => {
      button.addEventListener('click', async () => {
        const text = button.dataset.copyText || '';
        if (!text) {
          return;
        }

        try {
          await this.copyText(text);
          this.showFeedback(`Copied: ${text}`);
        } catch (_error) {
          this.showFeedback(`Copy failed. Use: ${text}`);
          window.prompt('Copy this text:', text);
        }
      });
    });
  }

  async onTick() {
    // No refresh needed for static links
  }

  showFeedback(message) {
    const feedback = this.container?.querySelector(`#${this.id}-feedback`);
    if (!feedback) {
      return;
    }

    feedback.textContent = message;
    feedback.classList.add('visible');
    window.clearTimeout(this.feedbackTimer);
    this.feedbackTimer = window.setTimeout(() => {
      feedback.classList.remove('visible');
    }, 2500);
  }

  escapeAttr(value) {
    return value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  }

  async copyText(text) {
    if (navigator.clipboard?.writeText && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return;
    }

    const textarea = document.createElement('textarea');
    textarea.value = text;
    textarea.setAttribute('readonly', '');
    textarea.style.position = 'fixed';
    textarea.style.top = '-1000px';
    textarea.style.left = '-1000px';
    document.body.appendChild(textarea);
    textarea.focus();
    textarea.select();

    try {
      if (!document.execCommand('copy')) {
        throw new Error('execCommand copy failed');
      }
    } finally {
      document.body.removeChild(textarea);
    }
  }
}

window.LinksWidget = LinksWidget;
