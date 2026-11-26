import Foundation

/// JavaScript DOM & Virtual Mouse Cursor automation engine for Bihar SECURE v2 (`secure.dord.gov.in/securev2/`).
/// - Locates heading rows directly by exact heading text (`RCC DRAIN`, `PAVER BLOCK`, etc.) + `(Analysis of Rates)`
/// - Clicks the exact leftmost `⊕` Add Item button inside the heading row (before Edit pencil & Delete trash)
/// - Locates the left-panel stacked-layers `+` icon directly between `LMR Location` and `No Appendix Added !` / headings
/// - Renders a live animated virtual mouse cursor with click ripples
enum SecureAutomationJS {
    static let engineScript: String = #"""
    (function() {
      if (window.__SECURE_AI_IPAD_V5__) return;

      const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

      function ensureCursor(doc) {
        try {
          if (!doc || !doc.body) return null;
          let cur = doc.getElementById('secure-ai-virtual-cursor');
          if (!cur) {
            cur = doc.createElement('div');
            cur.id = 'secure-ai-virtual-cursor';
            cur.innerHTML = '<svg width="24" height="24" viewBox="0 0 24 24" fill="none"><path d="M4 2L20 11.5L12.5 13.5L9.5 21L4 2Z" fill="#8B7BFF" stroke="#FFFFFF" stroke-width="1.8" stroke-linejoin="round"/></svg>';
            Object.assign(cur.style, {
              position: 'fixed', left: '50%', top: '50%', width: '24px', height: '24px',
              zIndex: '2147483647', pointerEvents: 'none',
              transition: 'left 0.15s ease-out, top 0.15s ease-out, opacity 0.2s',
              opacity: '0', filter: 'drop-shadow(0 2px 6px rgba(0,0,0,0.55))'
            });
            doc.body.appendChild(cur);
          }
          return cur;
        } catch (_) { return null; }
      }

      async function moveCursorAndRipple(el) {
        if (!el) return { cx: 0, cy: 0 };
        const doc = el.ownerDocument || document;
        const cur = ensureCursor(doc);
        const r = el.getBoundingClientRect();
        const cx = Math.max(4, Math.min((doc.defaultView?.innerWidth || window.innerWidth) - 4, r.left + r.width / 2));
        const cy = Math.max(4, Math.min((doc.defaultView?.innerHeight || window.innerHeight) - 4, r.top + r.height / 2));
        if (cur) {
          cur.style.opacity = '1';
          cur.style.left = `${cx}px`;
          cur.style.top = `${cy}px`;
          await sleep(160);
          const ring = doc.createElement('div');
          Object.assign(ring.style, {
            position: 'fixed', left: `${cx - 14}px`, top: `${cy - 14}px`, width: '28px', height: '28px',
            borderRadius: '50%', border: '2.5px solid #8B7BFF', background: 'rgba(139, 123, 255, 0.28)',
            zIndex: '2147483646', pointerEvents: 'none',
            transition: 'transform 0.25s ease-out, opacity 0.25s ease-out',
            transform: 'scale(0.5)', opacity: '1'
          });
          doc.body.appendChild(ring);
          requestAnimationFrame(() => { ring.style.transform = 'scale(1.6)'; ring.style.opacity = '0'; });
          setTimeout(() => { try { ring.remove(); } catch (_) {} }, 300);
        }
        return { cx, cy };
      }

      function hideCursor() {
        for (const d of getAllDocs()) {
          try { const cur = d.getElementById('secure-ai-virtual-cursor'); if (cur) cur.style.opacity = '0'; } catch (_) {}
        }
      }

      function getAllDocs() {
        const docs = [document];
        try {
          for (const f of document.querySelectorAll('iframe, frame')) {
            try { if (f.contentDocument && f.contentDocument.body) docs.push(f.contentDocument); } catch (_) {}
          }
        } catch (_) {}
        return docs;
      }

      function queryAllAcrossDocs(selector) {
        const out = [];
        for (const d of getAllDocs()) {
          try { out.push(...Array.from(d.querySelectorAll(selector))); } catch (_) {}
        }
        return out;
      }

      function isVisible(el) {
        if (!el) return false;
        const win = el.ownerDocument?.defaultView || window;
        const style = win.getComputedStyle(el);
        if (style.display === 'none' || style.visibility === 'hidden' || parseFloat(style.opacity) === 0) return false;
        const rect = el.getBoundingClientRect();
        return rect.width > 1 && rect.height > 1;
      }

      function blurKeyboard() {
        for (const d of getAllDocs()) {
          try { if (d.activeElement && typeof d.activeElement.blur === 'function') d.activeElement.blur(); } catch (_) {}
        }
      }

      function setNativeValue(el, value, shouldBlur = true) {
        if (!el) return;
        const win = el.ownerDocument?.defaultView || window;
        const str = value == null ? '' : String(value);
        const proto = el.tagName === 'TEXTAREA'
          ? win.HTMLTextAreaElement.prototype
          : (el.tagName === 'SELECT' ? win.HTMLSelectElement.prototype : win.HTMLInputElement.prototype);
        const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
        if (setter) setter.call(el, str);
        else el.value = str;
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        el.dispatchEvent(new Event('blur', { bubbles: true }));
        if (shouldBlur) blurKeyboard();
      }

      async function clickEl(el) {
        if (!el) return false;
        try { el.scrollIntoView({ behavior: 'instant', block: 'center' }); } catch (_) {}
        const pos = await moveCursorAndRipple(el);
        const win = el.ownerDocument?.defaultView || window;
        const opts = { bubbles: true, cancelable: true, view: win, clientX: pos.cx, clientY: pos.cy };
        try { el.dispatchEvent(new PointerEvent('pointermove', opts)); } catch (_) {}
        el.dispatchEvent(new MouseEvent('mousemove', opts));
        try { el.dispatchEvent(new PointerEvent('pointerdown', opts)); } catch (_) {}
        el.dispatchEvent(new MouseEvent('mousedown', opts));
        el.dispatchEvent(new MouseEvent('mouseup', opts));
        try { el.dispatchEvent(new PointerEvent('pointerup', opts)); } catch (_) {}
        el.click();
        return true;
      }

      async function autoFillSecureLogin(userId, password) {
        const inputs = queryAllAcrossDocs('input').filter((el) => isVisible(el) && !el.disabled);
        const userInput = inputs.find((el) => {
          const m = `${el.placeholder || ''} ${el.name || ''} ${el.id || ''} ${el.getAttribute('formcontrolname') || ''}`.toLowerCase();
          return m.includes('user') || m.includes('login') || m.includes('email') || el.type === 'text';
        });
        const passInput = inputs.find((el) => el.type === 'password' || `${el.placeholder || ''} ${el.name || ''}`.toLowerCase().includes('pass'));
        const captchaInput = inputs.find((el) => `${el.placeholder || ''} ${el.name || ''} ${el.id || ''}`.toLowerCase().includes('captcha'));

        if (!userInput || !passInput) {
          return { ok: false, message: 'Open the SECURE Login popup first, then tap your saved account.' };
        }
        await moveCursorAndRipple(userInput);
        setNativeValue(userInput, userId, false);
        await sleep(120);
        await moveCursorAndRipple(passInput);
        setNativeValue(passInput, password, false);
        await sleep(120);
        hideCursor();
        if (captchaInput) captchaInput.focus();
        return { ok: true, message: `Filled login for ${userId}. Enter CAPTCHA and tap LOGIN.` };
      }

      function isPortalLoading() {
        const selectors = [
          '.spinner', '.loader', '.loading', '.blockUI', '.ngx-spinner-overlay',
          '.swal2-loading', '[class*="spinner"]', '[class*="loader"]', '#preloader',
          '.mat-progress-bar', '.progress-bar-animated'
        ];
        for (const sel of selectors) {
          for (const n of queryAllAcrossDocs(sel)) {
            if (isVisible(n)) return true;
          }
        }
        for (const s of queryAllAcrossDocs('div, span, p')) {
          if (s.children.length === 0 && isVisible(s)) {
            const t = (s.textContent || '').trim().toLowerCase();
            if (t === 'loading' || t === 'loading...' || t === 'please wait...') return true;
          }
        }
        return false;
      }

      async function waitForPortalIdle(minWaitMs = 700, maxWaitMs = 20000) {
        const start = Date.now();
        await sleep(minWaitMs);
        while (Date.now() - start < maxWaitMs) {
          if (!isPortalLoading()) return true;
          await sleep(250);
        }
        return false;
      }

      function findButtonByText(patterns, root = null) {
        const regexList = patterns.map((p) => (p instanceof RegExp ? p : new RegExp(p, 'i')));
        const candidates = root
          ? Array.from(root.querySelectorAll('button, a.btn, input[type="button"], input[type="submit"], [role="button"], a'))
          : queryAllAcrossDocs('button, a.btn, input[type="button"], input[type="submit"], [role="button"], a');
        for (const el of candidates) {
          if (!isVisible(el) || el.disabled) continue;
          const txt = (el.innerText || el.value || el.getAttribute('title') || el.getAttribute('aria-label') || '').trim();
          if (regexList.some((re) => re.test(txt))) return el;
        }
        return null;
      }

      async function dismissSwalIfAny() {
        for (const btn of queryAllAcrossDocs('.swal2-confirm, button.confirm')) {
          if (isVisible(btn)) {
            const txt = (btn.innerText || '').trim().toLowerCase();
            if (txt === 'ok' || txt.includes('close')) {
              await clickEl(btn);
              return true;
            }
          }
        }
        return false;
      }

      async function confirmSwalDelete() {
        for (let i = 0; i < 20; i++) {
          for (const b of queryAllAcrossDocs('.swal2-confirm, button.swal2-confirm, button.btn-primary, button')) {
            if (!isVisible(b)) continue;
            const txt = (b.innerText || '').trim().toLowerCase();
            if (txt.includes('yes, delete') || txt.includes('yes delete') || (b.classList.contains('swal2-confirm') && txt.includes('yes'))) {
              await clickEl(b);
              await waitForPortalIdle(900, 20000);
              return { ok: true, message: 'Confirmed SweetAlert2 delete' };
            }
          }
          await sleep(180);
        }
        return { ok: false, message: 'SweetAlert2 delete confirmation button not found' };
      }

      function findActiveAppendixForm() {
        let best = null;
        let bestArea = Infinity;
        for (const el of queryAllAcrossDocs('div, form, section, .card, .modal-content')) {
          if (!isVisible(el)) continue;
          const txt = el.innerText || '';
          if (txt.includes('Add Appendix/Description') && (txt.includes('Heading / Description') || txt.includes('Lump sum Type'))) {
            const hasAdd = !!findButtonByText([/^add$/i], el);
            const hasChk = el.querySelectorAll('input[type="checkbox"]').length >= 1;
            if (hasAdd && hasChk) {
              const r = el.getBoundingClientRect();
              const area = r.width * r.height;
              if (area < bestArea) {
                bestArea = area;
                best = el;
              }
            }
          }
        }
        return best;
      }

      async function openAddAppendixForm() {
        let form = findActiveAppendixForm();
        if (form) return form;

        let lmrRect = null;
        for (const n of queryAllAcrossDocs('label, span, div, td, p')) {
          if (!isVisible(n) || n.children.length > 2) continue;
          if ((n.textContent || '').trim().toLowerCase().startsWith('lmr location')) {
            lmrRect = n.getBoundingClientRect();
            break;
          }
        }

        const vw = window.innerWidth;
        const minY = lmrRect ? (lmrRect.bottom - 2) : 80;
        const maxY = lmrRect ? (lmrRect.bottom + 140) : 340;
        const maxX = vw * 0.45;

        const candidates = [];
        for (const el of queryAllAcrossDocs('img, svg, i, mat-icon, button, a, span, div')) {
          if (!isVisible(el)) continue;
          const r = el.getBoundingClientRect();
          if (r.top >= minY && r.bottom <= maxY && r.left >= 10 && r.right <= maxX) {
            if (r.width >= 14 && r.width <= 96 && r.height >= 14 && r.height <= 74) {
              const isIcon = ['IMG', 'SVG', 'I', 'MAT-ICON'].includes(el.tagName) || (['BUTTON', 'A'].includes(el.tagName) && el.querySelector('img, svg, i, mat-icon'));
              if (!isIcon) continue;
              const meta = `${el.className || ''} ${el.getAttribute('title') || ''} ${el.getAttribute('aria-label') || ''}`.toLowerCase();
              if (meta.includes('expand') || meta.includes('full')) continue;
              if (r.left > vw * 0.34) continue;
              candidates.push({ el, rect: r });
            }
          }
        }

        const targetX = vw * 0.21;
        candidates.sort((a, b) => Math.abs((a.rect.left + a.rect.width / 2) - targetX) - Math.abs((b.rect.left + b.rect.width / 2) - targetX));

        const tried = new Set();
        for (const c of candidates.slice(0, 6)) {
          const target = c.el.closest('button, a, [role="button"], div') || c.el;
          if (tried.has(target)) continue;
          tried.add(target);
          await clickEl(target);
          for (let w = 0; w < 8; w++) {
            await sleep(160);
            form = findActiveAppendixForm();
            if (form) return form;
          }
        }
        return null;
      }

      function findHeadingRowByTextOrIndex(headingText, headingIndex) {
        const vw = window.innerWidth;
        const targetText = String(headingText || '').trim().toUpperCase();

        const allRows = [];
        const seenRows = new Set();
        for (const el of queryAllAcrossDocs('div, li, tr, mat-expansion-panel-header, button, a, p, span, h5, h6')) {
          if (!isVisible(el)) continue;
          const r = el.getBoundingClientRect();
          if (r.left > vw * 0.45 || r.width < 40 || r.height > 120) continue;
          const txt = (el.innerText || '').trim().toUpperCase();
          if (!txt || txt.includes('NO APPENDIX ADDED') || txt.includes('ADD APPENDIX/DESCRIPTION') || txt.includes('VB-G RAM G TOTAL')) continue;

          if (txt.includes('ANALYSIS OF RATES') || (targetText.length >= 3 && txt.includes(targetText))) {
            let row = el;
            for (let step = 0; step < 5 && row.parentElement; step++) {
              const pr = row.parentElement.getBoundingClientRect();
              const iconCount = row.querySelectorAll('svg, i, img, button, a, mat-icon').length;
              if (iconCount >= 2 && row.getBoundingClientRect().width >= 150 && row.getBoundingClientRect().height <= 110) {
                break;
              }
              if (pr.width <= vw * 0.48 && pr.height <= 120) {
                row = row.parentElement;
              } else {
                break;
              }
            }
            if (!seenRows.has(row)) {
              seenRows.add(row);
              allRows.push(row);
            }
          }
        }

        const filtered = allRows.filter((row) => {
          return !allRows.some((other) => other !== row && row.contains(other) && other.querySelectorAll('svg, i, img, button, a, mat-icon').length >= 2);
        });

        filtered.sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top);

        if (targetText.length >= 3) {
          const exact = filtered.find((r) => (r.innerText || '').toUpperCase().includes(targetText));
          if (exact) return exact;
        }
        return filtered[headingIndex] || filtered[filtered.length - 1] || null;
      }

      function findAddItemButtonInRow(row) {
        if (!row) return null;
        const rowRect = row.getBoundingClientRect();
        const explicitPlus = row.querySelector('.fa-plus, .fa-plus-circle, .bi-plus, .bi-plus-circle, [title*="Add"], [aria-label*="Add"]');
        if (explicitPlus && isVisible(explicitPlus)) {
          return explicitPlus.closest('button, a, [role="button"]') || explicitPlus;
        }
        const icons = Array.from(row.querySelectorAll('button, a, svg, i, img, mat-icon'))
          .filter((el) => {
            if (!isVisible(el)) return false;
            const r = el.getBoundingClientRect();
            const isSmallIcon = r.width >= 10 && r.width <= 48 && r.height >= 10 && r.height <= 48;
            const meta = `${el.className || ''} ${el.getAttribute('title') || ''}`.toLowerCase();
            if (meta.includes('info') || meta.includes('trash') || meta.includes('delete') || meta.includes('edit') || meta.includes('pencil')) return false;
            return isSmallIcon && r.left > (rowRect.left + rowRect.width * 0.42);
          })
          .sort((a, b) => a.getBoundingClientRect().left - b.getBoundingClientRect().left);

        if (icons.length > 0) {
          return icons[0].closest('button, a, [role="button"]') || icons[0];
        }
        return null;
      }

      async function addHeading(headingText) {
        await dismissSwalIfAny();
        const form = await openAddAppendixForm();
        if (!form) {
          return { ok: false, message: 'Could not open "Add Appendix/Description". Tap the stacked-layers + icon on the left once, then press Resume.' };
        }

        const checkboxes = Array.from(form.querySelectorAll('input[type="checkbox"]'))
          .filter(isVisible)
          .sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top);

        if (checkboxes.length >= 1 && !checkboxes[0].checked) {
          await clickEl(checkboxes[0]);
          await sleep(300);
        }

        const inputs = Array.from(form.querySelectorAll('input[type="text"], input:not([type]), textarea'))
          .filter((el) => isVisible(el) && !el.disabled && !el.readOnly);
        const headInput = inputs.find((el) => {
          const meta = `${el.placeholder || ''} ${el.name || ''} ${el.id || ''}`.toLowerCase();
          return meta.includes('analysis') || meta.includes('rate') || meta.includes('head') || meta.includes('desc');
        }) || inputs[0];

        if (!headInput) {
          return { ok: false, message: 'Heading text input not found inside Add Appendix/Description.' };
        }

        await moveCursorAndRipple(headInput);
        setNativeValue(headInput, headingText);
        await sleep(220);

        const addBtn = findButtonByText([/^add$/i, /save/i, /submit/i], form);
        if (!addBtn) {
          return { ok: false, message: '"Add" button not found inside Add Appendix/Description.' };
        }
        await clickEl(addBtn);
        await waitForPortalIdle(1000, 20000);
        await dismissSwalIfAny();
        blurKeyboard();
        return { ok: true, message: `Added heading: ${headingText}` };
      }

