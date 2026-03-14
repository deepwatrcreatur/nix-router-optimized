/**
 * Speed Test Widget
 * Allows running on-demand internet speed tests
 */

class SpeedtestWidget extends BaseWidget {
  constructor(options = {}) {
    super({
      title: 'Speed Test',
      ...options
    });

    this.widgetClass = 'speedtest-widget';
    this.isRunning = false;
    this.pollInterval = null;
    this.history = this.loadHistory();
  }

  getMarkup() {
    return `
      <div class="widget-header">
        <h2>${this.title}</h2>
      </div>
      <div class="widget-body">
      <div class="speedtest-container">
        <div class="speedtest-results">
          <div class="speedtest-gauge-row">
            <div class="speedtest-gauge">
              <div class="speedtest-gauge-value" id="${this.id}-download">--</div>
              <div class="speedtest-gauge-label">Download</div>
              <div class="speedtest-gauge-unit">Mbps</div>
            </div>
            <div class="speedtest-gauge">
              <div class="speedtest-gauge-value" id="${this.id}-upload">--</div>
              <div class="speedtest-gauge-label">Upload</div>
              <div class="speedtest-gauge-unit">Mbps</div>
            </div>
            <div class="speedtest-gauge ping">
              <div class="speedtest-gauge-value" id="${this.id}-ping">--</div>
              <div class="speedtest-gauge-label">Ping</div>
              <div class="speedtest-gauge-unit">ms</div>
            </div>
          </div>
          <div class="speedtest-server" id="${this.id}-server">
            <span class="server-label">Server:</span>
            <span class="server-name">Not tested yet</span>
          </div>
        </div>

        <div class="speedtest-progress" id="${this.id}-progress" style="display: none;">
          <div class="speedtest-progress-bar">
            <div class="speedtest-progress-fill" id="${this.id}-progress-fill"></div>
          </div>
          <div class="speedtest-status" id="${this.id}-status">Initializing...</div>
        </div>

        <div class="speedtest-actions">
          <button class="speedtest-btn" id="${this.id}-run-btn">
            <span class="btn-icon">&#9654;</span>
            Run Speed Test
          </button>
        </div>

        <div class="speedtest-history" id="${this.id}-history">
          <div class="history-title">Recent Tests</div>
          <div class="history-list" id="${this.id}-history-list">
            ${this.renderHistory()}
          </div>
        </div>
      </div>
      </div>
    `;
  }

  onMounted() {
    // Bind run button
    const runBtn = document.getElementById(`${this.id}-run-btn`);
    if (runBtn) {
      runBtn.addEventListener('click', () => this.runSpeedTest());
    }

    // Load last result if available
    if (this.history.length > 0) {
      this.displayResult(this.history[0]);
    }

    // Check if a test is already running
    this.checkRunningTest();
  }

  async checkRunningTest() {
    try {
      const response = await fetch('/api/speedtest/status');
      const data = await response.json();

      if (data.running) {
        this.isRunning = true;
        this.showProgress();
        this.startPolling();
      }
    } catch (error) {
      // Ignore errors on initial check
    }
  }

  async runSpeedTest() {
    if (this.isRunning) return;

    this.isRunning = true;
    this.showProgress();
    this.updateStatus('Starting speed test...');
    this.setProgress(0);

    try {
      const response = await fetch('/api/speedtest/run', { method: 'POST' });
      const data = await response.json();

      if (data.error) {
        this.showError(data.error);
        this.isRunning = false;
        this.hideProgress();
        return;
      }

      // Start polling for results
      this.startPolling();
    } catch (error) {
      this.showError('Failed to start speed test');
      this.isRunning = false;
      this.hideProgress();
    }
  }

  startPolling() {
    // Clear any existing poll interval
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
    }

