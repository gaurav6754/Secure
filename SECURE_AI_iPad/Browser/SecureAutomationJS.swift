import Foundation

/// JavaScript DOM & Virtual Mouse Cursor automation engine for Bihar SECURE v2 (`secure.dord.gov.in/securev2/`).
/// - Locates heading rows directly by exact heading text (`RCC DRAIN`, `PAVER BLOCK`, etc.) + `(Analysis of Rates)`
/// - Clicks the exact leftmost `⊕` Add Item button inside the heading row (before Edit pencil & Delete trash)
/// - Locates the left-panel stacked-layers `+` icon directly between `LMR Location` and `No Appendix Added !` / headings
/// - Renders a live animated virtual mouse cursor with click ripples
enum SecureAutomationJS {
    static let engineScript: String = #"""
    (function() {
      if (window.__SECURE_AI_IPAD_V24__) return;

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
          await sleep(Math.max(45, Math.round(160 / (window.__SECURE_AI_SPEED__ || 1))));
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

      function getCheckboxTarget(cb) {
        if (!cb) return null;
        if (isVisible(cb)) return cb;
        const wrap = cb.closest('mat-checkbox, label, .form-check, .custom-control, .mdc-checkbox');
        return (wrap && isVisible(wrap)) ? wrap : null;
      }

      function blurKeyboard() {
        for (const d of getAllDocs()) {
          try { if (d.activeElement && typeof d.activeElement.blur === 'function') d.activeElement.blur(); } catch (_) {}
        }
      }

      function sanitizeSecureDesc(raw, maxLen = 95) {
        let s = String(raw == null ? '' : raw)
          .replace(/https?:\/\/\S+/gi, ' ')
          .replace(/Page\s+\d+\s+of\s+\d+/gi, ' ')
          .replace(/[\r\n\t]+/g, ' ')
          .replace(/:/g, '-')
          .replace(/[×xX](?=\s*\d)/g, 'X')
          .replace(/[–—]/g, '-')
          .replace(/[^A-Za-z0-9 .+\-*()/]/g, ' ')
          .replace(/\s+/g, ' ')
          .trim();
        // Strip leading lone serial number like "1 GW PCC..." -> "GW PCC..."
        s = s.replace(/^\d{1,2}\s+(?!MM\b|CM\b|FT\b|IN\b|INCH\b|M\b|SQM\b|CUM\b|KG\b)(?=[A-Za-z])/i, '');
        // Smart reorder: "12 MM CM 1-4 PLASTER" -> "CM 1-4 PLASTER 12 MM", "100A BRICK..." -> "BRICK... 100A"
        const leadNum = s.match(/^([0-9][A-Za-z0-9.\-]*(?:\s+(?:MM|CM|FT|IN|INCH|M|SQM|CUM|KG))?)\s+([A-Za-z].*)$/i);
        if (leadNum) {
          s = `${leadNum[2]} ${leadNum[1]}`.trim();
        }
        // SECURE v2 rejects Item Description / Heading starting with a digit or symbol (and never write lone "1")!
        if (!s || /^\d+$/.test(s)) {
          s = 'Work';
        } else if (!/^[A-Za-z]/.test(s)) {
          s = 'Work ' + s;
        }
        return s.slice(0, maxLen).trim();
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
        try { el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true })); } catch (_) {}
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
        if (typeof el.click === 'function') {
          el.click();
        } else {
          el.dispatchEvent(new MouseEvent('click', opts));
        }
        return true;
      }

      async function autoFillSecureLogin(userId, password) {
        const findLoginFields = () => {
          const inputs = queryAllAcrossDocs('input').filter((el) => isVisible(el) && !el.disabled);
          const userInput = inputs.find((el) => {
            const m = `${el.placeholder || ''} ${el.name || ''} ${el.id || ''} ${el.getAttribute('formcontrolname') || ''}`.toLowerCase();
            return m.includes('user') || m.includes('login') || m.includes('email') || el.type === 'text';
          });
          const passInput = inputs.find((el) => el.type === 'password' || `${el.placeholder || ''} ${el.name || ''}`.toLowerCase().includes('pass'));
          const captchaInput = inputs.find((el) => `${el.placeholder || ''} ${el.name || ''} ${el.id || ''}`.toLowerCase().includes('captcha'));
          return { userInput, passInput, captchaInput };
        };

        let { userInput, passInput, captchaInput } = findLoginFields();
        if (!userInput || !passInput) {
          // Try opening the Login popup automatically if the user is on the SECURE landing page
          const openLoginBtn = findButtonByText([/^login$/i, /sign\s*in/i]);
          if (openLoginBtn) {
            await clickEl(openLoginBtn);
            for (let w = 0; w < 8; w++) {
              await sleep(180);
              ({ userInput, passInput, captchaInput } = findLoginFields());
              if (userInput && passInput) break;
            }
          }
        }
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
        if (captchaInput) {
          try {
            captchaInput.setAttribute('inputmode', 'numeric');
            captchaInput.setAttribute('enterkeyhint', 'go');
            if (!captchaInput.__secureAiEnterBound) {
              captchaInput.__secureAiEnterBound = true;
              captchaInput.addEventListener('keydown', (ev) => {
                if (ev.key === 'Enter') {
                  const submitBtn = findButtonByText([/^login$/i, /submit/i]);
                  if (submitBtn) submitBtn.click();
                }
              });
            }
          } catch (_) {}
          captchaInput.focus();
        }
        return { ok: true, message: `Filled login for ${userId}. Type CAPTCHA and press Go/Return.` };
      }

      function isPortalLoading() {
        const vw = window.innerWidth || 1024;
        const vh = window.innerHeight || 768;
        // 1. Full-screen spinner overlay (only if genuinely covering >50% of screen)
        for (const n of queryAllAcrossDocs('.ngx-spinner-overlay, .blockUI')) {
          if (n.closest && n.closest('.swal2-container')) continue;
          if (!isVisible(n)) continue;
          const r = n.getBoundingClientRect();
          if (r.width > vw * 0.5 && r.height > vh * 0.5) return true;
        }
        // 2. Real SECURE v2 centered "Loading" modal text
        for (const s of queryAllAcrossDocs('div, span, p')) {
          if (s.children.length === 0 && isVisible(s)) {
            if (s.closest && s.closest('.swal2-container')) continue;
            const t = (s.textContent || '').trim().toLowerCase();
            if (t === 'loading' || t === 'loading...' || t === 'please wait...') {
              const r = s.getBoundingClientRect();
              if (r.left > vw * 0.20 && r.right < vw * 0.80 && r.top > vh * 0.15 && r.bottom < vh * 0.85) {
                return true;
              }
            }
          }
        }
        return false;
      }

      async function waitForPortalIdle(minWaitMs = 700, maxWaitMs = 12000) {
        const spd = Math.max(1, Math.min(5, window.__SECURE_AI_SPEED__ || 1));
        const scaledMin = Math.max(220, Math.round(minWaitMs / Math.sqrt(spd)));
        const start = Date.now();
        await sleep(scaledMin);
        while (Date.now() - start < maxWaitMs) {
          if (!isPortalLoading()) return true;
          await sleep(180);
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

      function findRightPanelButtonByText(patterns) {
        const vw = window.innerWidth || 1024;
        const regexList = patterns.map((p) => (p instanceof RegExp ? p : new RegExp(p, 'i')));
        const primary = queryAllAcrossDocs('button, a.btn, input[type="button"], input[type="submit"], [role="button"], a, .btn')
          .filter((el) => isVisible(el) && !el.disabled && el.getBoundingClientRect().left > vw * 0.35);
        for (const el of primary) {
          const txt = (el.innerText || el.value || el.getAttribute('title') || el.getAttribute('aria-label') || '').trim();
          if (txt.length <= 50 && regexList.some((re) => re.test(txt))) return el;
        }
        // Fallback: clickable div/span buttons (e.g. Angular custom styled 'Add Measurements +' / 'Add Deduction +')
        const fallback = queryAllAcrossDocs('div, span, label')
          .filter((el) => {
            if (!isVisible(el)) return false;
            const r = el.getBoundingClientRect();
            if (r.left <= vw * 0.35 || r.height < 20 || r.height > 64 || r.width < 40 || r.width > 320) return false;
            const txt = (el.innerText || el.textContent || '').trim();
            return txt.length > 0 && txt.length <= 45 && regexList.some((re) => re.test(txt));
          })
          .sort((a, b) => (a.getBoundingClientRect().width * a.getBoundingClientRect().height) - (b.getBoundingClientRect().width * b.getBoundingClientRect().height));
        if (fallback.length > 0) return fallback[0];
        return findButtonByText(patterns);
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
          const txt = (el.innerText || '').toLowerCase();
          if ((txt.includes('add appendix') || txt.includes('appendix/description')) &&
              (txt.includes('heading') || txt.includes('lump sum') || txt.includes('lumpsum'))) {
            const hasAdd = !!findButtonByText([/^add$/i, /^save$/i, /add\s*appendix/i], el);
            const hasChk = el.querySelectorAll('input[type="checkbox"], [role="checkbox"], mat-checkbox').length >= 1
                        || el.querySelectorAll('input[type="text"], textarea, select').length >= 1;
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
        if (form) return { form, diag: 'already-open' };

        const vw = window.innerWidth || 1024;
        const vh = window.innerHeight || 768;

        // 1. Find the SMALL leaf label for "LMR Location" (never a tall outer wrapper div!)
        let lmrRect = null;
        let lmrBestArea = Infinity;
        for (const n of queryAllAcrossDocs('label, span, div, td, p, b, strong')) {
          if (!isVisible(n)) continue;
          const t = (n.textContent || '').trim();
          if (t.length > 45) continue;
          if (!t.toLowerCase().startsWith('lmr location')) continue;
          const r = n.getBoundingClientRect();
          if (r.height < 8 || r.height > 65 || r.top < 20 || r.bottom > vh * 0.55) continue;
          const area = r.width * r.height;
          if (area < lmrBestArea) {
            lmrBestArea = area;
            lmrRect = r;
          }
        }

        // Also locate "No Appendix Added" if present (strictly below the stacked-layers + bar)
        let noAppRect = null;
        for (const n of queryAllAcrossDocs('div, span, p, h5, h6')) {
          if (!isVisible(n)) continue;
          const t = (n.textContent || '').trim();
          if (t.length < 40 && t.toLowerCase().includes('no appendix added')) {
            const r = n.getBoundingClientRect();
            if (r.height < 80 && r.left < vw * 0.45) {
              noAppRect = r;
              break;
            }
          }
        }

        const baseTop = lmrRect ? Math.min(Math.max(lmrRect.bottom, 90), vh * 0.45) : 145;
        const minY = baseTop - 2;
        const maxY = noAppRect ? Math.min(noAppRect.top - 4, baseTop + 150) : Math.min(baseTop + 150, vh * 0.65);
        const maxX = vw * 0.42;

        // 2. Scan DOM elements in the white rounded top bar below LMR Location (exclude right-edge expand icon)
        const candidates = [];
        for (const el of queryAllAcrossDocs('img, svg, i, mat-icon, button, a, fa-icon, span, div')) {
          if (!isVisible(el)) continue;
          const r = el.getBoundingClientRect();
          if (r.top < minY || r.bottom > maxY || r.left < 8 || r.right > maxX) continue;
          if (r.width < 14 || r.width > 110 || r.height < 14 || r.height > 80) continue;
          const win = el.ownerDocument?.defaultView || window;
          const isIcon = ['IMG', 'SVG', 'I', 'MAT-ICON', 'BUTTON', 'A', 'FA-ICON'].includes(el.tagName)
            || el.getAttribute('role') === 'button'
            || win.getComputedStyle(el).cursor === 'pointer';
          if (!isIcon) continue;
          const cls = typeof el.className === 'string' ? el.className : (el.className?.baseVal || '');
          const meta = `${cls} ${el.getAttribute('title') || ''} ${el.getAttribute('aria-label') || ''}`.toLowerCase();
          if (meta.includes('expand') || meta.includes('full') || meta.includes('close')) continue;
          if (r.left > vw * 0.33) continue; // skip the small expand icon on the right edge of the bar
          candidates.push({ el, rect: r });
        }

        const targetX = vw * 0.21;
        candidates.sort((a, b) => Math.abs((a.rect.left + a.rect.width / 2) - targetX) - Math.abs((b.rect.left + b.rect.width / 2) - targetX));

        const tried = new Set();
        for (const c of candidates.slice(0, 6)) {
          const target = c.el.closest('button, a, [role="button"]') || c.el;
          if (tried.has(target)) continue;
          tried.add(target);
          await clickEl(target);
          for (let w = 0; w < 6; w++) {
            await sleep(160);
            form = findActiveAppendixForm();
            if (form) return { form, diag: 'dom-candidate' };
          }
        }

        // 3. Direct PC-style elementFromPoint coordinate probe right across the stacked-layers + icon
        const probeXs = [vw * 0.21, vw * 0.19, vw * 0.23];
        const probeYs = [baseTop + 34, baseTop + 48, baseTop + 22, baseTop + 62, baseTop + 76]
          .filter((y) => y > 40 && y < vh - 40);
        let lastHitTag = 'none';
        for (const doc of getAllDocs()) {
          for (const py of probeYs) {
            for (const px of probeXs) {
              let hit = null;
              try { hit = doc.elementFromPoint(px, py); } catch (_) {}
              if (!hit) continue;
              lastHitTag = `${hit.tagName}@${Math.round(px)},${Math.round(py)}`;
              const chain = [hit, hit.parentElement, hit.parentElement?.parentElement, hit.closest?.('button, a, [role="button"]')].filter(Boolean);
              for (const node of chain) {
                if (tried.has(node)) continue;
                const nr = node.getBoundingClientRect();
                if (nr.width > vw * 0.44 || nr.height > 110 || nr.top < minY - 12) continue;
                tried.add(node);
                await clickEl(node);
                for (let w = 0; w < 6; w++) {
                  await sleep(160);
                  form = findActiveAppendixForm();
                  if (form) return { form, diag: `probe-${lastHitTag}` };
                }
              }
            }
          }
        }
        return { form: null, diag: `vw=${Math.round(vw)} baseY=${Math.round(baseTop)} cand=${candidates.length} last=${lastHitTag}` };
      }

      function findHeadingRowByTextOrIndex(headingText, headingIndex) {
        const vw = window.innerWidth || 1024;
        const targetText = String(headingText || '').trim().toUpperCase();

        const allRows = [];
        const seenRows = new Set();
        for (const el of queryAllAcrossDocs('div, li, tr, mat-expansion-panel-header, button, a, p, span, h5, h6')) {
          if (!isVisible(el)) continue;
          const r = el.getBoundingClientRect();
          if (r.left > vw * 0.44 || r.width < 40 || r.height > 120) continue;
          const txt = (el.innerText || '').trim().toUpperCase();
          if (!txt || txt.includes('NO APPENDIX ADDED') || txt.includes('ADD APPENDIX/DESCRIPTION') || txt.includes('VB-G RAM G TOTAL')) continue;

          if (txt.includes('ANALYSIS OF RATES') || (targetText.length >= 3 && txt.includes(targetText))) {
            // Walk up to the FULL-WIDTH heading header bar (>= 30% of viewport width) so it includes [⊕, Edit, Trash] on the right!
            let row = el;
            for (let step = 0; step < 7 && row.parentElement; step++) {
              const curR = row.getBoundingClientRect();
              const pr = row.parentElement.getBoundingClientRect();
              if (curR.width >= vw * 0.30 && curR.height <= 115) {
                break;
              }
              if (pr.width <= vw * 0.46 && pr.height <= 125) {
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
          return !allRows.some((other) => other !== row && row.contains(other) && other.getBoundingClientRect().width >= vw * 0.30);
        });

        filtered.sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top);

        if (targetText.length >= 3) {
          const exact = filtered.find((r) => (r.innerText || '').toUpperCase().includes(targetText));
          if (exact) return exact;
          const prefix14 = targetText.slice(0, 14).trim();
          if (prefix14.length >= 6) {
            const prefMatch = filtered.find((r) => (r.innerText || '').toUpperCase().includes(prefix14));
            if (prefMatch) return prefMatch;
          }
        }
        return filtered[headingIndex] || filtered[filtered.length - 1] || null;
      }

      function findAddItemCandidatesInRow(row) {
        if (!row) return [];
        const rowRect = row.getBoundingClientRect();
        // The (i) info icon is on the left (~30-45% of row width).
        // The action buttons [⊕ Add Item, ✎ Edit, 🗑 Delete] are ALWAYS on the RIGHT half (> 55% of row width).
        // The collapse chevron (v) is at the far right edge (> rowRect.right - 26).
        const minLeft = rowRect.left + rowRect.width * 0.55;
        const maxRight = rowRect.right - 22;

        const out = [];
        const seen = new Set();
        const addCand = (el) => {
          // NEVER walk up to a wide accordion header (<mat-expansion-panel-header role="button">)!
          const smallParent = el.closest('button, a');
          const target = (smallParent && smallParent.getBoundingClientRect().width <= 56 && smallParent.getBoundingClientRect().height <= 56)
            ? smallParent
            : el;
          if (!target || seen.has(target)) return;
          const tr = target.getBoundingClientRect();
          if (tr.width > 64 || tr.height > 64) return;
          seen.add(target);
          out.push(target);
        };

        // 1. Explicit plus/add icons strictly in the right half
        for (const el of row.querySelectorAll('.fa-plus, .fa-plus-circle, .fa-circle-plus, .bi-plus, .bi-plus-circle, [title*="Add" i], [aria-label*="Add" i]')) {
          if (!isVisible(el)) continue;
          const r = el.getBoundingClientRect();
          if (r.left >= minLeft && r.right <= rowRect.right - 10) {
            addCand(el);
          }
        }

        // 2. Geometric action-cluster scan: leftmost small icon in [55% .. right-22px] = ⊕ (before Edit pencil & Delete trash)
        const icons = Array.from(row.querySelectorAll('button, a, svg, i, img, mat-icon, fa-icon, span, [role="button"]'))
          .filter((el) => {
            if (!isVisible(el)) return false;
            const r = el.getBoundingClientRect();
            if (r.width < 10 || r.width > 44 || r.height < 10 || r.height > 44) return false;
            if (r.left < minLeft || r.right > maxRight) return false;
            // NEVER pick 'See more' or '₹ 38435.87' text spans/links — the ⊕ icon has zero text (or just '+')!
            const rawTxt = (el.innerText || '').trim();
            if (rawTxt.length > 1) return false;
            const win = el.ownerDocument?.defaultView || window;
            const clickable = ['BUTTON', 'A', 'SVG', 'I', 'IMG', 'MAT-ICON', 'FA-ICON'].includes(el.tagName)
              || el.getAttribute('role') === 'button'
              || win.getComputedStyle(el).cursor === 'pointer';
            if (!clickable) return false;
            const cls = typeof el.className === 'string' ? el.className : (el.className?.baseVal || '');
            const meta = `${cls} ${el.getAttribute('title') || ''} ${el.getAttribute('aria-label') || ''}`.toLowerCase();
            if (meta.includes('info') || meta.includes('exclamation') || meta.includes('trash') || meta.includes('delete') || meta.includes('edit') || meta.includes('pencil') || meta.includes('chevron') || meta.includes('angle') || meta.includes('caret') || meta.includes('down') || meta.includes('up')) {
              return false;
            }
            return true;
          })
          .sort((a, b) => a.getBoundingClientRect().left - b.getBoundingClientRect().left);

        for (const ic of icons) addCand(ic);
        return out;
      }

      function findAddItemButtonInRow(row) {
        const cands = findAddItemCandidatesInRow(row);
        return cands.length > 0 ? cands[0] : null;
      }

      async function addHeading(headingText) {
        await dismissSwalIfAny();
        const opened = await openAddAppendixForm();
        const form = opened && opened.form;
        if (!form) {
          return { ok: false, message: `Could not open "Add Appendix/Description" (${opened?.diag || ''}). Tap the stacked-layers + icon once, then press Resume.` };
        }

        const checkboxes = Array.from(form.querySelectorAll('input[type="checkbox"]'))
          .filter((cb) => !!getCheckboxTarget(cb))
          .sort((a, b) => getCheckboxTarget(a).getBoundingClientRect().top - getCheckboxTarget(b).getBoundingClientRect().top);

        if (checkboxes.length >= 1 && !checkboxes[0].checked) {
          await clickEl(getCheckboxTarget(checkboxes[0]));
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
        setNativeValue(headInput, sanitizeSecureDesc(headingText, 120) || 'HEADING');
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

      async function selectHybridDropdown({ panelSide, triggerMatchers, optionMatcher, root = null }) {
        const vw = window.innerWidth || 1024;
        const vh = window.innerHeight || 768;
        const inPanel = (r) => {
          if (panelSide === 'right') return r.left > vw * 0.36;
          if (panelSide === 'left') return r.left < vw * 0.48;
          return true;
        };

        const applyNativeSelect = async (sel) => {
          const opts = Array.from(sel.options || []);
          const chosen = opts.find((o) => optionMatcher((o.text || o.label || '').trim()));
          if (!chosen) return null;
          try { sel.scrollIntoView({ behavior: 'instant', block: 'center' }); } catch (_) {}
          await moveCursorAndRipple(sel);
          sel.selectedIndex = chosen.index;
          sel.value = chosen.value;
          sel.dispatchEvent(new Event('input', { bubbles: true }));
          sel.dispatchEvent(new Event('change', { bubbles: true }));
          sel.dispatchEvent(new Event('blur', { bubbles: true }));
          await waitForPortalIdle(950, 15000);
          return { ok: true, selectedText: (chosen.text || '').trim(), mode: 'native-select' };
        };

        // Wait up to 3.2s for the dropdown & its options to finish loading from SECURE API
        for (let attempt = 0; attempt < 12; attempt++) {
          // 1. Native <select> check (including Shadow DOM / Angular <select>)
          const nativeSelects = (root ? Array.from(root.querySelectorAll('select')) : queryAllAcrossDocs('select'))
            .filter((s) => isVisible(s) && !s.disabled && inPanel(s.getBoundingClientRect()));
          for (const sel of nativeSelects) {
            if ((sel.options || []).length > 1) {
              const allTxt = Array.from(sel.options).map((o) => o.text || '').join(' ').toLowerCase();
              if (triggerMatchers.some((re) => re.test(allTxt)) || nativeSelects.length === 1) {
                const res = await applyNativeSelect(sel);
                if (res) return res;
              }
            }
          }

          // 2. Custom Angular / Material / ng-select / input / button dropdown trigger
          const getElLabel = (el) => {
            if (el.tagName === 'SELECT') {
              const opt = el.options && el.options[el.selectedIndex];
              return ((opt && opt.text) || '').trim();
            }
            if (el.tagName === 'INPUT') {
              return (el.value || el.placeholder || el.getAttribute('aria-label') || '').trim();
            }
            return (el.innerText || el.textContent || el.getAttribute('aria-label') || '').trim();
          };

          // Find vertical band of 'Specification / Activity' when targeting the right panel
          let specBandMinY = 0;
          let specBandMaxY = vh * 0.65;
          if (panelSide === 'right') {
            for (const n of queryAllAcrossDocs('h4, h5, h6, div, span, p, label')) {
              if (!isVisible(n)) continue;
              const nt = (n.textContent || '').trim();
              if (nt.length < 40 && nt.toLowerCase().includes('specification / activity')) {
                const sr = n.getBoundingClientRect();
                if (sr.left > vw * 0.36 && sr.height < 60) {
                  specBandMinY = Math.max(0, sr.top - 30);
                  specBandMaxY = sr.bottom + 70;
                  break;
                }
              }
            }
          }

          const triggerCandidates = (root
            ? Array.from(root.querySelectorAll('input, select, mat-select, ng-select, p-dropdown, [role="combobox"], [role="listbox"], button, div, span'))
            : queryAllAcrossDocs('input, select, mat-select, ng-select, p-dropdown, [role="combobox"], [role="listbox"], button, div, span')
          ).filter((el) => {
            if (!isVisible(el) || el.disabled) return false;
            const r = el.getBoundingClientRect();
            if (!inPanel(r) || r.width < 110 || r.height < 20 || r.height > 72) return false;
            if (r.top < specBandMinY || r.top > specBandMaxY) return false;
            const t = getElLabel(el);
            if (t.length === 0 || t.length > 90) return false;
            return triggerMatchers.some((re) => re.test(t));
          }).sort((a, b) => {
            // Prefer exact 'Select Sub Head' / 'MGNREGA' / 'Select Lump sum' matches first, then smallest box
            const ta = getElLabel(a).toLowerCase();
            const tb = getElLabel(b).toLowerCase();
            const pa = (ta.includes('select sub head') || ta.includes('mgnrega') || ta.includes('select lump')) ? 0 : 1;
            const pb = (tb.includes('select sub head') || tb.includes('mgnrega') || tb.includes('select lump')) ? 0 : 1;
            if (pa !== pb) return pa - pb;
            return (a.getBoundingClientRect().width * a.getBoundingClientRect().height) - (b.getBoundingClientRect().width * b.getBoundingClientRect().height);
          });

          // 3. Direct coordinate anchor for Right Panel '-- Select Sub Head Type --' (same row as 'Specification / Activity')
          if (triggerCandidates.length === 0 && panelSide === 'right') {
            for (const n of queryAllAcrossDocs('h4, h5, h6, div, span, p, label')) {
              if (!isVisible(n)) continue;
              const t = (n.textContent || '').trim();
              if (t.length < 40 && t.toLowerCase().includes('specification / activity')) {
                const sr = n.getBoundingClientRect();
                if (sr.left > vw * 0.36 && sr.height < 60) {
                  const hit = (n.ownerDocument || document).elementFromPoint(vw * 0.74, sr.top + sr.height / 2);
                  if (hit) {
                    const wrap = hit.closest('select, input, mat-select, ng-select, p-dropdown, button, [role="combobox"]') || hit;
                    if (wrap.tagName === 'SELECT' && (wrap.options || []).length > 1) {
                      const res = await applyNativeSelect(wrap);
                      if (res) return res;
                    }
                    triggerCandidates.push(wrap);
                  }
                }
                break;
              }
            }
          }

          if (triggerCandidates.length > 0) {
            const trigger = triggerCandidates[0];
            if (trigger.tagName === 'SELECT') {
              if ((trigger.options || []).length > 1) {
                const res = await applyNativeSelect(trigger);
                if (res) return res;
              }
              await sleep(260);
              continue;
            }

            const currentTxt = getElLabel(trigger);
            if (optionMatcher(currentTxt)) {
              return { ok: true, selectedText: currentTxt, mode: 'already-selected' };
            }

            // Click the custom dropdown trigger to open its popup list
            await clickEl(trigger);
            await sleep(420);

            const findMatchingOption = () => {
              const optNodes = queryAllAcrossDocs('mat-option, [role="option"], .ng-option, .p-dropdown-item, .dropdown-item, li, div, span, a, p')
                .filter((el) => {
                  if (!isVisible(el) || el === trigger || trigger.contains(el)) return false;
                  const r = el.getBoundingClientRect();
                  if (!inPanel(r) || r.height < 16 || r.height > 70 || r.width < 80) return false;
                  const t = (el.innerText || el.textContent || '').trim();
                  if (t.length === 0 || t.length > 110) return false;
                  return optionMatcher(t);
                })
                .sort((a, b) => (a.getBoundingClientRect().width * a.getBoundingClientRect().height) - (b.getBoundingClientRect().width * b.getBoundingClientRect().height));
              return optNodes[0] || null;
            };

            let optEl = findMatchingOption();

            // Scroll open dropdown list down to the bottom (where 54 - MGNREGA Bihar Data- TM & Data live)
            if (!optEl) {
              const scrollables = queryAllAcrossDocs('.cdk-overlay-pane, .mat-select-panel, .mat-mdc-select-panel, .ng-dropdown-panel-items, .dropdown-menu, ul, div')
                .filter((el) => {
                  if (!isVisible(el)) return false;
                  const r = el.getBoundingClientRect();
                  if (!inPanel(r) || r.height < 55) return false;
                  return el.scrollHeight > el.clientHeight + 15;
                });
              for (const sc of scrollables) {
                for (let step = 1; step <= 6; step++) {
                  sc.scrollTop = Math.round((sc.scrollHeight * step) / 6);
                  sc.dispatchEvent(new Event('scroll', { bubbles: true }));
                  await sleep(160);
                  optEl = findMatchingOption();
                  if (optEl) break;
                }
                if (optEl) break;
              }
            }

            if (optEl) {
              try { optEl.scrollIntoView({ behavior: 'instant', block: 'center' }); } catch (_) {}
              await sleep(140);
              await clickEl(optEl);
              await waitForPortalIdle(950, 15000);
              return { ok: true, selectedText: (optEl.innerText || optEl.textContent || '').trim(), mode: 'custom-dropdown' };
            }

            return { ok: false, message: `Opened ${trigger.tagName} (${currentTxt.slice(0, 24)}) but target option not found` };
          }

          await sleep(260);
        }

        // X-ray diagnostic if still not found
        let diag = 'none';
        try {
          const sels = queryAllAcrossDocs('select').filter((s) => isVisible(s));
          diag = `selects=${sels.length} [` + sels.map((s) => `${Math.round(s.getBoundingClientRect().left)}:${(s.options||[]).length}`).join(',') + ']';
        } catch (_) {}
        return { ok: false, message: `Dropdown trigger not found (${diag})` };
      }

      function findSearchButtonNear(searchBox) {
        if (!searchBox) return null;
        const sb = searchBox.getBoundingClientRect();
        // 1. Check sibling/input-group button immediately to the right of searchBox (cyan magnifier icon button)
        const parent = searchBox.parentElement;
        if (parent) {
          const nearBtns = Array.from(parent.querySelectorAll('button, a, span, i, svg, [role="button"]'))
            .filter((el) => {
              if (el === searchBox || !isVisible(el)) return false;
              const r = el.getBoundingClientRect();
              return r.left >= sb.right - 12 && r.left <= sb.right + 110 && Math.abs((r.top + r.height / 2) - (sb.top + sb.height / 2)) <= 32;
            })
            .sort((a, b) => a.getBoundingClientRect().left - b.getBoundingClientRect().left);
          if (nearBtns.length > 0) {
            const b = nearBtns[0].closest('button, a');
            return (b && b.getBoundingClientRect().width <= 120) ? b : nearBtns[0];
          }
        }
        // 2. Global geometric scan right next to searchBox
        const allBtns = queryAllAcrossDocs('button, a.btn, [role="button"], i.fa-search, .fa-magnifying-glass, .bi-search')
          .filter((el) => {
            if (!isVisible(el) || el.disabled) return false;
            const r = el.getBoundingClientRect();
            return r.left >= sb.right - 12 && r.left <= sb.right + 110 && Math.abs((r.top + r.height / 2) - (sb.top + sb.height / 2)) <= 34;
          })
          .sort((a, b) => a.getBoundingClientRect().left - b.getBoundingClientRect().left);
        if (allBtns.length > 0) {
          const b = allBtns[0].closest('button, a');
          return (b && b.getBoundingClientRect().width <= 120) ? b : allBtns[0];
        }
        return findRightPanelButtonByText([/search/i, /find/i, /^go$/i]);
      }

      async function addItem(headingIndex, headingText, code, isTM) {
        await dismissSwalIfAny();
        const row = findHeadingRowByTextOrIndex(headingText, headingIndex);
        if (!row) {
          return { ok: false, message: `Heading "${headingText}" (#${headingIndex + 1}) not found in left panel.` };
        }
        // CRITICAL: Always scroll heading into view first (fixes Heading 9/10+ off-screen after Delete!)
        try { row.scrollIntoView({ behavior: 'instant', block: 'center' }); } catch (_) {}
        await sleep(180);

        const vw = window.innerWidth || 1024;
        const findRightSearchBox = () => {
          const searchInputs = queryAllAcrossDocs('input[type="text"], input[type="search"], input:not([type])')
            .filter((el) => isVisible(el) && !el.disabled && !el.readOnly && el.getBoundingClientRect().left > vw * 0.38);
          return searchInputs.find((el) => {
            const meta = `${el.placeholder || ''} ${el.name || ''} ${el.id || ''}`.toLowerCase();
            return meta.includes('spec') || meta.includes('search') || meta.includes('code') || meta.includes('activity') || meta.includes('item');
          }) || searchInputs[0] || null;
        };

        const plusCands = findAddItemCandidatesInRow(row);
        const rr = row.getBoundingClientRect();
        for (const frac of [0.83, 0.80, 0.86, 0.76, 0.73]) {
          const px = rr.left + rr.width * frac;
          const py = rr.top + Math.min(rr.height * 0.5, 28);
          try {
            const hit = (row.ownerDocument || document).elementFromPoint(px, py);
            if (hit && !plusCands.includes(hit)) {
              const hr = hit.getBoundingClientRect();
              const ht = (hit.innerText || '').trim();
              if (hr.width <= 48 && hr.height <= 48 && ht.length <= 1) plusCands.push(hit);
            }
          } catch (_) {}
        }

        if (plusCands.length === 0) {
          return { ok: false, message: `Could not find ⊕ Add Item button on heading "${headingText}".` };
        }

        let searchBox = null;
        for (const cand of plusCands.slice(0, 5)) {
          await clickEl(cand);
          await waitForPortalIdle(550, 10000);
          for (let w = 0; w < 6; w++) {
            searchBox = findRightSearchBox();
            if (searchBox) break;
            await sleep(180);
          }
          if (searchBox) break;
        }
        if (!searchBox) {
          return { ok: false, message: `Could not open Specification/Activity from ⊕ on "${headingText}".` };
        }

        // Select the right Sub Head Type (handles BOTH custom dropdown and native <select>!)
        const chapter = String(code).split('.')[0].trim();
        const subheadRes = await selectHybridDropdown({
          panelSide: 'right',
          triggerMatchers: [/select\s*sub\s*head/i, /sub\s*head/i, /mgnrega/i, /^\s*\d{1,2}\s*-\s*[A-Za-z]{3,}/i],
          optionMatcher: (txt) => {
            const up = txt.toUpperCase();
            if (up.includes('SELECT SUB HEAD')) return false;
            if (isTM) {
              return up.includes('54') && (up.includes('TM') || up.includes('DATA-TM') || up.includes('DATA- TM'));
            }
            if (chapter === '54') {
              return up.includes('54') && !up.includes('TM') && (up.includes('BIHAR') || up.includes('MGNREGA'));
            }
            return up.startsWith(chapter + ' -') || up.startsWith(chapter + '-');
          }
        });
        if (!subheadRes.ok) {
          return { ok: false, message: `Could not select Sub Head Type for ${code} (${subheadRes.message}).` };
        }

        if (!searchBox) searchBox = findRightSearchBox();
        if (!searchBox) {
          return { ok: false, message: `Specification/Activity search box not found for ${code}.` };
        }
        try { searchBox.scrollIntoView({ behavior: 'instant', block: 'center' }); } catch (_) {}
        await moveCursorAndRipple(searchBox);
        setNativeValue(searchBox, code);
        try { searchBox.dispatchEvent(new KeyboardEvent('keyup', { key: 'Enter', code: 'Enter', bubbles: true })); } catch (_) {}
        await sleep(250);

        // Click the cyan magnifier search button right next to the search box
        const searchBtn = findSearchButtonNear(searchBox);
        if (searchBtn) {
          await clickEl(searchBtn);
          await waitForPortalIdle(850, 15000);
        }

        const codeUpper = String(code).trim().toUpperCase();
        const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const exactCodeRe = new RegExp('(^|[^A-Z0-9.])' + escapeRe(codeUpper) + '($|[^A-Z0-9.])');

        let matchedRow = null;
        let matchedChk = null;
        for (let w = 0; w < 12; w++) {
          // ONLY inspect actual table rows (tr) — NEVER outer wrapper divs that contain hidden rows!
          const trs = queryAllAcrossDocs('table tbody tr, tr')
            .filter((r) => {
              if (!isVisible(r)) return false;
              const rr = r.getBoundingClientRect();
              if (rr.left <= vw * 0.35 || rr.height < 24 || rr.height > 750) return false;
              const cb = r.querySelector('input[type="checkbox"]');
              const target = getCheckboxTarget(cb);
              if (!cb || !target) return false;
              const cr = target.getBoundingClientRect();
              return cr.left > vw * 0.35 && cr.top > 80 && cr.width > 4 && cr.height > 4;
            })
            .sort((a, b) => a.getBoundingClientRect().height - b.getBoundingClientRect().height);

          // Exact code match first (e.g. 54.1.1A never collides with 54.1.1)
          matchedRow = trs.find((r) => {
            const cells = Array.from(r.querySelectorAll('td')).map((td) => (td.innerText || '').trim().toUpperCase());
            return cells.some((c) => c === codeUpper) || exactCodeRe.test((r.innerText || '').toUpperCase());
          });
          if (!matchedRow) {
            matchedRow = trs.find((r) => (r.innerText || '').toUpperCase().includes(codeUpper));
          }
          if (matchedRow) {
            matchedChk = matchedRow.querySelector('input[type="checkbox"]');
            break;
          }
          await sleep(250);
        }

        if (!matchedRow || !matchedChk) {
          const cancelBtn = findRightPanelButtonByText([/cancel/i, /close/i]);
          if (cancelBtn) await clickEl(cancelBtn);
          await sleep(300);
          return { ok: true, skipped: true, message: `Code ${code} not in search results (already present). Closed cleanly.` };
        }

        const chkTarget = getCheckboxTarget(matchedChk) || matchedChk;
        if (!matchedChk.checked) {
          await clickEl(chkTarget);
          await sleep(260);
        }
        if (!matchedChk.checked) {
          // Secondary fallback if custom label absorbed the click
          await clickEl(matchedChk);
          await sleep(220);
        }

        const saveSpecBtn = findRightPanelButtonByText([/^save$/i, /save/i, /add\s*selected/i, /add\s*item/i, /^add$/i, /submit/i]);
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
        const vw = window.innerWidth || 1024;
        const row = findHeadingRowByTextOrIndex(headingText, headingIndex);
        if (!row) {
          return { ok: false, message: `Heading "${headingText}" not found for measurements of ${code}.` };
        }
        try { row.scrollIntoView({ behavior: 'instant', block: 'center' }); } catch (_) {}
        await sleep(140);

        const escapeReM = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const codeUpperM = String(code).trim().toUpperCase();
        const exactItemRe = new RegExp('(^|[^A-Z0-9.])' + escapeReM(codeUpperM) + '($|[^A-Z0-9.])');

        const findItemRow = () => {
          const container = row.parentElement?.parentElement || row.parentElement || document;
          const nodes = Array.from(container.querySelectorAll('div, tr, li'))
            .filter((n) => {
              if (!isVisible(n)) return false;
              const r = n.getBoundingClientRect();
              if (r.left > vw * 0.44 || r.height > 120 || r.height < 18) return false;
              const t = (n.innerText || '').toUpperCase();
              return exactItemRe.test(t) && !t.includes('ANALYSIS OF RATES');
            })
            .sort((a, b) => (a.getBoundingClientRect().width * a.getBoundingClientRect().height) - (b.getBoundingClientRect().width * b.getBoundingClientRect().height));
          if (nodes.length > 0) {
            let itemEl = nodes[0];
            for (let s = 0; s < 5 && itemEl.parentElement; s++) {
              const ir = itemEl.getBoundingClientRect();
              const pr = itemEl.parentElement.getBoundingClientRect();
              if (ir.width >= vw * 0.28 && ir.height <= 110) break;
              if (pr.width <= vw * 0.45 && pr.height <= 115) itemEl = itemEl.parentElement;
              else break;
            }
            return itemEl;
          }
          return null;
        };

        let itemNode = findItemRow();
        if (!itemNode) {
          await clickEl(row);
          await sleep(500);
          itemNode = findItemRow();
        }
        if (itemNode) {
          const ir = itemNode.getBoundingClientRect();
          const itemIcons = Array.from(itemNode.querySelectorAll('button, a, svg, i, img, mat-icon, fa-icon, span'))
            .filter((el) => {
              if (!isVisible(el)) return false;
              const r = el.getBoundingClientRect();
              if (r.width < 10 || r.width > 44 || r.height < 10 || r.height > 44) return false;
              if (r.left < ir.left + ir.width * 0.55) return false;
              const cls = typeof el.className === 'string' ? el.className : (el.className?.baseVal || '');
              const meta = `${cls} ${el.getAttribute('title') || ''}`.toLowerCase();
              if (meta.includes('trash') || meta.includes('delete')) return false;
              return true;
            })
            .sort((a, b) => a.getBoundingClientRect().left - b.getBoundingClientRect().left);
          let measBtn = itemIcons[0] || itemNode;
          const smallBtn = measBtn.closest?.('button, a');
          if (smallBtn && smallBtn.getBoundingClientRect().width <= 56) measBtn = smallBtn;
          await clickEl(measBtn);
          await waitForPortalIdle(800, 15000);
        }

        const getMeasRows = () => {
          // 1. Standard HTML table rows with >= 4 inputs on right panel
          const trs = queryAllAcrossDocs('table tbody tr, tr').filter((tr) => {
            if (!isVisible(tr) || tr.getBoundingClientRect().left <= vw * 0.35) return false;
            const inps = tr.querySelectorAll('input:not([type="hidden"]):not([type="checkbox"]), textarea');
            return inps.length >= 4;
          });
          if (trs.length > 0) return trs;
          // 2. Flex/grid div rows with >= 4 inputs on right panel
          const divs = queryAllAcrossDocs('div.row, div[class*="row"], form div').filter((d) => {
            if (!isVisible(d)) return false;
            const r = d.getBoundingClientRect();
            if (r.left <= vw * 0.35 || r.height < 28 || r.height > 110) return false;
            const inps = d.querySelectorAll('input:not([type="hidden"]):not([type="checkbox"]), textarea');
            return inps.length >= 4 && inps.length <= 10;
          });
          return divs;
        };

        const waitForRightBtn = async (patterns, maxChecks = 12) => {
          for (let i = 0; i < maxChecks; i++) {
            const b = findRightPanelButtonByText(patterns);
            if (b) return b;
            await sleep(220);
          }
          return null;
        };

        const fillBatch = async (batchRows, isDeductionBatch) => {
          if (batchRows.length === 0) return { ok: true };

          // Open the Measurement or Deduction form via 'Add Measurements +' or 'Add Deduction +'
          let trs = getMeasRows();
          if (trs.length === 0) {
            const openPatterns = isDeductionBatch
              ? [/add\s*deduction/i, /deduction/i]
              : [/add\s*measurement/i, /measurement/i];
            const openBtn = await waitForRightBtn(openPatterns, 14);
            if (!openBtn) {
              return { ok: false, message: `${isDeductionBatch ? 'Add Deduction +' : 'Add Measurements +'} button not found for ${code}.` };
            }
            await clickEl(openBtn);
            await waitForPortalIdle(500, 12000);
            for (let w = 0; w < 12; w++) {
              trs = getMeasRows();
              if (trs.length > 0) break;
              await sleep(220);
            }
          }

          if (trs.length === 0) {
            return { ok: false, message: `Measurement table did not open for ${code}.` };
          }

          // Optional Head Description for Deduction batch
          if (isDeductionBatch) {
            const headDesc = queryAllAcrossDocs('input[type="text"], input:not([type]), textarea')
              .find((el) => {
                if (!isVisible(el) || el.disabled || el.readOnly) return false;
                const r = el.getBoundingClientRect();
                if (r.left <= vw * 0.35 || el.closest('table, tr')) return false;
                const meta = `${el.placeholder || ''} ${el.name || ''} ${el.id || ''} ${el.parentElement?.innerText || ''}`.toLowerCase();
                return meta.includes('head') && meta.includes('desc');
              });
            if (headDesc && !headDesc.value) {
              setNativeValue(headDesc, 'Deduction');
              await sleep(100);
            }
          }

          for (let rIdx = 0; rIdx < batchRows.length; rIdx++) {
            const rData = batchRows[rIdx];
            trs = getMeasRows();

            if (rIdx > 0) {
              await dismissSwalIfAny();
              // Click the cyan '+' button in the Add/Remove column of the last row (retry once if row count didn't increment)
              const prevCount = trs.length;
              for (let tryAdd = 0; tryAdd < 2; tryAdd++) {
                trs = getMeasRows();
                if (trs.length > prevCount) break;
                const lastTr = trs[trs.length - 1];
                if (!lastTr) break;
                const rowButtons = Array.from(lastTr.querySelectorAll('button, a, .btn, span, i, svg'))
                  .filter((el) => {
                    if (!isVisible(el)) return false;
                    const r = el.getBoundingClientRect();
                    return r.width >= 14 && r.width <= 60 && r.height >= 14 && r.height <= 48 && r.left > vw * 0.80;
                  });
                let rowPlus = rowButtons.find((el) => {
                  const cls = typeof el.className === 'string' ? el.className : (el.className?.baseVal || '');
                  const txt = (el.innerText || '').trim();
                  const low = `${cls} ${el.getAttribute('title') || ''}`.toLowerCase();
                  return txt === '+' || low.includes('plus') || low.includes('info') || low.includes('primary') || low.includes('add');
                });
                if (!rowPlus && rowButtons.length >= 2) {
                  rowButtons.sort((a, b) => b.getBoundingClientRect().top - a.getBoundingClientRect().top);
                  rowPlus = rowButtons[0];
                }
                if (rowPlus) {
                  const smallP = rowPlus.closest('button, a');
                  await clickEl((smallP && smallP.getBoundingClientRect().width <= 64) ? smallP : rowPlus);
                  for (let w = 0; w < 8; w++) {
                    await sleep(180);
                    trs = getMeasRows();
                    if (trs.length > prevCount) break;
                  }
                }
              }
              if (trs.length <= prevCount) {
                return { ok: false, message: `Could not append measurement row ${rIdx + 1} for ${code}.` };
              }
            }

            const targetTr = trs[trs.length - 1];
            if (!targetTr) {
              return { ok: false, message: `Measurement input row not found for ${code} (row ${rIdx + 1}).` };
            }
            const inputs = Array.from(targetTr.querySelectorAll('input:not([type="hidden"]):not([type="checkbox"]), textarea'))
              .filter((el) => isVisible(el) && !el.disabled && !el.readOnly);

            // Sanitize Item Description strictly to SECURE v2's allowed characters: A-Z a-z 0-9 space . + - * ( ) /
            const cleanDesc = sanitizeSecureDesc(rData.desc || 'Item', 95) || 'Item';
            // Exact SECURE v2 columns: [0]=Item Description, [1]=No, [2]=L/D/A, [3]=B/B, [4]=D/C, [5]=Cf
            const values = [cleanDesc, rData.no || '1', rData.l || '', rData.b || '', rData.d || '', rData.cf || ''];
            for (let ci = 0; ci < Math.min(inputs.length, values.length); ci++) {
              if (values[ci] !== '') {
                setNativeValue(inputs[ci], values[ci]);
                await sleep(65);
              }
            }
            await dismissSwalIfAny();
          }

          await sleep(160);
          await dismissSwalIfAny();
          const saveBtn = await waitForRightBtn([/save\s*measurement/i, /^save$/i, /update/i], 10);
          if (!saveBtn) {
            return { ok: false, message: `Save Measurements button not found for ${code}.` };
          }
          await clickEl(saveBtn);
          await waitForPortalIdle(1000, 20000);
          await dismissSwalIfAny();
          blurKeyboard();
          return { ok: true };
        };

        const normalRows = rowsData.filter((r) => !r.isDeduction);
        const deductionRows = rowsData.filter((r) => !!r.isDeduction);

        if (normalRows.length > 0) {
          const res1 = await fillBatch(normalRows, false);
          if (!res1.ok) return res1;
        }
        if (deductionRows.length > 0) {
          const res2 = await fillBatch(deductionRows, true);
          if (!res2.ok) return res2;
        }
        return { ok: true, message: `Saved ${rowsData.length} measurement row(s) for ${code}` };
      }

      async function addLumpSum(keyword, customDesc, amount) {
        await dismissSwalIfAny();
        const opened = await openAddAppendixForm();
        const form = opened && opened.form;
        if (!form) {
          return { ok: false, message: `Could not open Add Appendix/Description for Lump Sum (${opened?.diag || ''}).` };
        }

        const checkboxes = Array.from(form.querySelectorAll('input[type="checkbox"]'))
          .filter((cb) => !!getCheckboxTarget(cb))
          .sort((a, b) => getCheckboxTarget(a).getBoundingClientRect().top - getCheckboxTarget(b).getBoundingClientRect().top);

        let lumpChk = checkboxes.find((cb) => {
          const labelTxt = (cb.closest('label, mat-checkbox, .form-check')?.innerText || cb.parentElement?.innerText || '').toLowerCase();
          return labelTxt.includes('lump') && !labelTxt.includes('heading');
        }) || (checkboxes.length >= 2 ? checkboxes[checkboxes.length - 1] : checkboxes[0]);

        if (lumpChk && !lumpChk.checked) {
          await clickEl(getCheckboxTarget(lumpChk));
          await sleep(450);
        }

        const kwLow = String(keyword || 'Miscellaneous').toLowerCase();
        const lumpRes = await selectHybridDropdown({
          panelSide: 'left',
          root: form,
          triggerMatchers: [/select\s*lump\s*sum/i, /conveyance/i, /miscellaneous/i, /display\s*board/i, /gst/i, /labour/i, /quality/i, /worksite/i],
          optionMatcher: (txt) => {
            const low = txt.toLowerCase();
            if (low.includes('select lump sum') || low === 'lump sum type' || low.includes('lump sum description')) return false;
            if (kwLow === 'display' || kwLow === 'display board') {
              return low.includes('display') || low.includes('cib');
            }
            if (kwLow === 'bf') {
              return low.includes('bft') || low.includes('bf/t');
            }
            return low.includes(kwLow);
          }
        });
        if (!lumpRes.ok) {
          const fallbackRes = await selectHybridDropdown({
            panelSide: 'left',
            root: form,
            triggerMatchers: [/select\s*lump\s*sum/i],
            optionMatcher: (txt) => txt.toLowerCase().includes('miscellaneous')
          });
          if (!fallbackRes.ok) {
            return { ok: false, message: `Lump sum Type dropdown not selected (${lumpRes.message}).` };
          }
        }

        const inputs = Array.from(form.querySelectorAll('input[type="text"], input[type="number"], input:not([type]), textarea'))
          .filter((el) => isVisible(el) && !el.disabled && !el.readOnly);
        const descInput = inputs.find((el) => {
          const meta = `${el.placeholder || ''} ${el.name || ''} ${el.id || ''}`.toLowerCase();
          return meta.includes('desc') && !meta.includes('head') && !meta.includes('analysis');
        });
        if (descInput && customDesc) {
          setNativeValue(descInput, sanitizeSecureDesc(customDesc, 95));
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
        const amtNum = Number(amount); setNativeValue(amtInput, Number.isFinite(amtNum) && amtNum % 1 === 0 ? String(Math.round(amtNum)) : String(amount));
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

      async function scrapeCurrentEstimate() {
        const vw = window.innerWidth || 1024;
        const allRows = [];
        const seenRows = new Set();

        for (const el of queryAllAcrossDocs('div, li, tr, mat-expansion-panel-header')) {
          if (!isVisible(el)) continue;
          const r = el.getBoundingClientRect();
          if (r.left > vw * 0.46 || r.width < 120 || r.height > 125) continue;
          const txt = (el.innerText || '').trim();
          if (!txt.includes('Analysis of Rates')) continue;
          if (txt.includes('Add Appendix/Description') || txt.includes('No Appendix Added')) continue;
          let row = el;
          for (let step = 0; step < 6 && row.parentElement; step++) {
            const curR = row.getBoundingClientRect();
            const pr = row.parentElement.getBoundingClientRect();
            if (curR.width >= vw * 0.28 && curR.height <= 120) break;
            if (pr.width <= vw * 0.48 && pr.height <= 125) row = row.parentElement;
            else break;
          }
          if (!seenRows.has(row)) {
            seenRows.add(row);
            allRows.push(row);
          }
        }

        const rows = allRows
          .filter((row) => !allRows.some((other) => other !== row && row.contains(other)))
          .sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top);

        const codeRe = /\b(\d{1,2}(?:\.TM)?(?:\.[A-Za-z0-9]+){2,6})\b/gi;
        const headings = [];

        for (let idx = 0; idx < rows.length; idx++) {
          const row = rows[idx];
          try { row.scrollIntoView({ behavior: 'instant', block: 'center' }); } catch (_) {}
          await sleep(100);

          const getCardContainer = () => row.closest('mat-expansion-panel, .card, .accordion-item, li') || row.parentElement || row;
          let container = getCardContainer();
          let text = container.innerText || '';
          codeRe.lastIndex = 0;

          // If this heading card is collapsed (no SOR codes visible yet), click it to expand so Verify & Fix sees all items!
          if (!codeRe.test(text) && !text.includes('No Specification Added')) {
            await clickEl(row);
            await sleep(480);
            container = getCardContainer();
            text = container.innerText || '';
          }

          const rawTitle = (row.innerText || '').split('\n')[0].replace(/See more.*/i, '').trim();
          const items = [];
          const seenCodes = new Set();
          codeRe.lastIndex = 0;
          // Find every SOR code match and inspect the slice of text between this code and the next code for real Qty & ₹ Amount
          const matches = [];
          let m;
          while ((m = codeRe.exec(text)) !== null) {
            matches.push({ code: m[1].toUpperCase(), index: m.index });
          }
          for (let mi = 0; mi < matches.length; mi++) {
            const c = matches[mi].code;
            if (seenCodes.has(c)) continue;
            seenCodes.add(c);
            const sliceEnd = (mi + 1 < matches.length) ? matches[mi + 1].index : text.length;
            const block = text.slice(matches[mi].index, sliceEnd);
            // Anchor strictly before '@' (e.g. "351.74 metre @ ₹", "726.319 sqm @ ₹", "80.0 no @ ₹") so description numbers like "50 metre" are never matched!
            const qtyM = block.match(/(\d+(?:,\d+)*(?:\.\d+)?)\s*(?:cum|sqm|metre|meter|rmt|kg|no|nos|day|each|ls|mt|qtl)\s*@/i)
              || block.match(/(\d+(?:,\d+)*(?:\.\d+)?)\s*(?:cum|sqm|metre|meter|rmt|kg|no|nos|day|each|ls|mt|qtl)\b/i);
            const qtyVal = qtyM ? parseFloat(qtyM[1].replace(/,/g, '')) : 0;
            // Match final rupee amount in the item block (last ₹ number, not the unit rate after @)
            const rupeeMatches = Array.from(block.matchAll(/₹\s*(\d+(?:,\d+)*(?:\.\d+)?)/g));
            const amtVal = rupeeMatches.length > 0 ? parseFloat(rupeeMatches[rupeeMatches.length - 1][1].replace(/,/g, '')) : 0;
            items.push({ code: c, description: c, quantity: Number.isFinite(qtyVal) ? qtyVal : 0, amount: Number.isFinite(amtVal) ? amtVal : 0 });
          }
          headings.push({ index: idx, text: rawTitle, items });
        }

        hideCursor();

        const lumpSums = [];
        const bodyText = document.body.innerText || '';
        const lumpLines = bodyText.split('\n').filter((l) => /lump\s*sum|conveyance|display board|cess|contingenc|\bgst\b/i.test(l));
        for (const l of lumpLines.slice(0, 12)) {
          const numMatch = l.match(/(\d+(?:,\d+)*(?:\.\d+)?)/);
          lumpSums.push({ description: l.trim(), amount: numMatch ? parseFloat(numMatch[1].replace(/,/g, '')) : 0 });
        }
        return { headings, lumpSums };
      }

      async function deleteItemInHeading(headingIndex, code) {
        await dismissSwalIfAny();
        const vw = window.innerWidth || 1024;
        const row = findHeadingRowByTextOrIndex('', headingIndex);
        if (!row) return { ok: false, message: `Heading #${headingIndex + 1} not found for deletion.` };
        try { row.scrollIntoView({ behavior: 'instant', block: 'center' }); } catch (_) {}
        const getContainer = () => row.closest('mat-expansion-panel, .card, .accordion-item, li') || row.parentElement || row;
        const codeUpper = String(code).trim().toUpperCase();
        const escDel = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const delRe = new RegExp('(^|[^A-Z0-9.])' + escDel(codeUpper) + '($|[^A-Z0-9.])');

        const findItemCard = () => {
          const cont = getContainer();
          const nodes = Array.from(cont.querySelectorAll('div, tr, li'))
            .filter((r) => {
              if (!isVisible(r)) return false;
              const rr = r.getBoundingClientRect();
              if (rr.left > vw * 0.45 || rr.height > 140 || rr.height < 20) return false;
              const t = (r.innerText || '').toUpperCase();
              return delRe.test(t) && !t.includes('ANALYSIS OF RATES');
            })
            .sort((a, b) => (a.getBoundingClientRect().width * a.getBoundingClientRect().height) - (b.getBoundingClientRect().width * b.getBoundingClientRect().height));
          if (nodes.length === 0) return null;
          let itemEl = nodes[0];
          for (let s = 0; s < 5 && itemEl.parentElement; s++) {
            const ir = itemEl.getBoundingClientRect();
            const pr = itemEl.parentElement.getBoundingClientRect();
            if (ir.width >= vw * 0.28 && ir.height <= 125) break;
            if (pr.width <= vw * 0.46 && pr.height <= 130) itemEl = itemEl.parentElement;
            else break;
          }
          return itemEl;
        };

        let itemCard = findItemCard();
        if (!itemCard) {
          await clickEl(row);
          await sleep(450);
          itemCard = findItemCard();
        }
        if (!itemCard) return { ok: false, message: `Item ${code} not found under Heading #${headingIndex + 1} for deletion.` };

        // Click the red trash icon (rightmost small icon inside itemCard)
        let delBtn = itemCard.querySelector('.fa-trash, .fa-trash-alt, .bi-trash, [title*="Delete" i], [aria-label*="Delete" i]');
        if (!delBtn) {
          const ir = itemCard.getBoundingClientRect();
          const icons = Array.from(itemCard.querySelectorAll('button, a, svg, i, img, mat-icon, fa-icon, span'))
            .filter((el) => {
              if (!isVisible(el)) return false;
              const r = el.getBoundingClientRect();
              return r.width >= 10 && r.width <= 44 && r.height >= 10 && r.height <= 44 && r.left > ir.left + ir.width * 0.60;
            })
            .sort((a, b) => b.getBoundingClientRect().left - a.getBoundingClientRect().left);
          delBtn = icons[0] || null;
        }
        if (!delBtn) return { ok: false, message: `Delete trash icon not found for item ${code}.` };
        const smallBtn = delBtn.closest?.('button, a');
        await clickEl((smallBtn && smallBtn.getBoundingClientRect().width <= 56) ? smallBtn : delBtn);
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
      window.__SECURE_AI_IPAD_V24__ = true;
    })();
    """#
}