      async function addItem(headingIndex, headingText, code, isTM) {
        await dismissSwalIfAny();
        const row = findHeadingRowByTextOrIndex(headingText, headingIndex);
        if (!row) {
          return { ok: false, message: `Heading "${headingText}" (#${headingIndex + 1}) not found in left panel.` };
        }

        const plusBtn = findAddItemButtonInRow(row);
        if (!plusBtn) {
          return { ok: false, message: `Could not find ⊕ Add Item button on heading "${headingText}".` };
        }
        await clickEl(plusBtn);
        await waitForPortalIdle(850, 15000);

        const selects = queryAllAcrossDocs('select').filter((s) => isVisible(s) && !s.disabled);
        const subheadSelect = selects.find((s) => {
          const txt = Array.from(s.options).map((o) => o.text).join(' ').toLowerCase();
          return txt.includes('sub head') || txt.includes('mgnrega') || txt.includes('54 -');
        });

        if (subheadSelect) {
          const chapter = String(code).split('.')[0].trim();
          let chosen = null;
          for (const opt of Array.from(subheadSelect.options)) {
            const t = (opt.text || '').trim();
            if (isTM && t.toUpperCase().includes('54') && t.toUpperCase().includes('TM')) { chosen = opt; break; }
            if (!isTM && chapter === '54' && t.toUpperCase().includes('54') && !t.toUpperCase().includes('TM') && t.toLowerCase().includes('bihar')) { chosen = opt; break; }
            if (chapter !== '54' && t.startsWith(chapter)) { chosen = opt; break; }
          }
          if (chosen) {
            await moveCursorAndRipple(subheadSelect);
            subheadSelect.value = chosen.value;
            subheadSelect.dispatchEvent(new Event('change', { bubbles: true }));
            await waitForPortalIdle(850, 15000);
          }
        }

        const searchInputs = queryAllAcrossDocs('input[type="text"], input[type="search"], input:not([type])')
          .filter((el) => isVisible(el) && !el.disabled && el.getBoundingClientRect().left > window.innerWidth * 0.35);
        const searchBox = searchInputs.find((el) => {
          const meta = `${el.placeholder || ''} ${el.name || ''} ${el.id || ''}`.toLowerCase();
          return meta.includes('spec') || meta.includes('search') || meta.includes('code') || meta.includes('activity') || meta.includes('item');
        }) || searchInputs[0];

        if (!searchBox) {
          return { ok: false, message: `Specification/Activity search box not found for ${code}.` };
        }
        await moveCursorAndRipple(searchBox);
        setNativeValue(searchBox, code);
        await sleep(220);

        const searchBtn = findButtonByText([/search/i, /find/i, /go/i]);
        if (searchBtn) {
          await clickEl(searchBtn);
          await waitForPortalIdle(850, 15000);
        }

        const rows = queryAllAcrossDocs('tr, .list-group-item, .search-result-row, div').filter((r) => isVisible(r) && r.querySelector('input[type="checkbox"]'));
        const codeUpper = String(code).trim().toUpperCase();
        const matchedRow = rows.find((r) => (r.innerText || '').toUpperCase().includes(codeUpper) && r.getBoundingClientRect().height < 220);

        if (!matchedRow) {
          const cancelBtn = findButtonByText([/cancel/i, /close/i]);
          if (cancelBtn) await clickEl(cancelBtn);
          await sleep(300);
          return { ok: true, skipped: true, message: `Code ${code} not in search results (already present). Closed cleanly.` };
        }

        const chk = matchedRow.querySelector('input[type="checkbox"]');
        if (chk && !chk.checked) {
          await clickEl(chk);
          await sleep(220);
        }

        const saveSpecBtn = findButtonByText([/save/i, /add\s*selected/i, /add\s*item/i, /submit/i]);
        if (!saveSpecBtn) {
          return { ok: false, message: `Save button not found after selecting ${code}.` };
        }
        await clickEl(saveSpecBtn);
        await waitForPortalIdle(1000, 20000);
        await dismissSwalIfAny();
        blurKeyboard();
        return { ok: true, message: `Added SOR item ${code}` };
      }

