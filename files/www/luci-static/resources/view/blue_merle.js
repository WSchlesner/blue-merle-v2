'use strict';
'require view';
'require fs';

var cmd = '/usr/libexec/blue-merle';
var countdownTimer = null;

function luhnValid(s) {
    if (!/^\d{15}$/.test(s)) return false;
    var sum = 0;
    for (var i = 0; i < 15; i++) {
        var d = parseInt(s[i], 10);
        if (i % 2 === 1) { d *= 2; if (d > 9) d -= 9; }
        sum += d;
    }
    return sum % 10 === 0;
}

function exec(sub) {
    return fs.exec(cmd, [sub]).then(function(r) {
        if (r.code !== 0)
            throw new Error(sub + ' failed: ' + (r.stderr || '').trim());
        return r.stdout || '';
    });
}

return view.extend({
    load: function() {
        return Promise.all([
            exec('status').then(function(out) {
                try { return JSON.parse(out); }
                catch(e) { return {}; }
            }).catch(function() { return {}; }),
            exec('log').catch(function() { return ''; })
        ]);
    },

    render: function(data) {
        if (countdownTimer) { clearInterval(countdownTimer); countdownTimer = null; }

        var st  = data[0] || {};
        var log = (data[1] || '').trim();

        // ── Helpers ──────────────────────────────────────────────────────────

        var noticeEl = E('div', { 'id': 'bm-notice', 'style': 'display:none;margin-bottom:1em' });

        function showNotice(msg, isError) {
            noticeEl.className = isError ? 'alert-message error' : 'alert-message warning';
            noticeEl.textContent = msg;
            noticeEl.style.display = '';
        }

        function startCountdown(prefix, seconds) {
            if (countdownTimer) clearInterval(countdownTimer);
            noticeEl.className = 'alert-message warning';
            noticeEl.style.display = '';
            var remaining = seconds;
            var tick = function() {
                noticeEl.textContent = prefix + ' Reloading in ' + remaining + 's…';
            };
            tick();
            countdownTimer = setInterval(function() {
                remaining--;
                if (remaining <= 0) {
                    clearInterval(countdownTimer);
                    countdownTimer = null;
                    window.location.reload();
                } else { tick(); }
            }, 1000);
        }

        function handleRotateImeis() {
            startCountdown('Rotation started — allow 30–90 s for modem RF cycle.', 90);
            exec('rotate').catch(function(e) {
                if (countdownTimer) { clearInterval(countdownTimer); countdownTimer = null; }
                showNotice('Error: ' + e.message, true);
            });
        }

        function handleRotateWireless() {
            startCountdown('Wireless rotation started — applying new MACs/SSIDs…', 20);
            exec('rotate_wireless').catch(function(e) {
                if (countdownTimer) { clearInterval(countdownTimer); countdownTimer = null; }
                showNotice('Error: ' + e.message, true);
            });
        }

        function handleRestore() {
            if (!window.confirm('Restore all factory values?\nThis will reveal your real device identity.'))
                return;
            startCountdown('Restore started.', 90);
            exec('restore').catch(function(e) {
                if (countdownTimer) { clearInterval(countdownTimer); countdownTimer = null; }
                showNotice('Error: ' + e.message, true);
            });
        }

        // ── Table helpers ─────────────────────────────────────────────────────

        function tableHead() {
            return E('thead', {}, [ E('tr', {}, [
                E('th', { 'style': 'width:220px;padding:6px 8px;text-align:left' }, []),
                E('th', { 'style': 'padding:6px 8px;text-align:left;font-weight:600;border-bottom:2px solid var(--border-color-high)' }, [ 'Current' ]),
                E('th', { 'style': 'padding:6px 8px;text-align:left;font-weight:600;color:var(--text-color-medium);border-bottom:2px solid var(--border-color-high)' }, [ 'Factory' ])
            ])]);
        }

        // cur can be a string or a pre-built Element (for async fields like IMSI)
        function row(label, cur, fac) {
            var curStr = typeof cur === 'string' ? cur : null;
            var isRotated = curStr && fac && fac !== '—' && curStr !== fac;
            return E('tr', {}, [
                E('td', { 'style': 'width:220px;padding:6px 8px;font-weight:bold' }, [ label ]),
                E('td', { 'style': 'padding:6px 8px;font-family:monospace' +
                    (isRotated ? ';color:#1a7f3c;font-weight:bold' : '') },
                    curStr !== null ? [ curStr || '—' ] : [ cur ]),
                E('td', { 'style': 'padding:6px 8px;font-family:monospace;color:#888' },
                    [ fac && fac !== '—' ? fac : '' ])
            ]);
        }

        function passwordRow(label, cur, fac) {
            var isRotated = fac && fac !== '—' && cur && cur !== fac;
            var hasCur = cur && cur !== '—';
            var hasFac = fac && fac !== '—';
            var curMasked = hasCur ? '•'.repeat(cur.length) : '—';
            var curShowing = false;
            var curEl = E('span', { 'style': 'font-family:monospace' +
                (isRotated ? ';color:#1a7f3c;font-weight:bold' : '') }, [ curMasked ]);
            var curBtn = hasCur ? E('button', {
                'class': 'btn', 'style': 'margin-left:8px;padding:1px 8px;font-size:.8em',
                'click': function() {
                    curShowing = !curShowing;
                    curEl.textContent = curShowing ? cur : curMasked;
                    curBtn.textContent = curShowing ? 'Hide' : 'Show';
                }
            }, [ 'Show' ]) : null;
            var facMasked = hasFac ? '•'.repeat(fac.length) : '';
            var facShowing = false;
            var facEl = hasFac ? E('span', { 'style': 'font-family:monospace;color:#888' }, [ facMasked ]) : null;
            var facBtn = hasFac ? E('button', {
                'class': 'btn', 'style': 'margin-left:8px;padding:1px 8px;font-size:.8em',
                'click': function() {
                    facShowing = !facShowing;
                    facEl.textContent = facShowing ? fac : facMasked;
                    facBtn.textContent = facShowing ? 'Hide' : 'Show';
                }
            }, [ 'Show' ]) : null;
            return E('tr', {}, [
                E('td', { 'style': 'width:220px;padding:6px 8px;font-weight:bold' }, [ label ]),
                E('td', { 'style': 'padding:6px 8px' }, curBtn ? [ curEl, curBtn ] : [ curEl ]),
                E('td', { 'style': 'padding:6px 8px' }, facEl ? (facBtn ? [ facEl, facBtn ] : [ facEl ]) : [ '' ])
            ]);
        }

        // ── Options helpers ───────────────────────────────────────────────────

        var wirelessSavedEl = E('span', { 'style': 'font-size:.82em;color:#1a7f3c;font-weight:normal' }, []);
        var imeiSavedEl     = E('span', { 'style': 'font-size:.82em;color:#1a7f3c;font-weight:normal' }, []);
        var touchSavedEl    = E('span', { 'style': 'font-size:.82em;color:#1a7f3c;font-weight:normal' }, []);
        function flashSaved(el) {
            el.textContent = 'Saved ✓';
            setTimeout(function() { el.textContent = ''; }, 1500);
        }

        function checkbox(label, key, checked, savedEl) {
            var _saved = savedEl || wirelessSavedEl;
            var cb = E('input', {
                'type': 'checkbox', 'style': 'margin-right:6px',
                'change': function() {
                    fs.exec(cmd, [ 'set:' + key + '=' + (cb.checked ? '1' : '0') ])
                        .then(function() { flashSaved(_saved); })
                        .catch(function(e) { console.error('set option failed:', e.message); });
                }
            });
            cb.checked = !!checked;
            return E('label', { 'style': 'display:inline-flex;align-items:center;margin-right:20px;cursor:pointer' },
                [ cb, label ]);
        }

        function radio(label, name, value, isChecked, uciKey) {
            var rb = E('input', {
                'type': 'radio', 'name': name, 'value': value, 'style': 'margin-right:4px',
                'change': function() {
                    if (rb.checked) {
                        st[uciKey] = value;
                        fs.exec(cmd, [ 'set:' + uciKey + '=' + value ])
                            .then(function() { flashSaved(imeiSavedEl); })
                            .catch(function(e) { console.error('set option failed:', e.message); });
                    }
                }
            });
            rb.checked = !!isChecked;
            return E('label', { 'style': 'display:inline-flex;align-items:center;margin-right:14px;cursor:pointer' },
                [ rb, label ]);
        }

        // ── Section wrapper ───────────────────────────────────────────────────

        function section(title, children) {
            return E('fieldset', { 'class': 'cbi-section', 'style': 'margin-bottom:1.5em' },
                [ E('legend', { 'style': 'border-bottom:1px solid #ccc;width:100%;padding-bottom:5px;margin-bottom:8px' }, [ title ]) ].concat(children));
        }

        // ── IMSI async placeholders ───────────────────────────────────────────

        var imsi1El = E('span', { 'id': 'bm-imsi1', 'style': 'color:#aaa' }, [ 'Loading…' ]);
        var imsi2El = E('span', { 'id': 'bm-imsi2', 'style': 'color:#aaa' }, [ 'Loading…' ]);

        // ── Build page ────────────────────────────────────────────────────────

        var mode1 = st.imei_mode_slot1 || 'random';
        var mode2 = st.imei_mode_slot2 || 'random';

        // ── Static IMEI inputs ────────────────────────────────────────────────

        function makeImeiInput(slotLabel, key, savedVal, liveImei) {
            var errEl = E('span', { 'style': 'color:#c00;font-size:.85em;margin-left:8px;display:none' });
            var inp = E('input', {
                'type': 'text',
                'placeholder': '15-digit IMEI',
                'value': savedVal || '',
                'maxlength': '15',
                'style': 'font-family:monospace;width:160px;padding:3px 5px;border:1px solid #ccc;border-radius:3px'
            });

            function validate() {
                var v = inp.value.trim();
                if (v === '') {
                    inp.style.borderColor = '#ccc';
                    errEl.style.display = 'none';
                    return true;
                }
                if (!/^\d{15}$/.test(v)) {
                    inp.style.borderColor = '#c00';
                    errEl.textContent = 'Must be exactly 15 digits';
                    errEl.style.display = '';
                    return false;
                }
                if (!luhnValid(v)) {
                    inp.style.borderColor = '#c00';
                    errEl.textContent = 'Invalid — Luhn checksum failed';
                    errEl.style.display = '';
                    return false;
                }
                inp.style.borderColor = '#1a7f3c';
                errEl.style.display = 'none';
                return true;
            }

            inp.addEventListener('input', validate);
            inp.addEventListener('blur', function() {
                if (!validate()) return;
                var v = inp.value.trim();
                if (v) fs.exec(cmd, ['set:' + key + '=' + v])
                    .catch(function(e) { console.error('save static IMEI failed:', e.message); });
            });

            var useBtn = E('button', {
                'class': 'btn',
                'style': 'margin-left:8px;padding:2px 8px;font-size:.8em',
                'title': 'Copy current live IMEI into this field',
                'click': function() {
                    inp.value = liveImei || '';
                    inp.dispatchEvent(new Event('input'));
                    inp.dispatchEvent(new Event('blur'));
                }
            }, [ 'Use current' ]);

            return E('div', { 'style': 'display:flex;align-items:center;margin-bottom:6px' }, [
                E('span', { 'style': 'width:120px;font-weight:bold' }, [ slotLabel ]),
                inp,
                useBtn,
                errEl
            ]);
        }

        var staticSlot1El = E('div', { 'style': 'display:' + (mode1 === 'static' ? '' : 'none') }, [
            makeImeiInput('SIM Slot 1',      'static_imei_slot1', st.static_imei_slot1, st.imei1)
        ]);
        var staticSlot2El = E('div', { 'style': 'display:' + (mode2 === 'static' ? '' : 'none') }, [
            makeImeiInput('SIM Slot 2/eSIM', 'static_imei_slot2', st.static_imei_slot2, st.imei2)
        ]);
        var staticImeiSection = E('div', {
            'style': 'margin-top:4px;padding:10px 12px;background:#f8f8f8;border:1px solid #ddd;' +
                     'border-radius:4px;display:' + ((mode1 === 'static' || mode2 === 'static') ? '' : 'none')
        }, [ staticSlot1El, staticSlot2El ]);

        function modeDesc(m) {
            if (m === 'deterministic') return 'IMEI is derived from the SIM IMSI and stays consistent across rotations.';
            if (m === 'static')        return 'The exact IMEI entered below is written on every rotation. You are responsible for entering a valid, Luhn-correct IMEI.';
            return 'A new random IMEI is generated on each rotation.';
        }
        var modeDesc1El = E('div', { 'style': 'color:#888;font-size:.85em;margin-bottom:4px' }, [ modeDesc(mode1) ]);
        var modeDesc2El = E('div', { 'style': 'color:#888;font-size:.85em;margin-bottom:10px' }, [ modeDesc(mode2) ]);

        var page = E('div', { 'class': 'cbi-map' }, [
            E('h2', {}, [ 'Blue Merle — Identity Randomization' ]),
            noticeEl,

            !st.installed ? E('div', { 'class': 'alert-message error', 'style': 'margin-bottom:1em' }, [
                'Factory state not captured — run ',
                E('code', {}, [ 'blue-merle install' ]),
                ' over SSH before using this page.'
            ]) : E('span'),

            // ── IMEI ──────────────────────────────────────────────────────────
            section('IMEI', [
                E('table', { 'style': 'width:100%;border-collapse:collapse' }, [
                    E('thead', {}, [ E('tr', {}, [
                        E('th', { 'style': 'width:60px;padding:4px 8px;text-align:left' }, []),
                        E('th', { 'style': 'padding:4px 8px;text-align:left;font-weight:600;border-bottom:2px solid var(--border-color-high)' }, [ 'Current' ]),
                        E('th', { 'style': 'padding:4px 8px;text-align:left;font-weight:600;color:var(--text-color-medium);border-bottom:2px solid var(--border-color-high)' }, [ 'Factory' ])
                    ])]),
                    E('tbody', {}, [
                        E('tr', {}, [ E('td', { 'colspan': '3', 'style': 'padding:6px 8px 2px;font-size:.82em;font-weight:700;color:var(--text-color-high)' }, [ 'SIM Slot 1' ]) ]),
                        E('tr', {}, [
                            E('td', { 'style': 'padding:1px 8px;color:var(--text-color-medium);font-size:.82em' }, [ 'IMEI' ]),
                            E('td', { 'style': 'padding:1px 8px;font-family:monospace' + (st.imei1 && st.factory_i1 && st.factory_i1 !== '---' && st.imei1 !== st.factory_i1 ? ';color:#1a7f3c;font-weight:bold' : '') }, [ st.imei1 || '—' ]),
                            E('td', { 'style': 'padding:1px 8px;font-family:monospace;color:var(--text-color-medium)' }, [ st.factory_i1 && st.factory_i1 !== '---' ? st.factory_i1 : '' ])
                        ]),
                        E('tr', {}, [
                            E('td', { 'style': 'padding:1px 8px 8px;color:var(--text-color-medium);font-size:.82em' }, [ 'IMSI' ]),
                            E('td', { 'style': 'padding:1px 8px 8px;font-family:monospace', 'colspan': '2' }, [ imsi1El ])
                        ]),
                        E('tr', {}, [ E('td', { 'colspan': '3', 'style': 'padding:8px 8px 2px;font-size:.82em;font-weight:700;color:var(--text-color-high);border-top:1px solid var(--border-color-high)' }, [ 'SIM Slot 2 / eSIM' ]) ]),
                        E('tr', {}, [
                            E('td', { 'style': 'padding:1px 8px;color:var(--text-color-medium);font-size:.82em' }, [ 'IMEI' ]),
                            E('td', { 'style': 'padding:1px 8px;font-family:monospace' + (st.imei2 && st.factory_i2 && st.factory_i2 !== '---' && st.imei2 !== st.factory_i2 ? ';color:#1a7f3c;font-weight:bold' : '') }, [ st.imei2 || '—' ]),
                            E('td', { 'style': 'padding:1px 8px;font-family:monospace;color:var(--text-color-medium)' }, [ st.factory_i2 && st.factory_i2 !== '---' ? st.factory_i2 : '' ])
                        ]),
                        E('tr', {}, [
                            E('td', { 'style': 'padding:1px 8px 6px;color:var(--text-color-medium);font-size:.82em' }, [ 'IMSI' ]),
                            E('td', { 'style': 'padding:1px 8px 6px;font-family:monospace', 'colspan': '2' }, [ imsi2El ])
                        ])
                    ])
                ])
            ]),

            // ── Wireless/System Identity ───────────────────────────────────────
            section('Wireless/System Identity', [
                E('table', { 'style': 'width:100%;border-collapse:collapse' }, [
                    tableHead(),
                    E('tbody', {}, [
                        row('SSID', st.ssid, st.factory_ssid),
                        row('Guest SSID', st.guest_ssid, st.factory_guest_ssid),
                        row('2.4 GHz BSSID', st.mac_2g, st.factory_mac_2g),
                        row('5 GHz BSSID', st.mac_5g, st.factory_mac_5g),
                        row('6 GHz BSSID', st.mac_6g, st.factory_mac_6g),
                        row('Station MAC (Repeater)', st.mac_sta, st.factory_mac_sta),
                        row('2.4 GHz Guest BSSID', st.mac_guest2g, st.factory_mac_guest2g),
                        row('5 GHz Guest BSSID', st.mac_guest5g, st.factory_mac_guest5g),
                        row('6 GHz Guest BSSID', st.mac_guest6g, st.factory_mac_guest6g),
                        row('Hostname', st.hostname, st.factory_host),
                        passwordRow('Main WiFi Password', st.wifi2g_key, st.factory_wifi2g_key),
                        passwordRow('Guest WiFi Password', st.guest2g_key, st.factory_guest2g_key)
                    ])
                ])
            ]),

            // ── Rotation Options ──────────────────────────────────────────────
            section('Rotation Options', [
                E('div', { 'style': 'font-size:.85em;font-weight:600;color:var(--text-color-high);border-bottom:1px solid var(--border-color-high);padding-bottom:3px;margin-bottom:8px;display:flex;align-items:center;justify-content:space-between' }, [ 'Wireless / System Rotation', wirelessSavedEl ]),
                E('div', { 'style': 'margin-bottom:4px' }, [
                    checkbox('Randomize identity on boot', 'randomize_on_boot', st.opt_boot !== '0')
                ]),
                E('div', { 'style': 'color:var(--text-color-medium);font-size:.82em;margin-bottom:8px;padding-left:1.5em' }, [
                    'Note: when unchecked, the options below will not rotate at boot.'
                ]),
                E('div', { 'style': 'margin-bottom:12px;padding-left:1.25em;display:flex;flex-direction:column;gap:2px' }, [
                    checkbox('Rotate BSSIDs / MACs',    'randomize_mac',      st.opt_mac      !== '0'),
                    checkbox('Rotate SSID & Guest SSID', 'randomize_ssid',    st.opt_ssid     !== '0'),
                    checkbox('Rotate WiFi Password',     'randomize_password', st.opt_password !== '0'),
                    checkbox('Rotate Hostname',          'randomize_hostname', st.opt_hostname !== '0')
                ]),
                E('div', { 'style': 'font-size:.85em;font-weight:600;color:var(--text-color-high);border-bottom:1px solid var(--border-color-high);padding-bottom:3px;margin-bottom:8px;margin-top:12px;display:flex;align-items:center;justify-content:space-between' }, [ 'IMEI Rotation', imeiSavedEl ]),
                E('div', { 'style': 'font-size:.82em;font-weight:600;color:var(--text-color-medium);margin-bottom:4px' }, [ 'SIM Slot 1' ]),
                E('div', { 'style': 'display:flex;align-items:center;flex-wrap:wrap;gap:4px;margin-bottom:4px' }, [
                    radio('Random',                     'imei_mode_slot1', 'random',        mode1 === 'random',        'imei_mode_slot1'),
                    radio('Deterministic (IMSI-keyed)', 'imei_mode_slot1', 'deterministic', mode1 === 'deterministic', 'imei_mode_slot1'),
                    radio('Static (manual)',             'imei_mode_slot1', 'static',        mode1 === 'static',        'imei_mode_slot1')
                ]),
                modeDesc1El,
                E('div', { 'style': 'font-size:.82em;font-weight:600;color:var(--text-color-medium);margin-bottom:4px;margin-top:8px' }, [ 'SIM Slot 2 / eSIM' ]),
                E('div', { 'style': 'display:flex;align-items:center;flex-wrap:wrap;gap:4px;margin-bottom:4px' }, [
                    radio('Random',                     'imei_mode_slot2', 'random',        mode2 === 'random',        'imei_mode_slot2'),
                    radio('Deterministic (IMSI-keyed)', 'imei_mode_slot2', 'deterministic', mode2 === 'deterministic', 'imei_mode_slot2'),
                    radio('Static (manual)',             'imei_mode_slot2', 'static',        mode2 === 'static',        'imei_mode_slot2')
                ]),
                modeDesc2El,
                staticImeiSection,
                E('div', { 'style': 'font-size:.85em;font-weight:600;color:var(--text-color-high);border-bottom:1px solid var(--border-color-high);padding-bottom:3px;margin-bottom:8px;margin-top:12px;display:flex;align-items:center;justify-content:space-between' }, [ 'Touchscreen Trigger', touchSavedEl ]),
                E('div', { 'style': 'margin-bottom:4px' }, [
                    checkbox('Enable clock long-press to trigger SIM swap', 'touch_enabled', st.touch_enabled === '1', touchSavedEl)
                ]),
                E('div', { 'style': 'color:var(--text-color-medium);font-size:.82em;padding-left:1.5em' }, [
                    'Hold the clock (top-left of screen) for 2 seconds to initiate a SIM swap.'
                ])
            ]),

            // ── Actions ───────────────────────────────────────────────────────
            section('Actions', [
                E('dl', { 'style': 'margin:0 0 .75em;color:var(--text-color-medium);font-size:.9em;display:grid;grid-template-columns:auto 1fr;gap:2px 8px' }, [
                    E('dt', { 'style': 'font-weight:600;white-space:nowrap;color:var(--text-color-high)' }, [ 'Rotate IMEIs' ]),
                    E('dd', { 'style': 'margin:0' }, [ '— writes new IMEIs using the selected mode and cycles modem RF for re-registration.' ]),
                    E('dt', { 'style': 'font-weight:600;white-space:nowrap;color:var(--text-color-high)' }, [ 'Rotate Wireless/System' ]),
                    E('dd', { 'style': 'margin:0' }, [ '— immediately applies new MACs, SSIDs, hostname, and password per the checked options.' ]),
                    E('dt', { 'style': 'font-weight:600;white-space:nowrap;color:var(--text-color-high)' }, [ 'Restore Factory' ]),
                    E('dd', { 'style': 'margin:0' }, [ '— returns all identity values to factory state.' ])
                ]),
                E('div', {}, [
                    E('button', {
                        'class': 'btn cbi-button-apply', 'style': 'margin-right:8px',
                        'click': handleRotateImeis
                    }, [ 'Rotate IMEIs' ]),
                    E('button', {
                        'class': 'btn cbi-button-apply', 'style': 'margin-right:8px',
                        'click': handleRotateWireless
                    }, [ 'Rotate Wireless/System' ]),
                    E('button', {
                        'class': 'btn cbi-button-reset',
                        'click': handleRestore
                    }, [ 'Restore Factory' ])
                ]),
                E('div', {
                    'style': 'color:var(--text-color-medium);font-size:.9em;margin-top:.6em;line-height:1.7'
                }, [
                    E('div', {}, [
                        'Last IMEI rotation: ',
                        E('span', { 'style': 'font-family:monospace' }, [ st.last_imei_rotate || 'Never' ])
                    ]),
                    E('div', {}, [
                        'Last wireless rotation: ',
                        E('span', { 'style': 'font-family:monospace' }, [ st.last_wireless_rotate || 'Never' ])
                    ])
                ])
            ])
        ].concat(log ? [
            // ── Last command log ──────────────────────────────────────────────
            section('Last Command Log', [
                E('pre', { 'style': 'background:#f4f4f4;padding:10px;font-size:11px;overflow-x:auto;' +
                    'border:1px solid #ddd;border-radius:3px;margin:0;white-space:pre-wrap' }, [ log ])
            ])
        ] : []));

        // Wire static IMEI section show/hide and description updates to per-slot radios
        function updateStaticSection() {
            var s1 = page.querySelector('input[name="imei_mode_slot1"]:checked');
            var s2 = page.querySelector('input[name="imei_mode_slot2"]:checked');
            var show1 = s1 && s1.value === 'static';
            var show2 = s2 && s2.value === 'static';
            staticSlot1El.style.display = show1 ? '' : 'none';
            staticSlot2El.style.display = show2 ? '' : 'none';
            staticImeiSection.style.display = (show1 || show2) ? '' : 'none';
        }
        page.querySelectorAll('input[name="imei_mode_slot1"]').forEach(function(rb) {
            rb.addEventListener('change', function() {
                modeDesc1El.textContent = modeDesc(rb.value);
                updateStaticSection();
            });
        });
        page.querySelectorAll('input[name="imei_mode_slot2"]').forEach(function(rb) {
            rb.addEventListener('change', function() {
                modeDesc2El.textContent = modeDesc(rb.value);
                updateStaticSection();
            });
        });

        // Populate IMSI asynchronously — these are slow AT reads
        exec('imsi').then(function(out) {
            var r;
            try { r = JSON.parse(out); } catch(e) { r = {}; }
            imsi1El.textContent = r.slot1 === '__failed__' ? 'Failed to Populate' : r.slot1 || 'No SIM Detected';
            imsi1El.style.color  = (r.slot1 && r.slot1 !== '__failed__') ? '' : 'var(--text-color-medium)';
            imsi2El.textContent = r.slot2 === '__failed__' ? 'Failed to Populate' : r.slot2 || 'No SIM or eSIM Detected';
            imsi2El.style.color  = (r.slot2 && r.slot2 !== '__failed__') ? '' : 'var(--text-color-medium)';
        }).catch(function() {
            imsi1El.textContent = 'No SIM Detected';
            imsi1El.style.color  = 'var(--text-color-medium)';
            imsi2El.textContent = 'No SIM or eSIM Detected';
            imsi2El.style.color  = 'var(--text-color-medium)';
        });

        return page;
    },

    handleSave: null,
    handleSaveApply: null,
    handleReset: null
});
