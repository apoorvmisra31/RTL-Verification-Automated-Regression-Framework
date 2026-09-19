/**
 * app.js - Main Application Controller for Verification Dashboard
 * Handles navigation, REST API interactions, Server-Sent Events, and UI state.
 */

document.addEventListener('DOMContentLoaded', () => {
  // Global State
  const state = {
    tests: [],
    system: null,
    latestSummary: null,
    activeTab: 'overview',
    selectedTestForModal: null,
    waveViewer: null,
    activeJob: null,
  };

  // Initialize Waveform Viewer Canvas
  state.waveViewer = new WaveformViewer('waveform-canvas', 'waveform-canvas-container');

  // Elements
  const els = {
    navItems: document.querySelectorAll('.nav-item'),
    tabPanels: document.querySelectorAll('.tab-panel'),
    currentViewTitle: document.getElementById('current-view-title'),
    currentViewSubtitle: document.getElementById('current-view-subtitle'),
    statusPill: document.getElementById('status-pill'),
    statusLabel: document.getElementById('status-label'),
    liveJobBanner: document.getElementById('live-job-banner'),
    jobBannerTitle: document.getElementById('job-banner-title'),
    jobBannerDetail: document.getElementById('job-banner-detail'),
    jobProgressBar: document.getElementById('job-progress-bar'),
    jobProgressPct: document.getElementById('job-progress-pct'),
    btnCancelJob: document.getElementById('btn-cancel-job'),

    // Overview KPIs
    kpiTotalTests: document.getElementById('kpi-total-tests'),
    kpiPassRate: document.getElementById('kpi-pass-rate'),
    kpiPassCount: document.getElementById('kpi-pass-count'),
    kpiDuration: document.getElementById('kpi-duration'),
    kpiTimestamp: document.getElementById('kpi-timestamp'),
    kpiSimName: document.getElementById('kpi-sim-name'),
    categoryBreakdown: document.getElementById('category-breakdown'),

    // Test Catalog
    tableTestsCatalog: document.getElementById('tbody-tests-catalog'),
    selectTestCategory: document.getElementById('select-test-category'),

    // Regression View
    btnStartRegression: document.getElementById('btn-start-regression'),
    btnQuickRegression: document.getElementById('btn-quick-regression'),
    chkRegressionWave: document.getElementById('chk-regression-wave'),
    regStateVal: document.getElementById('reg-state-val'),
    regActiveTest: document.getElementById('reg-active-test'),
    regElapsedTime: document.getElementById('reg-elapsed-time'),
    regProgressFill: document.getElementById('reg-progress-fill'),
    regressionTerminalBody: document.getElementById('regression-terminal-body'),
    btnClearTerminal: document.getElementById('btn-clear-terminal'),
    tbodyRegressionResults: document.getElementById('tbody-regression-results'),

    // Waveform Debug
    selectWaveTest: document.getElementById('select-wave-test'),
    btnLoadWaveform: document.getElementById('btn-load-waveform'),
    btnOpenGtkwave: document.getElementById('btn-open-gtkwave'),

    // Logs View
    selectLogTest: document.getElementById('select-log-test'),
    inputLogFilter: document.getElementById('input-log-filter'),
    logContentPre: document.getElementById('log-content-pre'),

    // Reports View
    reportTabBtns: document.querySelectorAll('.report-tab-btn'),
    reportMdRender: document.getElementById('report-md-render'),
    reportCsvRender: document.getElementById('report-csv-render'),
    reportJsonRender: document.getElementById('report-json-render'),
    btnDownloadJson: document.getElementById('btn-download-json'),
    btnDownloadCsv: document.getElementById('btn-download-csv'),
    btnDownloadMd: document.getElementById('btn-download-md'),

    // Defect Lab
    selectDefectMacro: document.getElementById('select-defect-macro'),
    defectDescBox: document.getElementById('defect-desc-box'),
    btnRunDefectDemo: document.getElementById('btn-run-defect-demo'),
    defectTerminalBody: document.getElementById('defect-terminal-body'),
    step1: document.getElementById('step-1'),
    step2: document.getElementById('step-2'),
    step3: document.getElementById('step-3'),

    // System Settings
    systemInfoGrid: document.getElementById('system-info-grid'),
    btnCleanWorkspace: document.getElementById('btn-clean-workspace'),
    btnCleanSystem: document.getElementById('btn-clean-system'),
    btnRefreshSystem: document.getElementById('btn-refresh-system'),

    // Modal
    modalRunTest: document.getElementById('modal-run-test'),
    modalTestTitle: document.getElementById('modal-test-title'),
    modalTestDesc: document.getElementById('modal-test-desc'),
    modalInputSeed: document.getElementById('modal-input-seed'),
    modalChkWave: document.getElementById('modal-chk-wave'),
    modalSelectBug: document.getElementById('modal-select-bug'),
    btnModalClose: document.getElementById('btn-modal-close'),
    btnModalCancel: document.getElementById('btn-modal-cancel'),
    btnModalExecute: document.getElementById('btn-modal-execute'),

    toastContainer: document.getElementById('toast-container'),
  };

  const VIEW_TITLES = {
    overview: { title: "Verification Overview", sub: "System metrics, real-time simulator status, and quick operations" },
    tests: { title: "Verification Test Catalog", sub: "Discovered SystemVerilog test suite with on-demand execution" },
    regression: { title: "Automated Regression Suite", sub: "Execute full verification regressions with live streaming diagnostics" },
    waveforms: { title: "Digital Waveform Debugger", sub: "Interactive in-browser logic timing viewer and GTKWave desktop launching" },
    logs: { title: "Simulation Log Inspector", sub: "Searchable test traces, SVA assertions, and scoreboard comparators" },
    reports: { title: "Generated Regression Deliverables", sub: "Machine-readable JSON, CSV metrics, and Markdown reports" },
    'defect-lab': { title: "Hardware Defect Injection Lab", sub: "Deterministic demonstration of defect detection and verification integrity" },
    system: { title: "System Environment & Diagnostics", sub: "Toolchain discovery, compiler paths, and workspace management" },
  };

  // --------------------------------------------------------------------------
  // Tab Switching
  // --------------------------------------------------------------------------
  function switchTab(tabName) {
    state.activeTab = tabName;
    els.navItems.forEach(btn => {
      btn.classList.toggle('active', btn.dataset.tab === tabName);
    });
    els.tabPanels.forEach(panel => {
      panel.classList.toggle('active', panel.id === `tab-${tabName}`);
    });

    const meta = VIEW_TITLES[tabName] || { title: "Verification Dashboard", sub: "" };
    els.currentViewTitle.textContent = meta.title;
    els.currentViewSubtitle.textContent = meta.sub;

    if (tabName === 'waveforms') {
      setTimeout(() => state.waveViewer.render(), 50);
    } else if (tabName === 'reports') {
      loadReportViews();
    }
  }

  els.navItems.forEach(btn => {
    btn.addEventListener('click', () => switchTab(btn.dataset.tab));
  });

  // Quick action buttons in Overview
  document.getElementById('btn-quick-reset-test')?.addEventListener('click', () => openTestModal('test_reset'));
  document.getElementById('btn-quick-burst-test')?.addEventListener('click', () => openTestModal('test_burst_write_read'));
  document.getElementById('btn-quick-overflow-test')?.addEventListener('click', () => openTestModal('test_overflow'));
  document.getElementById('btn-quick-defect-lab')?.addEventListener('click', () => switchTab('defect-lab'));

  // --------------------------------------------------------------------------
  // Toast Notifications
  // --------------------------------------------------------------------------
  function showToast(msg, type = 'info') {
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.textContent = msg;
    els.toastContainer.appendChild(toast);
    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateY(10px)';
      toast.style.transition = 'all 0.2s ease';
      setTimeout(() => toast.remove(), 200);
    }, 3500);
  }

  // --------------------------------------------------------------------------
  // Server-Sent Events (SSE) for Real-Time Execution Tracking
  // --------------------------------------------------------------------------
  function initSSE() {
    const eventSource = new EventSource('/api/job-stream');

    eventSource.addEventListener('state', (e) => {
      try {
        const job = JSON.parse(e.data);
        handleJobStateUpdate(job);
      } catch (err) {
        console.error("SSE state parse error:", err);
      }
    });

    eventSource.addEventListener('log', (e) => {
      try {
        const data = JSON.parse(e.data);
        appendTerminalLine(data.log);
      } catch (err) {
        console.error("SSE log parse error:", err);
      }
    });

    eventSource.onerror = () => {
      // Fallback polling if SSE drops
      setTimeout(pollJobStatus, 2000);
    };
  }

  function pollJobStatus() {
    fetch('/api/job-status')
      .then(res => res.json())
      .then(job => handleJobStateUpdate(job))
      .catch(err => console.error("Poll error:", err));
  }

  function handleJobStateUpdate(job) {
    state.activeJob = job;
    const isRunning = ['PREPARING', 'COMPILING', 'RUNNING'].includes(job.status);

    // Update Global Banner
    if (isRunning) {
      els.liveJobBanner.classList.remove('hidden');
      els.jobBannerTitle.textContent = `Executing ${job.job_type === 'regression' ? 'Regression Suite' : (job.job_type === 'defect_demo' ? 'Defect Lab Demo' : 'Test ' + (job.active_test || ''))}...`;
      els.jobBannerDetail.textContent = job.active_test ? `Active Test: ${job.active_test} (${job.current_index}/${job.total_tests})` : 'Compiling simulation snapshots...';
      els.jobProgressBar.style.width = `${job.progress_pct}%`;
      els.jobProgressPct.textContent = `${job.progress_pct}%`;
    } else {
      els.liveJobBanner.classList.add('hidden');
    }

    // Update Regression View Panel
    els.regStateVal.textContent = job.status;
    els.regActiveTest.textContent = job.active_test || 'None';
    els.regElapsedTime.textContent = `${job.elapsed_sec.toFixed(2)}s`;
    els.regProgressFill.style.width = `${job.progress_pct}%`;

    // Handle Defect Demo Stepper
    if (job.job_type === 'defect_demo') {
      if (job.demo_step === 'STAGE_1_INJECT') {
        els.step1.className = 'step-item active';
        els.step2.className = 'step-item';
        els.step3.className = 'step-item';
      } else if (job.demo_step === 'STAGE_2_RESTORE') {
        els.step1.className = 'step-item completed';
        els.step2.className = 'step-item active';
        els.step3.className = 'step-item';
      } else if (job.demo_step === 'STAGE_3_VERIFIED') {
        els.step1.className = 'step-item completed';
        els.step2.className = 'step-item completed';
        els.step3.className = 'step-item completed';
      }
    }

    // When job completes, refresh reports and tests
    if (job.status === 'COMPLETED' || job.status === 'FAILED') {
      if (job.latest_result && job.latest_result.summary) {
        updateRegressionResultsTable(job.latest_result.test_results);
        updateKPIs(job.latest_result);
      }
    }
  }

  function appendTerminalLine(line) {
    const lineEl = document.createElement('div');
    lineEl.className = 'term-line';

    if (line.includes('ERROR') || line.includes('FAIL') || line.includes('FATAL')) {
      lineEl.classList.add('error');
    } else if (line.includes('WARN')) {
      lineEl.classList.add('warn');
    } else if (line.includes('PASS') || line.includes('PASSED') || line.includes('SUCCESS')) {
      lineEl.classList.add('success');
    } else if (line.includes('INFO') || line.includes('[BUILD]') || line.includes('[RUN]')) {
      lineEl.classList.add('info');
    }

    lineEl.textContent = line;
    els.regressionTerminalBody.appendChild(lineEl);
    els.regressionTerminalBody.scrollTop = els.regressionTerminalBody.scrollHeight;

    // Mirror to Defect Lab terminal if active
    if (state.activeJob && state.activeJob.job_type === 'defect_demo') {
      const clone = lineEl.cloneNode(true);
      els.defectTerminalBody.appendChild(clone);
      els.defectTerminalBody.scrollTop = els.defectTerminalBody.scrollHeight;
    }
  }

  // Cancel Job
  els.btnCancelJob.addEventListener('click', () => {
    fetch('/api/cancel-job', { method: 'POST' })
      .then(res => res.json())
      .then(data => {
        if (data.cancelled) showToast('Verification job cancelled.', 'info');
      });
  });

  els.btnClearTerminal.addEventListener('click', () => {
    els.regressionTerminalBody.innerHTML = '';
  });

  // --------------------------------------------------------------------------
  // Data Loaders: Status, Tests, Reports
  // --------------------------------------------------------------------------
  function loadSystemStatus() {
    fetch('/api/status')
      .then(res => res.json())
      .then(data => {
        state.system = data.system;
        const simReady = data.system.simulator_ready;

        els.statusPill.className = `system-status-pill ${simReady ? 'online' : 'offline'}`;
        els.statusLabel.textContent = simReady ? `${data.system.simulator} Ready` : 'Simulator Offline';
        els.kpiSimName.textContent = data.system.simulator;

        // Render system info grid
        els.systemInfoGrid.innerHTML = `
          <div class="sys-info-card">
            <div class="sys-info-label">Operating Platform</div>
            <div class="sys-info-val">${data.system.platform} (macOS / Apple Silicon)</div>
          </div>
          <div class="sys-info-card">
            <div class="sys-info-label">Python Environment</div>
            <div class="sys-info-val">Python ${data.system.python_version} (Zero External Deps)</div>
          </div>
          <div class="sys-info-card">
            <div class="sys-info-label">Icarus Verilog Compiler (iverilog)</div>
            <div class="sys-info-val">${data.system.iverilog_path || 'Not Found'}</div>
          </div>
          <div class="sys-info-card">
            <div class="sys-info-label">Simulator Runtime (vvp)</div>
            <div class="sys-info-val">${data.system.vvp_path || 'Not Found'}</div>
          </div>
          <div class="sys-info-card">
            <div class="sys-info-label">Waveform Viewer (GTKWave)</div>
            <div class="sys-info-val">${data.system.gtkwave_path || 'Not Installed (Optional GUI)'}</div>
          </div>
          <div class="sys-info-card">
            <div class="sys-info-label">Project Root Directory</div>
            <div class="sys-info-val">${data.project.root_dir}</div>
          </div>
        `;
      });
  }

  function loadTests() {
    fetch('/api/tests')
      .then(res => res.json())
      .then(data => {
        state.tests = data.tests;
        renderTestCatalog(data.tests);
        populateDropdowns(data.tests);
        renderOverviewCategories(data.tests);
      });
  }

  function populateDropdowns(tests) {
    els.selectWaveTest.innerHTML = '<option value="">Select Test Waveform...</option>';
    els.selectLogTest.innerHTML = '<option value="">Select Test Log...</option>';

    tests.forEach(t => {
      const optW = document.createElement('option');
      optW.value = t.name;
      optW.textContent = `${t.name} (${t.title})`;
      els.selectWaveTest.appendChild(optW);

      const optL = document.createElement('option');
      optL.value = t.name;
      optL.textContent = `${t.name}.log`;
      els.selectLogTest.appendChild(optL);
    });

    // Auto-select first available wave
    if (tests.length > 0) {
      els.selectWaveTest.value = tests[1].name; // test_single_write_read
      els.selectLogTest.value = tests[0].name;
      loadTestLog(tests[0].name);
    }
  }

  function renderTestCatalog(tests) {
    els.tableTestsCatalog.innerHTML = '';
    const selectedCategory = els.selectTestCategory.value;

    tests.forEach(t => {
      if (selectedCategory !== 'ALL' && t.category !== selectedCategory) return;

      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>
          <div class="font-mono font-medium">${t.name}</div>
          <div class="text-xs text-muted">${t.title}</div>
        </td>
        <td><span class="badge badge-outline">${t.category}</span></td>
        <td class="text-xs text-secondary" style="max-width: 320px;">${t.description}</td>
        <td>
          <div class="flex gap-2">
            ${t.has_log ? '<span class="badge badge-success text-xs">LOG</span>' : '<span class="badge badge-outline text-xs">NO LOG</span>'}
            ${t.has_wave ? '<span class="badge badge-warning text-xs">VCD</span>' : ''}
          </div>
        </td>
        <td class="text-right">
          <button class="btn btn-secondary btn-sm btn-run-single" data-test="${t.name}">Run</button>
          <button class="btn btn-primary btn-sm btn-config-single" data-test="${t.name}">Configure...</button>
        </td>
      `;
      els.tableTestsCatalog.appendChild(tr);
    });

    // Attach listeners
    document.querySelectorAll('.btn-run-single').forEach(btn => {
      btn.addEventListener('click', () => {
        runSingleTestDirect(btn.dataset.test);
      });
    });

    document.querySelectorAll('.btn-config-single').forEach(btn => {
      btn.addEventListener('click', () => {
        openTestModal(btn.dataset.test);
      });
    });
  }

  els.selectTestCategory.addEventListener('change', () => {
    renderTestCatalog(state.tests);
  });

  function renderOverviewCategories(tests) {
    const counts = {};
    tests.forEach(t => {
      counts[t.category] = (counts[t.category] || 0) + 1;
    });

    els.categoryBreakdown.innerHTML = '';
    for (const [cat, num] of Object.entries(counts)) {
      const row = document.createElement('div');
      row.className = 'category-row';
      row.innerHTML = `
        <span class="text-secondary">${cat}</span>
        <span class="font-mono font-bold">${num} test${num > 1 ? 's' : ''}</span>
      `;
      els.categoryBreakdown.appendChild(row);
    }
  }

  // --------------------------------------------------------------------------
  // Single Test Execution Modal & Direct Launch
  // --------------------------------------------------------------------------
  function openTestModal(testName) {
    const test = state.tests.find(t => t.name === testName);
    if (!test) return;

    state.selectedTestForModal = test;
    els.modalTestTitle.textContent = `Configure Test: ${test.name}`;
    els.modalTestDesc.textContent = test.description;
    els.modalRunTest.classList.remove('hidden');
  }

  els.btnModalClose.addEventListener('click', () => els.modalRunTest.classList.add('hidden'));
  els.btnModalCancel.addEventListener('click', () => els.modalRunTest.classList.add('hidden'));

  els.btnModalExecute.addEventListener('click', () => {
    if (!state.selectedTestForModal) return;
    const seed = parseInt(els.modalInputSeed.value, 10) || 42;
    const wave = els.modalChkWave.checked;
    const bug = els.modalSelectBug.value || null;

    els.modalRunTest.classList.add('hidden');
    switchTab('regression');

    fetch('/api/run-test', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        test_name: state.selectedTestForModal.name,
        seed: seed,
        wave: wave,
        bug_macro: bug,
      }),
    })
      .then(res => res.json())
      .then(data => {
        if (data.error) showToast(data.error, 'error');
        else showToast(`Launched ${state.selectedTestForModal.name}`, 'info');
      })
      .catch(err => showToast(`Execution failed: ${err}`, 'error'));
  });

  function runSingleTestDirect(testName) {
    switchTab('regression');
    fetch('/api/run-test', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ test_name: testName, seed: 42, wave: true }),
    })
      .then(res => res.json())
      .then(data => {
        if (data.error) showToast(data.error, 'error');
        else showToast(`Running ${testName}...`, 'info');
      });
  }

  // --------------------------------------------------------------------------
  // Full Regression Launcher
  // --------------------------------------------------------------------------
  function triggerFullRegression() {
    switchTab('regression');
    const wave = els.chkRegressionWave.checked;

    fetch('/api/run-regression', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ seed: 42, wave: wave }),
    })
      .then(res => res.json())
      .then(data => {
        if (data.error) showToast(data.error, 'error');
        else showToast("Full regression started.", 'info');
      })
      .catch(err => showToast(`Failed to start: ${err}`, 'error'));
  }

  els.btnStartRegression.addEventListener('click', triggerFullRegression);
  els.btnQuickRegression.addEventListener('click', triggerFullRegression);

  // --------------------------------------------------------------------------
  // Regression Results Matrix Table
  // --------------------------------------------------------------------------
  function updateRegressionResultsTable(results) {
    els.tbodyRegressionResults.innerHTML = '';
    results.forEach(t => {
      const tr = document.createElement('tr');
      const passTag = t.passed ? '<span class="badge badge-success">PASS</span>' : '<span class="badge badge-danger">FAIL</span>';
      tr.innerHTML = `
        <td class="font-mono font-medium">${t.test_name}</td>
        <td>${passTag}</td>
        <td class="font-mono text-xs">${t.duration_sec.toFixed(3)}s</td>
        <td class="font-mono text-xs">${t.data_mismatches}</td>
        <td class="font-mono text-xs">${t.assertion_failures}</td>
        <td class="text-xs text-secondary">${t.details}</td>
        <td class="text-right">
          <button class="btn btn-secondary btn-sm btn-view-matrix-log" data-test="${t.test_name}">View Log</button>
        </td>
      `;
      els.tbodyRegressionResults.appendChild(tr);
    });

    document.querySelectorAll('.btn-view-matrix-log').forEach(btn => {
      btn.addEventListener('click', () => {
        switchTab('logs');
        els.selectLogTest.value = btn.dataset.test;
        loadTestLog(btn.dataset.test);
      });
    });
  }

  function updateKPIs(reportData) {
    if (!reportData || !reportData.summary) return;
    const s = reportData.summary;
    els.kpiTotalTests.textContent = s.total_tests;
    els.kpiPassRate.textContent = s.pass_rate;
    els.kpiPassCount.textContent = `${s.passed} Passed • ${s.failed} Failed`;
    els.kpiDuration.textContent = `${s.total_duration_sec.toFixed(3)}s`;
    els.kpiTimestamp.textContent = `Executed: ${new Date(reportData.timestamp).toLocaleTimeString()}`;

    const badge = document.getElementById('badge-regression-overall');
    if (badge) {
      badge.className = `badge ${s.overall_status === 'PASSED' ? 'badge-success' : 'badge-danger'}`;
      badge.textContent = `${s.passed}/${s.total_tests} ${s.overall_status}`;
    }
  }

  // --------------------------------------------------------------------------
  // Waveform Viewer
  // --------------------------------------------------------------------------
  els.btnLoadWaveform.addEventListener('click', () => {
    const test = els.selectWaveTest.value;
    if (!test) {
      showToast("Please select a test waveform.", "warn");
      return;
    }
    loadWaveformForTest(test);
  });

  function loadWaveformForTest(testName) {
    showToast(`Loading waveform for ${testName}...`, 'info');
    fetch(`/api/waves/parse?test=${testName}`)
      .then(res => res.json())
      .then(data => {
        if (data.error) {
          showToast(data.error, 'error');
          state.waveViewer.renderEmpty(data.error);
        } else {
          state.waveViewer.loadWaveform(data);
          showToast(`Waveform loaded: ${data.signals.length} signals`, 'info');
        }
      })
      .catch(err => showToast(`Waveform load error: ${err}`, 'error'));
  }

  els.btnOpenGtkwave.addEventListener('click', () => {
    let test = els.selectWaveTest.value;
    if (!test && els.selectWaveTest.options.length > 1) {
      els.selectWaveTest.selectedIndex = 1;
      test = els.selectWaveTest.value;
    }
    if (!test) {
      showToast("Select a test first.", "warn");
      return;
    }

    const origHtml = els.btnOpenGtkwave.innerHTML;
    els.btnOpenGtkwave.disabled = true;
    els.btnOpenGtkwave.innerHTML = `
      <svg class="spin" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10" stroke-dasharray="32" stroke-linecap="round"/></svg>
      <span>Opening GTKWave...</span>
    `;

    fetch('/api/waves/open', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ test_name: test }),
    })
      .then(res => res.json())
      .then(data => {
        if (data.success) {
          showToast(data.message, 'success');
        } else {
          showToast(data.error || 'Failed to open GTKWave', 'error');
        }
      })
      .catch(err => {
        showToast(`Network error: ${err.message}`, 'error');
      })
      .finally(() => {
        els.btnOpenGtkwave.disabled = false;
        els.btnOpenGtkwave.innerHTML = origHtml;
      });
  });

  // --------------------------------------------------------------------------
  // Log Inspector
  // --------------------------------------------------------------------------
  els.selectLogTest.addEventListener('change', () => {
    loadTestLog(els.selectLogTest.value);
  });

  function loadTestLog(testName) {
    if (!testName) return;
    fetch(`/api/logs/${testName}`)
      .then(res => res.json())
      .then(data => {
        if (data.log) {
          state.rawLog = data.log;
          filterAndRenderLog(data.log);
        } else {
          els.logContentPre.textContent = data.error || "Log file not found.";
        }
      })
      .catch(err => {
        els.logContentPre.textContent = `Error loading log: ${err}`;
      });
  }

  els.inputLogFilter.addEventListener('input', () => {
    if (state.rawLog) filterAndRenderLog(state.rawLog);
  });

  function filterAndRenderLog(rawText) {
    const query = els.inputLogFilter.value.trim().toLowerCase();
    const lines = rawText.split('\n');
    let filtered = lines;

    if (query) {
      filtered = lines.filter(l => l.toLowerCase().includes(query));
    }

    els.logContentPre.textContent = filtered.join('\n');
  }

  // --------------------------------------------------------------------------
  // Reports & Deliverables
  // --------------------------------------------------------------------------
  function loadReportViews() {
    // Markdown
    fetch('/api/reports/file?type=md')
      .then(res => res.text())
      .then(mdText => {
        renderMarkdown(mdText);
      });

    // JSON
    fetch('/api/reports/latest')
      .then(res => res.json())
      .then(jsonObj => {
        state.latestSummary = jsonObj;
        els.reportJsonRender.textContent = JSON.stringify(jsonObj, null, 2);
        updateKPIs(jsonObj);
        if (jsonObj.test_results) {
          updateRegressionResultsTable(jsonObj.test_results);
          renderCsvTable(jsonObj.test_results);
        }
      });
  }

  function renderMarkdown(md) {
    // Basic Markdown Parser for headings, tables, bold, and code
    let html = md
      .replace(/^### (.*$)/gim, '<h3>$1</h3>')
      .replace(/^## (.*$)/gim, '<h2>$1</h2>')
      .replace(/^# (.*$)/gim, '<h1>$1</h1>')
      .replace(/\*\*(.*)\*\*/gim, '<strong>$1</strong>')
      .replace(/`([^`]+)`/gim, '<code>$1</code>');

    // Convert markdown tables
    const tableRegex = /\|(.+)\|/g;
    html = html.replace(/(?:\|.*\|\r?\n)+/g, (match) => {
      const rows = match.trim().split('\n');
      let tableHtml = '<table class="data-table"><thead><tr>';
      const headers = rows[0].split('|').filter(c => c.trim().length > 0);
      headers.forEach(h => { tableHtml += `<th>${h.trim()}</th>`; });
      tableHtml += '</tr></thead><tbody>';

      for (let r = 2; r < rows.length; r++) {
        const cols = rows[r].split('|').filter(c => c.trim().length > 0);
        if (cols.length > 0) {
          tableHtml += '<tr>';
          cols.forEach(c => { tableHtml += `<td>${c.trim()}</td>`; });
          tableHtml += '</tr>';
        }
      }
      tableHtml += '</tbody></table>';
      return tableHtml;
    });

    els.reportMdRender.innerHTML = html;
  }

  function renderCsvTable(results) {
    let tableHtml = '<table class="data-table"><thead><tr><th>Test Name</th><th>Status</th><th>Time (s)</th><th>Data Mismatches</th><th>Assertion Fails</th><th>Details</th></tr></thead><tbody>';
    results.forEach(t => {
      tableHtml += `<tr>
        <td class="font-mono">${t.test_name}</td>
        <td><span class="badge ${t.passed ? 'badge-success' : 'badge-danger'}">${t.status}</span></td>
        <td>${t.duration_sec.toFixed(4)}</td>
        <td>${t.data_mismatches}</td>
        <td>${t.assertion_failures}</td>
        <td>${t.details}</td>
      </tr>`;
    });
    tableHtml += '</tbody></table>';
    els.reportCsvRender.innerHTML = tableHtml;
  }

  // Report sub-tabs
  els.reportTabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      els.reportTabBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');

      const view = btn.dataset.reportView;
      els.reportMdRender.classList.toggle('hidden', view !== 'md');
      els.reportCsvRender.classList.toggle('hidden', view !== 'csv');
      els.reportJsonRender.classList.toggle('hidden', view !== 'json');
    });
  });

  els.btnDownloadJson.addEventListener('click', () => window.open('/api/reports/file?type=json'));
  els.btnDownloadCsv.addEventListener('click', () => window.open('/api/reports/file?type=csv'));
  els.btnDownloadMd.addEventListener('click', () => window.open('/api/reports/file?type=md'));

  // --------------------------------------------------------------------------
  // Defect Injection Lab
  // --------------------------------------------------------------------------
  const DEFECT_DESCRIPTIONS = {
    BUG_INJECT_OVERFLOW: "Disables overflow write protection. The FIFO accepts writes when full without reading, overwriting unread stored data and masking the overflow pulse flag.",
    BUG_INJECT_UNDERFLOW_FLAG: "Suppresses underflow error flag generation. The FIFO fails to assert the underflow flag during illegal reads on an empty FIFO.",
    BUG_INJECT_COUNT_SIMULTANEOUS: "Erroneously increments count on simultaneous read/write when full, violating the count <= DEPTH invariant.",
    BUG_INJECT_ALMOST_FULL: "Inverts condition for almost_full watermark calculation, asserting premature or inverted watermark status.",
    BUG_INJECT_RESET_NEGLECT: "Fails to clear error flags during reset, leaving sticky error state asserted.",
  };

  els.selectDefectMacro.addEventListener('change', () => {
    const val = els.selectDefectMacro.value;
    els.defectDescBox.textContent = DEFECT_DESCRIPTIONS[val] || "Custom defect configuration.";
  });

  els.btnRunDefectDemo.addEventListener('click', () => {
    const defect = els.selectDefectMacro.value;
    els.defectTerminalBody.innerHTML = '';
    appendTerminalLine(`[LAB] Launching 3-stage validation lab for defect '${defect}'...`);

    fetch('/api/defect-demo/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ bug_macro: defect }),
    })
      .then(res => res.json())
      .then(data => {
        if (data.error) showToast(data.error, 'error');
        else showToast(`Defect Lab started: ${defect}`, 'info');
      });
  });

  // --------------------------------------------------------------------------
  // Workspace Cleaner & Diagnostics Refresh
  // --------------------------------------------------------------------------
  function cleanWorkspace() {
    if (!confirm("Clean all compiled binaries, logs, waveforms, and reports?")) return;
    fetch('/api/workspace/clean', { method: 'POST' })
      .then(res => res.json())
      .then(data => {
        showToast(data.message || 'Workspace cleaned.', 'info');
        loadSystemStatus();
        loadTests();
      });
  }

  els.btnCleanWorkspace?.addEventListener('click', cleanWorkspace);
  els.btnCleanSystem?.addEventListener('click', cleanWorkspace);
  els.btnRefreshSystem?.addEventListener('click', () => {
    loadSystemStatus();
    showToast("System diagnostics refreshed.", "info");
  });

  // --------------------------------------------------------------------------
  // Initial Bootstrapping
  // --------------------------------------------------------------------------
  loadSystemStatus();
  loadTests();
  loadReportViews();
  initSSE();
});