      async function fillMeasurements(headingIndex, headingText, code, rowsData) {
        await dismissSwalIfAny();
        const row = findHeadingRowByTextOrIndex(headingText, headingIndex);
        if (!row) {
          return { ok: false, message: `Heading "${headingText}" not found for measurements of ${code}.` };
        }

        const container = row.parentElement || row;
        const codeUpper = String(code).toUpperCase();
        let itemNode = Array.from(container.querySelectorAll('div, tr, li, a, span')).find((n) => isVisible(n) && (n.innerText || '').toUpperCase().includes(codeUpper) && n.getBoundingClientRect().height < 140);
        if (!itemNode) {
          await clickEl(row);
          await sleep(500);
          itemNode = Array.from(container.querySelectorAll('div, tr, li, a, span')).find((n) => isVisible(n) && (n.innerText || '').toUpperCase().includes(codeUpper) && n.getBoundingClientRect().height < 140);
        }
        if (!itemNode) {
          itemNode = Array.from(container.querySelectorAll('div, tr, li')).find((n) => isVisible(n) && ((n.innerText || '').includes('₹ 0') || (n.innerText || '').includes('0.00')) && n.getBoundingClientRect().height < 140);
        }
        if (itemNode) {
          const measBtn = itemNode.querySelector('button[title*="Meas"], a[title*="Meas"], .fa-plus, .fa-calculator, .fa-edit') || itemNode;
          await clickEl(measBtn);
          await waitForPortalIdle(800, 15000);
        }

        for (let rIdx = 0; rIdx < rowsData.length; rIdx++) {
          const rData = rowsData[rIdx];
          if (rIdx > 0 || rData.isDeduction) {
            const addRowBtn = rData.isDeduction
              ? findButtonByText([/add\s*deduct/i, /deduction/i])
              : findButtonByText([/add\s*measurement/i, /add\s*row/i, /\+\s*add/i]);
            if (addRowBtn) {
              await clickEl(addRowBtn);
              await sleep(300);
            }
          }

          const trs = queryAllAcrossDocs('table tbody tr').filter((tr) => {
            return isVisible(tr) && tr.querySelectorAll('input:not([type="hidden"]):not([type="checkbox"])').length >= 3;
          });
          const targetTr = trs[trs.length - 1];
          if (!targetTr) {
            return { ok: false, message: `Measurement input row not found for ${code} (row ${rIdx + 1}).` };
          }
          const inputs = Array.from(targetTr.querySelectorAll('input:not([type="hidden"]):not([type="checkbox"]), textarea'))
            .filter((el) => isVisible(el) && !el.disabled && !el.readOnly);

          const values = [rData.desc || '', rData.no || '1', rData.l || '', rData.b || '', rData.d || '', rData.cf || ''];
          for (let ci = 0; ci < Math.min(inputs.length, values.length); ci++) {
            if (values[ci] !== '') {
              setNativeValue(inputs[ci], values[ci]);
              await sleep(50);
            }
          }
        }

        const saveBtn = findButtonByText([/save\s*measurement/i, /^save$/i, /update/i]);
        if (!saveBtn) {
          return { ok: false, message: `Save Measurements button not found for ${code}.` };
        }
        await clickEl(saveBtn);
        await waitForPortalIdle(1000, 20000);
        await dismissSwalIfAny();
        blurKeyboard();
        return { ok: true, message: `Saved ${rowsData.length} measurement row(s) for ${code}` };
      }