    this.pollInterval = setInterval(() => this.pollStatus(), 2000);
  }

  async pollStatus() {
    try {
      const response = await fetch('/api/speedtest/status');
      const data = await response.json();

      if (data.error && !data.running) {
        this.showError(data.error);
        this.stopPolling();
        return;
      }

      if (data.running) {
        this.updateStatus(data.stage || 'Testing...');
        this.setProgress(data.progress || 0);
      } else if (data.result) {
        // Test completed
        this.stopPolling();
        this.displayResult(data.result);
        this.addToHistory(data.result);
        this.hideProgress();
      } else if (!data.running && !data.result) {
        // No test running and no result - might have finished before we started polling
        this.stopPolling();
        this.hideProgress();
      }
    } catch (error) {
      console.error('Speed test poll error:', error);
    }
  }

  stopPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
    this.isRunning = false;
  }

  showProgress() {
    const progress = document.getElementById(`${this.id}-progress`);
    const runBtn = document.getElementById(`${this.id}-run-btn`);

    if (progress) progress.style.display = 'block';
    if (runBtn) {
      runBtn.disabled = true;
      runBtn.innerHTML = '<span class="btn-icon spinning">&#8635;</span> Testing...';
    }
  }

  hideProgress() {
    const progress = document.getElementById(`${this.id}-progress`);
    const runBtn = document.getElementById(`${this.id}-run-btn`);

    if (progress) progress.style.display = 'none';
    if (runBtn) {
      runBtn.disabled = false;
      runBtn.innerHTML = '<span class="btn-icon">&#9654;</span> Run Speed Test';
    }
  }

  updateStatus(status) {
    const statusEl = document.getElementById(`${this.id}-status`);
    if (statusEl) {
      statusEl.textContent = status;
      statusEl.classList.remove('error');
    }
  }

  setProgress(percent) {
    const fill = document.getElementById(`${this.id}-progress-fill`);
    if (fill) fill.style.width = `${percent}%`;
  }

  displayResult(result) {
    const downloadEl = document.getElementById(`${this.id}-download`);
    const uploadEl = document.getElementById(`${this.id}-upload`);
    const pingEl = document.getElementById(`${this.id}-ping`);
    const serverEl = document.getElementById(`${this.id}-server`);

    if (downloadEl) downloadEl.textContent = result.download?.toFixed(1) || '--';
    if (uploadEl) uploadEl.textContent = result.upload?.toFixed(1) || '--';
    if (pingEl) pingEl.textContent = result.ping?.toFixed(0) || '--';

    if (serverEl && result.server) {
      serverEl.innerHTML = `
        <span class="server-label">Server:</span>
        <span class="server-name">${result.server}</span>
      `;
    }
  }

  showError(message) {
    const statusEl = document.getElementById(`${this.id}-status`);
    if (statusEl) {
      statusEl.textContent = `Error: ${message}`;
      statusEl.classList.add('error');
      setTimeout(() => statusEl.classList.remove('error'), 5000);
    }
  }

  loadHistory() {
    try {
      const saved = localStorage.getItem('speedtest-history');
      return saved ? JSON.parse(saved) : [];
    } catch {
      return [];
    }
  }

  saveHistory() {
    try {
      localStorage.setItem('speedtest-history', JSON.stringify(this.history.slice(0, 10)));
    } catch {
      // Ignore storage errors
    }
  }

  addToHistory(result) {
    const entry = {
      ...result,
      timestamp: new Date().toISOString()
    };

    this.history.unshift(entry);
    this.history = this.history.slice(0, 10); // Keep last 10
    this.saveHistory();
    this.updateHistoryDisplay();
  }

  renderHistory() {
    if (this.history.length === 0) {
      return '<div class="history-empty">No recent tests</div>';
    }

    return this.history.slice(0, 5).map(entry => {
      const date = new Date(entry.timestamp);
      const timeStr = date.toLocaleDateString() + ' ' + date.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});

      return `
        <div class="history-entry">
          <span class="history-time">${timeStr}</span>
          <span class="history-download">${entry.download?.toFixed(1) || '--'} Mbps</span>
          <span class="history-upload">${entry.upload?.toFixed(1) || '--'} Mbps</span>
        </div>
      `;
    }).join('');
  }

  updateHistoryDisplay() {
    const historyList = document.getElementById(`${this.id}-history-list`);
    if (historyList) {
      historyList.innerHTML = this.renderHistory();
    }
  }

  onDestroy() {
    super.onDestroy();
    this.stopPolling();
  }
}

// Export for use
window.SpeedtestWidget = SpeedtestWidget;
