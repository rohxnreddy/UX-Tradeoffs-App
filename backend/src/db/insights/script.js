document.addEventListener('DOMContentLoaded', () => {
    // Cache selectors
    const refreshBtn = document.getElementById('refresh-btn');
    const metricUsers = document.getElementById('metric-users');
    const metricSessions = document.getElementById('metric-sessions');
    const metricTests = document.getElementById('metric-tests');

    // Averages elements
    const avgVmaf = document.getElementById('avg-vmaf');
    const avgPesq = document.getElementById('avg-pesq');
    const avgPeaq = document.getElementById('avg-peaq');
    const avgIqa = document.getElementById('avg-iqa');

    // Counts elements
    const countVmaf = document.getElementById('count-vmaf');
    const countPeaq = document.getElementById('count-peaq');
    const countPesq = document.getElementById('count-pesq');
    const countIqa = document.getElementById('count-iqa');

    // Chart layouts template for glass dark theme
    const chartLayoutTemplate = {
        paper_bgcolor: 'rgba(0,0,0,0)',
        plot_bgcolor: 'rgba(0,0,0,0)',
        font: {
            family: 'Inter, sans-serif',
            color: '#f3f4f6'
        },
        margin: { t: 30, r: 15, b: 30, l: 45 },
        showlegend: false,
        xaxis: {
            gridcolor: 'rgba(255,255,255,0.05)',
            zerolinecolor: 'rgba(255,255,255,0.1)',
            tickfont: { size: 9 }
        },
        yaxis: {
            gridcolor: 'rgba(255,255,255,0.05)',
            zerolinecolor: 'rgba(255,255,255,0.1)',
            tickfont: { size: 9 }
        }
    };

    // Color definitions matching the CSS vars
    const colors = {
        blue: '#3b82f6',
        purple: '#8b5cf6',
        pink: '#ec4899',
        emerald: '#10b981',
        amber: '#f59e0b',
        blueGlow: 'rgba(59, 130, 246, 0.4)'
    };

    // Main fetch function
    async function fetchInsights() {
        try {
            const icon = refreshBtn.querySelector('i');
            if (icon) icon.classList.add('bx-spin');

            const response = await fetch('/api/insights');
            if (!response.ok) throw new Error('Network response was not ok');
            const data = await response.json();

            // Update UI elements
            updateMetrics(data.metrics, data.averages);
            renderCharts(data);

            if (icon) {
                setTimeout(() => icon.classList.remove('bx-spin'), 600);
            }
        } catch (error) {
            console.error('Error fetching insights:', error);
        }
    }

    // Update Top Metric Cards & Averages
    function updateMetrics(metrics, averages) {
        // High level metrics
        metricUsers.textContent = metrics.total_users ?? 0;
        metricSessions.textContent = metrics.total_sessions ?? 0;
        metricTests.textContent = metrics.total_tests ?? 0;

        // Breakdown counts
        countVmaf.textContent = metrics.test_counts.vmaf ?? 0;
        countPeaq.textContent = metrics.test_counts.peaq ?? 0;
        countPesq.textContent = metrics.test_counts.pesq ?? 0;
        countIqa.textContent = metrics.test_counts.iqa ?? 0;

        // Averages cards
        avgVmaf.textContent = averages.vmaf !== null ? averages.vmaf.toFixed(1) + '%' : 'N/A';
        avgPesq.textContent = (averages.pesq && averages.pesq.direct_pesq !== null) ? averages.pesq.direct_pesq.toFixed(2) : 'N/A';
        avgPeaq.textContent = (averages.peaq && averages.peaq.odg_score !== null) ? averages.peaq.odg_score.toFixed(2) : 'N/A';
        avgIqa.textContent = (averages.iqa && averages.iqa.camera_score !== null) ? averages.iqa.camera_score.toFixed(1) + '/100' : 'N/A';
    }

    // Master Chart Renderer
    function renderCharts(data) {
        renderTestPie(data.metrics.test_counts);
        
        // 1. VMAF Histogram
        renderHistogram(
            'chart-vmaf-dist',
            data.vmaf_all_scores,
            colors.emerald,
            'VMAF Score (%)'
        );

        // 2. PESQ Histogram
        renderHistogram(
            'chart-pesq-dist',
            data.pesq_all_scores,
            colors.blue,
            'PESQ Score (MOS)'
        );

        // 3. PEAQ Histogram
        renderHistogram(
            'chart-peaq-dist',
            data.peaq_all_scores,
            colors.amber,
            'PEAQ Score (ODG)'
        );

        // 4. IQA Histogram
        renderHistogram(
            'chart-iqa-dist',
            data.iqa_all_scores,
            colors.pink,
            'IQA Score (Camera)'
        );
    }

    // Render numerical histogram for scores
    function renderHistogram(divId, scores, color, xTitle) {
        if (!scores || scores.length === 0) {
            document.getElementById(divId).innerHTML = `
                <div style="display: flex; align-items: center; justify-content: center; height: 100%; min-height: 250px; color: var(--text-secondary);">
                    <span>No test logs recorded</span>
                </div>`;
            return;
        }

        const trace = {
            x: scores,
            type: 'histogram',
            marker: {
                color: color,
                opacity: 0.75,
                line: { color: color, width: 1.5 }
            },
            hoverinfo: 'x+y'
        };

        const layout = {
            ...chartLayoutTemplate,
            margin: { t: 20, r: 15, b: 35, l: 45 },
            xaxis: {
                ...chartLayoutTemplate.xaxis,
                title: { text: xTitle, font: { size: 9 } }
            },
            yaxis: { 
                ...chartLayoutTemplate.yaxis, 
                title: { text: 'Number of Tests', font: { size: 9 } },
                tickformat: ',d'
            }
        };

        Plotly.newPlot(divId, [trace], layout, { responsive: true, displayModeBar: false });
    }

    // Assessment Types Share Donut Chart
    function renderTestPie(counts) {
        const values = [counts.vmaf, counts.peaq, counts.pesq, counts.iqa];
        const labels = ['VMAF (Video)', 'PEAQ (Audio)', 'PESQ (Audio)', 'IQA (Image)'];

        if (values.every(v => v === 0)) {
            document.getElementById('chart-test-pie').innerHTML = `
                <div style="display: flex; align-items: center; justify-content: center; height: 100%; min-height: 250px; color: var(--text-secondary);">
                    <span>No data available</span>
                </div>`;
            return;
        }

        const trace = {
            values: values,
            labels: labels,
            type: 'pie',
            hole: 0.55,
            marker: {
                colors: [colors.emerald, colors.amber, colors.blue, colors.pink]
            },
            textinfo: 'percent',
            hoverinfo: 'label+value',
            insidetextorientation: 'radial'
        };

        const layout = {
            ...chartLayoutTemplate,
            margin: { t: 15, r: 15, b: 15, l: 15 },
            showlegend: true,
            legend: {
                orientation: 'h',
                x: 0,
                y: -0.1,
                font: { size: 10 }
            }
        };

        Plotly.newPlot('chart-test-pie', [trace], layout, { responsive: true, displayModeBar: false });
    }

    // Refresh btn handler
    refreshBtn.addEventListener('click', fetchInsights);

    // Initial load
    fetchInsights();
});