      async function addLumpSum(keyword, customDesc, amount) {
        await dismissSwalIfAny();
        const form = await openAddAppendixForm();
        if (!form) {
          return { ok: false, message: 'Could not open Add Appendix/Description for Lump Sum.' };
        }

        const checkboxes = Array.from(form.querySelectorAll('input[type="checkbox"]'))
          .filter(isVisible)
          .sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top);

        let lumpChk = checkboxes.find((cb) => {
          const labelTxt = (cb.closest('label')?.innerText || cb.parentElement?.innerText || '').toLowerCase();
          return labelTxt.includes('lump') && !labelTxt.includes('heading');
        }) || (checkboxes.length >= 2 ? checkboxes[checkboxes.length - 1] : checkboxes[0]);

        if (lumpChk && !lumpChk.checked) {
          await clickEl(lumpChk);
          await sleep(450);
        }

        const selects = Array.from(form.querySelectorAll('select')).filter((s) => isVisible(s) && !s.disabled);
        const lumpSelect = selects.find((s) => {
          const txt = Array.from(s.options).map((o) => o.text).join(' ').toLowerCase();
          return txt.includes('lump') || txt.includes('conveyance') || txt.includes('miscellaneous') || txt.includes('display board');
        }) || selects[0];

        if (!lumpSelect) {
          return { ok: false, message: 'Lump sum Type dropdown not found.' };
        }

