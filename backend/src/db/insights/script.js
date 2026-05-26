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

            const apiPath = window.location.pathname.replace(/\/insights\/dashboard\.html$/, '/api/insights');
            const response = await fetch(apiPath);
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
        
        // Render device and demographic charts
        renderDeviceBrands(data.distributions.device_brands);
        renderAndroidVersions(data.distributions.android_versions);
        renderPhoneAges(data.distributions.phone_ages);
        renderLocationGlobe(data.distributions.location_coordinates);

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

    // Render horizontal bar chart for Device Brands
    function renderDeviceBrands(brandsData) {
        const divId = 'chart-brands';
        if (!brandsData || brandsData.length === 0) {
            document.getElementById(divId).innerHTML = `
                <div style="display: flex; align-items: center; justify-content: center; height: 100%; min-height: 250px; color: var(--text-secondary);">
                    <span>No brand data available</span>
                </div>`;
            return;
        }
        
        const brands = brandsData.map(d => d.brand).reverse();
        const counts = brandsData.map(d => d.count).reverse();
        
        const trace = {
            x: counts,
            y: brands,
            type: 'bar',
            orientation: 'h',
            marker: {
                color: colors.blue,
                opacity: 0.85,
                line: { 
                    color: colors.blue,
                    width: 1 
                }
            },
            hoverinfo: 'x'
        };
        
        const layout = {
            ...chartLayoutTemplate,
            margin: { t: 15, r: 15, b: 35, l: 80 },
            xaxis: {
                ...chartLayoutTemplate.xaxis,
                title: { text: 'Sessions Count', font: { size: 9 } },
                tickformat: ',d'
            },
            yaxis: {
                ...chartLayoutTemplate.yaxis,
                tickfont: { size: 10 }
            }
        };
        
        Plotly.newPlot(divId, [trace], layout, { responsive: true, displayModeBar: false });
    }

    // Render vertical bar chart for Android Versions
    function renderAndroidVersions(androidData) {
        const divId = 'chart-android';
        if (!androidData || androidData.length === 0) {
            document.getElementById(divId).innerHTML = `
                <div style="display: flex; align-items: center; justify-content: center; height: 100%; min-height: 250px; color: var(--text-secondary);">
                    <span>No Android version data available</span>
                </div>`;
            return;
        }
        
        const versions = androidData.map(d => 'Android ' + d.version);
        const counts = androidData.map(d => d.count);
        
        const trace = {
            x: versions,
            y: counts,
            type: 'bar',
            marker: {
                color: colors.purple,
                opacity: 0.8,
                line: { color: colors.purple, width: 1 }
            },
            hoverinfo: 'y'
        };
        
        const layout = {
            ...chartLayoutTemplate,
            margin: { t: 15, r: 15, b: 35, l: 45 },
            xaxis: {
                ...chartLayoutTemplate.xaxis,
                tickfont: { size: 9 }
            },
            yaxis: {
                ...chartLayoutTemplate.yaxis,
                title: { text: 'Sessions Count', font: { size: 9 } },
                tickformat: ',d'
            }
        };
        
        Plotly.newPlot(divId, [trace], layout, { responsive: true, displayModeBar: false });
    }

    // Render donut chart for Age of Phone
    function renderPhoneAges(agesData) {
        const divId = 'chart-phone-age';
        if (!agesData || agesData.length === 0) {
            document.getElementById(divId).innerHTML = `
                <div style="display: flex; align-items: center; justify-content: center; height: 100%; min-height: 250px; color: var(--text-secondary);">
                    <span>No survey data available</span>
                </div>`;
            return;
        }
        
        const labels = agesData.map(d => d.age);
        const values = agesData.map(d => d.count);
        
        const trace = {
            values: values,
            labels: labels,
            type: 'pie',
            hole: 0.55,
            marker: {
                colors: [colors.amber, colors.emerald, colors.blue, colors.pink, colors.purple]
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
                font: { size: 9 }
            }
        };
        
        Plotly.newPlot(divId, [trace], layout, { responsive: true, displayModeBar: false });
    }

    // Render 3D Globe & Top Localities list
    function renderLocationGlobe(coordsData) {
        const divId = 'chart-location';
        if (!coordsData || coordsData.length === 0) {
            document.getElementById(divId).innerHTML = `
                <div style="display: flex; align-items: center; justify-content: center; height: 100%; min-height: 250px; color: var(--text-secondary);">
                    <span>No location data available</span>
                </div>`;
            return;
        }

        // Group/aggregate location data by city and country
        const groupedMap = {};
        coordsData.forEach(d => {
            const city = d.city || 'Unknown';
            const country = d.country || 'Unknown';
            const key = `${city}, ${country}`;
            if (!groupedMap[key]) {
                groupedMap[key] = {
                    city: city,
                    country: country,
                    lat: d.lat || 0,
                    lon: d.lon || 0,
                    count: 0,
                    maxSubCount: -1
                };
            }
            groupedMap[key].count += d.count;
            if (d.count > groupedMap[key].maxSubCount) {
                groupedMap[key].maxSubCount = d.count;
                groupedMap[key].lat = d.lat || 0;
                groupedMap[key].lon = d.lon || 0;
            }
        });

        const mergedLocalities = Object.values(groupedMap);

        // Render Globe
        const lats = mergedLocalities.map(d => d.lat);
        const lons = mergedLocalities.map(d => d.lon);
        const hoverText = mergedLocalities.map(d => `${d.city}, ${d.country}<br>Sessions: ${d.count}`);
        const sizes = mergedLocalities.map(d => Math.max(10, Math.min(35, 8 + Math.log2(d.count) * 4)));

        const trace = {
            type: 'scattergeo',
            mode: 'markers',
            lat: lats,
            lon: lons,
            hoverinfo: 'text',
            text: hoverText,
            marker: {
                size: sizes,
                color: colors.pink,
                opacity: 0.8,
                line: {
                    color: 'rgba(255, 255, 255, 0.6)',
                    width: 1
                }
            }
        };

        // Find center coordinates based on maximum frequency area
        let centerLon = 0;
        let centerLat = 0;
        if (mergedLocalities.length > 0) {
            let maxLoc = null;
            // Try to find a valid non-Unknown city
            mergedLocalities.forEach(loc => {
                if (loc.city !== 'Unknown' && loc.lat !== 0 && loc.lon !== 0) {
                    if (!maxLoc || loc.count > maxLoc.count) {
                        maxLoc = loc;
                    }
                }
            });
            // Fallback
            if (!maxLoc) {
                maxLoc = mergedLocalities[0];
                mergedLocalities.forEach(loc => {
                    if (!maxLoc || loc.count > maxLoc.count) {
                        maxLoc = loc;
                    }
                });
            }
            if (maxLoc) {
                centerLon = maxLoc.lon;
                centerLat = maxLoc.lat;
            }
        }

        const layout = {
            ...chartLayoutTemplate,
            margin: { t: 0, r: 0, b: 0, l: 0 },
            geo: {
                projection: {
                    type: 'orthographic',
                    rotation: {
                        lon: centerLon,
                        lat: centerLat,
                        roll: 0
                    }
                },
                showland: true,
                landcolor: 'rgba(255, 255, 255, 0.08)',
                showocean: true,
                oceancolor: 'rgba(9, 13, 22, 0.6)',
                showlakes: false,
                showrivers: false,
                showcountries: true,
                countrycolor: 'rgba(255, 255, 255, 0.15)',
                bgcolor: 'rgba(0,0,0,0)',
                lonaxis: {
                    showgrid: true,
                    gridcolor: 'rgba(255, 255, 255, 0.05)'
                },
                lataxis: {
                    showgrid: true,
                    gridcolor: 'rgba(255, 255, 255, 0.05)'
                }
            }
        };

        Plotly.newPlot(divId, [trace], layout, { responsive: true, displayModeBar: false });

        // Populate Sorted Localities list on the right
        const sortedLocalities = [...mergedLocalities].sort((a, b) => b.count - a.count);
        const listEl = document.getElementById('location-list');
        if (listEl) {
            listEl.innerHTML = sortedLocalities.map(d => `
                <div class="location-list-item">
                    <span class="location-item-name">${d.city}, ${d.country}</span>
                    <span class="location-item-value">${d.count}</span>
                </div>
            `).join('');
        }
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