        const kwLow = String(keyword || 'Miscellaneous').toLowerCase();
        const opt = Array.from(lumpSelect.options).find((o) => (o.text || '').toLowerCase().includes(kwLow))
          || Array.from(lumpSelect.options).find((o) => (o.text || '').toLowerCase().includes('miscellaneous'));
        if (opt) {
          await moveCursorAndRipple(lumpSelect);
          lumpSelect.value = opt.value;
          lumpSelect.dispatchEvent(new Event('change', { bubbles: true }));
          await sleep(500);
        }

        const inputs = Array.from(form.querySelectorAll('input[type="text"], input[type="number"], input:not([type]), textarea'))
          .filter((el) => isVisible(el) && !el.disabled && !el.readOnly);
        const descInput = inputs.find((el) => {
          const meta = `${el.placeholder || ''} ${el.name || ''} ${el.id || ''}`.toLowerCase();
          return meta.includes('desc') && !meta.includes('head') && !meta.includes('analysis');
        });
        if (descInput && customDesc) {
          setNativeValue(descInput, customDesc);
          await sleep(150);
        }

        const amtInput = inputs.find((el) => {
          const meta = `${el.placeholder || ''} ${el.name || ''} ${el.id || ''}`.toLowerCase();
          return meta.includes('amount') || meta.includes('amt') || meta.includes('cost') || el.type === 'number';
        }) || inputs[inputs.length - 1];

        if (!amtInput) {
          return { ok: false, message: 'Lump sum amount input not found.' };
        }
        await moveCursorAndRipple(amtInput);
        setNativeValue(amtInput, String(amount));
        await sleep(200);

        const saveBtn = findButtonByText([/^add$/i, /add\s*lump/i, /save/i], form);
        if (!saveBtn) {
          return { ok: false, message: '"Add" button not found for Lump Sum.' };
        }
        await clickEl(saveBtn);
        await waitForPortalIdle(950, 20000);
        await dismissSwalIfAny();
        blurKeyboard();
        return { ok: true, message: `Added Lump Sum: ${keyword} (₹${amount})` };
      }

      function scrapeCurrentEstimate() {
        const vw = window.innerWidth;
        const rows = [];
        for (const el of queryAllAcrossDocs('div, li, tr')) {
          if (!isVisible(el)) continue;
          const r = el.getBoundingClientRect();
          if (r.left > vw * 0.45 || r.height > 120) continue;
          const txt = (el.innerText || '').trim();
          if (txt.includes('Analysis of Rates') && el.querySelectorAll('svg, i, img, button').length >= 2) {
            rows.push(el);
          }
        }
        const headings = rows.map((row, idx) => {
          const rawTitle = (row.innerText || '').split('\n')[0].trim();
          const container = row.parentElement || row;
          const items = [];
          const codeRe = /\b(\d{1,2}(?:\.TM)?(?:\.[A-Za-z0-9]+){2,6})\b/gi;
          const text = container.innerText || '';
          const seen = new Set();
          let m;
          while ((m = codeRe.exec(text)) !== null) {
            const c = m[1].toUpperCase();
            if (!seen.has(c)) {
              seen.add(c);
              items.push({ code: c, description: c, quantity: 0, amount: 0 });
            }
          }
          return { index: idx, text: rawTitle, items };
        });

        const lumpSums = [];
        const bodyText = document.body.innerText || '';
        const lumpLines = bodyText.split('\n').filter((l) => /lump\s*sum|conveyance|display board|cess|contingenc/i.test(l));
        for (const l of lumpLines.slice(0, 12)) {
          const numMatch = l.match(/(\d+(?:,\d+)*(?:\.\d+)?)/);
          lumpSums.push({ description: l.trim(), amount: numMatch ? parseFloat(numMatch[1].replace(/,/g, '')) : 0 });
        }
        return { headings, lumpSums };
      }

      async function deleteItemInHeading(headingIndex, code) {
        const row = findHeadingRowByTextOrIndex('', headingIndex);
        if (!row) return { ok: false, message: `Heading #${headingIndex + 1} not found for deletion.` };
        const container = row.parentElement || row;
        const codeUpper = String(code).toUpperCase();
        const rows = Array.from(container.querySelectorAll('tr, li, .item-row, div')).filter(isVisible);
        const match = rows.find((r) => (r.innerText || '').toUpperCase().includes(codeUpper) && r.querySelector('.fa-trash, .bi-trash, button[title*="Delete"], a[title*="Delete"]'));
        if (!match) return { ok: false, message: `Delete icon not found for item ${code}.` };
        const delBtn = match.querySelector('.fa-trash, .bi-trash, button[title*="Delete"], a[title*="Delete"]')?.closest('button, a')
          || match.querySelector('.fa-trash, .bi-trash');
        await clickEl(delBtn);
        return await confirmSwalDelete();
      }

      window.__SECURE_AI_IPAD__ = {
        addHeading,
        addItem,
        fillMeasurements,
        addLumpSum,
        scrapeCurrentEstimate,
        deleteItemInHeading,
        confirmSwalDelete,
        autoFillSecureLogin,
        hideCursor,
        isPortalLoading
      };
      window.__SECURE_AI_IPAD_V5__ = true;
    })();
    """#
}
