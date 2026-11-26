import Foundation

/// JavaScript DOM automation engine tailored directly to the live Bihar SECURE v2 portal
/// (`https://secure.dord.gov.in/securev2/`).
/// - Opens the real "Add Appendix/Description" modal (Heading/Description & Lump sum Type)
/// - Never triggers the iPad on-screen keyboard during automated typing (`blur()` after input)
/// - Waits for SECURE v2's "Loading" indicator before proceeding
/// - Returns `{ ok: false, message: ... }` on any missing control so Swift pauses cleanly instead of skipping steps.
enum SecureAutomationJS {
    static let engineScript: String = #"""
    (function() {
      if (window.__SECURE_AI_IPAD_V2__) return;

      const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

      function isVisible(el) {
        if (!el) return false;
        const style = window.getComputedStyle(el);
        if (style.display === 'none' || style.visibility === 'hidden' || parseFloat(style.opacity) === 0) return false;
        const rect = el.getBoundingClientRect();
        return rect.width > 1 && rect.height > 1;
      }

      function blurKeyboard() {
        try {
          if (document.activeElement && typeof document.activeElement.blur === 'function') {
            document.activeElement.blur();
          }
        } catch (_) {}
      }

      function setNativeValue(el, value) {
        if (!el) return;
        const str = value == null ? '' : String(value);
        const proto = el.tagName === 'TEXTAREA'
          ? window.HTMLTextAreaElement.prototype
          : (el.tagName === 'SELECT' ? window.HTMLSelectElement.prototype : window.HTMLInputElement.prototype);
        const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
        if (setter) setter.call(el, str);
        else el.value = str;
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        el.dispatchEvent(new Event('blur', { bubbles: true }));
        blurKeyboard();
      }

      function clickEl(el) {
        if (!el) return false;
        try { el.scrollIntoView({ behavior: 'instant', block: 'center' }); } catch (_) {}
        el.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
        el.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true }));
        el.click();
        return true;
      }

      function isPortalLoading() {
        const selectors = [
          '.spinner', '.loader', '.loading', '.blockUI', '.ngx-spinner-overlay',
          '.swal2-loading', '[class*="spinner"]', '[class*="loader"]', '#preloader',
          '.mat-progress-bar', '.progress-bar-animated'
        ];
        for (const sel of selectors) {
          for (const n of document.querySelectorAll(sel)) {
            if (isVisible(n)) return true;
          }
        }
        // Check visible "Loading" text badge seen at bottom of SECURE v2
        const spans = document.querySelectorAll('div, span, p');
        for (const s of spans) {
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

      function findButtonByText(patterns, root = document) {
        const regexList = patterns.map((p) => (p instanceof RegExp ? p : new RegExp(p, 'i')));
        const candidates = root.querySelectorAll('button, a.btn, input[type="button"], input[type="submit"], [role="button"], a');
        for (const el of candidates) {
          if (!isVisible(el) || el.disabled) continue;
          const txt = (el.innerText || el.value || el.getAttribute('title') || el.getAttribute('aria-label') || '').trim();
          if (regexList.some((re) => re.test(txt))) return el;
        }
        return null;
      }

      function dismissSwalIfAny() {
        const confirmBtn = document.querySelector('.swal2-confirm, button.confirm');
        if (isVisible(confirmBtn)) {
          const txt = (confirmBtn.innerText || '').trim().toLowerCase();
          if (txt === 'ok' || txt.includes('close')) {
            clickEl(confirmBtn);
            return true;
          }
        }
        return false;
      }

      async function confirmSwalDelete() {
        for (let i = 0; i < 20; i++) {
          const btns = document.querySelectorAll('.swal2-confirm, button.swal2-confirm, button.btn-primary, button');
          for (const b of btns) {
            if (!isVisible(b)) continue;
            const txt = (b.innerText || '').trim().toLowerCase();
            if (txt.includes('yes, delete') || txt.includes('yes delete') || (b.classList.contains('swal2-confirm') && txt.includes('yes'))) {
              clickEl(b);
              await waitForPortalIdle(900, 20000);
              return { ok: true, message: 'Confirmed SweetAlert2 delete' };
            }
          }
          await sleep(180);
        }
        return { ok: false, message: 'SweetAlert2 delete confirmation button not found' };
      }

      function findActiveAppendixModal() {
        // SECURE v2 modal header contains "Add Appendix/Description"
        const containers = document.querySelectorAll('.modal.show, .modal-content, .mat-dialog-container, .p-dialog, [role="dialog"], .card, div');
        for (const el of containers) {
          if (!isVisible(el)) continue;
          const txt = (el.innerText || '');
          if (txt.includes('Add Appendix/Description') && txt.includes('Lump sum Type')) {
            // Prefer the tightest container that still holds the checkboxes and Add button
            const hasAdd = !!findButtonByText([/^add$/i], el);
            const hasChk = el.querySelectorAll('input[type="checkbox"]').length >= 1;
            if (hasAdd && hasChk && el.getBoundingClientRect().width < window.innerWidth * 0.92) {
              return el;
            }
          }
        }
        return null;
      }

      async function openAddAppendixModal() {
        let modal = findActiveAppendixModal();
        if (modal) return modal;

        // 1. Find clickable "Add Appendix" text or stacked-layers '+' icon (works for div/span/img/svg/button)
        const allNodes = Array.from(document.querySelectorAll('button, a, div, span, p, img, svg, i, mat-icon'));
        let trigger = null;

        // Priority A: Exact "Add Appendix" label or its clickable parent card
        for (const n of allNodes) {
          if (!isVisible(n)) continue;
          const t = (n.innerText || n.textContent || '').trim();
          if (/^add\s*appendix$/i.test(t) && n.children.length <= 2) {
            trigger = n.closest('button, a, [role="button"], .cursor-pointer') || n.parentElement || n;
            break;
          }
        }

        // Priority B: Stacked-layers '+' icon button at top of left estimate panel (above "No Appendix Added !")
        if (!trigger) {
          const imgsAndSvgs = Array.from(document.querySelectorAll('img, svg, i, button, a'))
            .filter((el) => {
              if (!isVisible(el)) return false;
              const r = el.getBoundingClientRect();
              const meta = `${el.getAttribute('title') || ''} ${el.getAttribute('alt') || ''} ${el.getAttribute('src') || ''} ${el.className || ''}`.toLowerCase();
              return (meta.includes('appendix') || meta.includes('layer') || meta.includes('add_heading') || meta.includes('plus')) && r.top > 120 && r.top < 480;
            });
          if (imgsAndSvgs.length > 0) {
            trigger = imgsAndSvgs[0].closest('button, a, div') || imgsAndSvgs[0];
          }
        }

        if (!trigger) return null;
        clickEl(trigger);

        for (let i = 0; i < 18; i++) {
          await sleep(200);
          modal = findActiveAppendixModal();
          if (modal) return modal;
        }
        return null;
      }

      function findHeadingCards() {
        const results = [];
        const seen = new Set();
        const selectors = ['.accordion-item', '.card', '[class*="heading"]', '[class*="appendix"]', '.panel', '.list-group-item'];
        for (const sel of selectors) {
          for (const el of document.querySelectorAll(sel)) {
            if (!isVisible(el) || seen.has(el)) continue;
            const rect = el.getBoundingClientRect();
            if (rect.left < window.innerWidth * 0.58 && rect.height >= 28 && rect.width >= 120 && rect.top > 120) {
              const hasAction = el.querySelector('.fa-plus, .fa-plus-circle, .bi-plus, .fa-trash, .fa-edit, button, svg');
              const txt = (el.innerText || '').trim();
              if (hasAction && txt.length > 0 && !txt.includes('No Appendix Added') && !txt.includes('Add Appendix/Description')) {
                seen.add(el);
                results.push(el);
              }
            }
          }
        }
        return results;
      }

      async function addHeading(headingText) {
        dismissSwalIfAny();
        const modal = await openAddAppendixModal();
        if (!modal) {
          return { ok: false, message: 'Could not open "Add Appendix/Description" dialog. Make sure you are on the Estimate Edit screen (showing "Add Appendix").' };
        }

        // Ensure UPPER "Heading / Description" checkbox is checked (NOT "Lump sum Type")
        const checkboxes = Array.from(modal.querySelectorAll('input[type="checkbox"]'))
          .filter(isVisible)
          .sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top);

        if (checkboxes.length >= 1) {
          const upperChk = checkboxes[0];
          if (!upperChk.checked) {
            clickEl(upperChk);
            await sleep(300);
          }
        }

        // Find the Heading / Description text input inside modal (placeholder "Analysis of Rates")
        const inputs = Array.from(modal.querySelectorAll('input[type="text"], input:not([type]), textarea'))
          .filter((el) => isVisible(el) && !el.disabled && !el.readOnly);
        const headInput = inputs.find((el) => {
          const meta = `${el.placeholder || ''} ${el.name || ''} ${el.id || ''}`.toLowerCase();
          return meta.includes('analysis') || meta.includes('rate') || meta.includes('head') || meta.includes('desc');
        }) || inputs[0];

        if (!headInput) {
          return { ok: false, message: 'Heading text box not found inside Add Appendix/Description dialog.' };
        }

        setNativeValue(headInput, headingText);
        await sleep(250);

        const addBtn = findButtonByText([/^add$/i, /save/i, /submit/i], modal);
        if (!addBtn) {
          return { ok: false, message: '"Add" button not found inside Add Appendix/Description dialog.' };
        }
        clickEl(addBtn);
        await waitForPortalIdle(950, 20000);
        dismissSwalIfAny();
        blurKeyboard();
        return { ok: true, message: `Added heading: ${headingText}` };
      }

      async function addItem(headingIndex, code, isTM) {
        dismissSwalIfAny();
        const cards = findHeadingCards();
        const targetCard = cards[headingIndex] || cards[cards.length - 1];
        if (!targetCard) {
          return { ok: false, message: `Heading #${headingIndex + 1} card not found in left panel.` };
        }

        const plusBtn = targetCard.querySelector('button[title*="Add"], a[title*="Add"], .fa-plus, .fa-plus-circle, .bi-plus')?.closest('button, a')
          || targetCard.querySelector('.fa-plus, .fa-plus-circle, button');
        if (plusBtn && isVisible(plusBtn)) {
          clickEl(plusBtn);
          await waitForPortalIdle(700, 15000);
        }

        const selects = Array.from(document.querySelectorAll('select')).filter((s) => isVisible(s) && !s.disabled);
        const subheadSelect = selects.find((s) => {
          const txt = Array.from(s.options).map((o) => o.text).join(' ').toLowerCase();
          return txt.includes('sub head') || txt.includes('mgnrega') || txt.includes('54 -');
        });

        if (subheadSelect) {
          const chapter = String(code).split('.')[0].trim();
          let chosen = null;
          for (const opt of Array.from(subheadSelect.options)) {
            const t = (opt.text || '').trim();
            if (isTM && t.toUpperCase().includes('54') && t.toUpperCase().includes('TM')) {
              chosen = opt; break;
            }
            if (!isTM && chapter === '54' && t.toUpperCase().includes('54') && !t.toUpperCase().includes('TM') && t.toLowerCase().includes('bihar')) {
              chosen = opt; break;
            }
            if (chapter !== '54' && t.startsWith(chapter)) {
              chosen = opt; break;
            }
          }
          if (chosen) {
            subheadSelect.value = chosen.value;
            subheadSelect.dispatchEvent(new Event('change', { bubbles: true }));
            await waitForPortalIdle(750, 15000);
          }
        }

        const searchInputs = Array.from(document.querySelectorAll('input[type="text"], input[type="search"], input:not([type])'))
          .filter((el) => isVisible(el) && !el.disabled && el.getBoundingClientRect().top > 120);
        const searchBox = searchInputs.find((el) => {
          const meta = `${el.placeholder || ''} ${el.name || ''} ${el.id || ''}`.toLowerCase();
          return meta.includes('spec') || meta.includes('search') || meta.includes('code') || meta.includes('activity') || meta.includes('item');
        });

        if (!searchBox) {
          return { ok: false, message: `Specification/Activity search box not found for ${code}.` };
        }
        setNativeValue(searchBox, code);
        await sleep(250);

        const searchBtn = findButtonByText([/search/i, /find/i, /go/i]);
        if (searchBtn) {
          clickEl(searchBtn);
          await waitForPortalIdle(800, 15000);
        }

        const rows = Array.from(document.querySelectorAll('tr, .list-group-item, .search-result-row')).filter(isVisible);
        const codeUpper = String(code).trim().toUpperCase();
        const matchedRow = rows.find((r) => (r.innerText || '').toUpperCase().includes(codeUpper) && r.querySelector('input[type="checkbox"]'));

        if (!matchedRow) {
          const cancelBtn = findButtonByText([/cancel/i, /close/i]);
          if (cancelBtn) clickEl(cancelBtn);
          await sleep(300);
          return { ok: true, skipped: true, message: `Code ${code} not in search results (already in heading). Closed search cleanly.` };
        }

        const chk = matchedRow.querySelector('input[type="checkbox"]');
        if (chk && !chk.checked) {
          clickEl(chk);
          await sleep(250);
        }

        const saveSpecBtn = findButtonByText([/save/i, /add\s*selected/i, /add\s*item/i, /submit/i]);
        if (!saveSpecBtn) {
          return { ok: false, message: `Save button not found after selecting ${code}.` };
        }
        clickEl(saveSpecBtn);
        await waitForPortalIdle(1000, 20000);
        dismissSwalIfAny();
        blurKeyboard();
        return { ok: true, message: `Added SOR item ${code}` };
      }

      async function fillMeasurements(headingIndex, code, rowsData) {
        dismissSwalIfAny();
        const cards = findHeadingCards();
        const card = cards[headingIndex] || cards[cards.length - 1];
        if (!card) {
          return { ok: false, message: `Heading #${headingIndex + 1} not found for measurements of ${code}.` };
        }

        const headerToggle = card.querySelector('[data-bs-toggle="collapse"], [data-toggle="collapse"], .accordion-button, .card-header');
        if (headerToggle && isVisible(headerToggle) && headerToggle.getAttribute('aria-expanded') === 'false') {
          clickEl(headerToggle);
          await sleep(450);
        }

        const codeUpper = String(code).toUpperCase();
        const itemNodes = Array.from(card.querySelectorAll('tr, li, .item-row, div')).filter(isVisible);
        let targetItem = itemNodes.find((n) => (n.innerText || '').toUpperCase().includes(codeUpper));
        if (!targetItem) {
          targetItem = itemNodes.find((n) => (n.innerText || '').includes('₹ 0') || (n.innerText || '').includes('0.00'));
        }
        if (targetItem) {
          const measBtn = targetItem.querySelector('button[title*="Meas"], a[title*="Meas"], .fa-plus, .fa-calculator, .fa-edit') || targetItem;
          clickEl(measBtn);
          await waitForPortalIdle(750, 15000);
        }

        for (let rIdx = 0; rIdx < rowsData.length; rIdx++) {
          const row = rowsData[rIdx];
          if (rIdx > 0 || row.isDeduction) {
            const addRowBtn = row.isDeduction
              ? findButtonByText([/add\s*deduct/i, /deduction/i])
              : findButtonByText([/add\s*measurement/i, /add\s*row/i, /\+\s*add/i]);
            if (addRowBtn) {
              clickEl(addRowBtn);
              await sleep(300);
            }
          }

          const trs = Array.from(document.querySelectorAll('table tbody tr')).filter((tr) => {
            return isVisible(tr) && tr.querySelectorAll('input:not([type="hidden"]):not([type="checkbox"])').length >= 3;
          });
          const targetTr = trs[trs.length - 1];
          if (!targetTr) {
            return { ok: false, message: `Measurement input row not found for ${code} (row ${rIdx + 1}).` };
          }
          const inputs = Array.from(targetTr.querySelectorAll('input:not([type="hidden"]):not([type="checkbox"]), textarea'))
            .filter((el) => isVisible(el) && !el.disabled && !el.readOnly);

          const values = [row.desc || '', row.no || '1', row.l || '', row.b || '', row.d || '', row.cf || ''];
          for (let ci = 0; ci < Math.min(inputs.length, values.length); ci++) {
            if (values[ci] !== '') {
              setNativeValue(inputs[ci], values[ci]);
              await sleep(60);
            }
          }
        }

        const saveBtn = findButtonByText([/save\s*measurement/i, /^save$/i, /update/i]);
        if (!saveBtn) {
          return { ok: false, message: `Save Measurements button not found for ${code}.` };
        }
        clickEl(saveBtn);
        await waitForPortalIdle(1000, 20000);
        dismissSwalIfAny();
        blurKeyboard();
        return { ok: true, message: `Saved ${rowsData.length} measurement row(s) for ${code}` };
      }

      async function addLumpSum(keyword, customDesc, amount) {
        dismissSwalIfAny();
        const modal = await openAddAppendixModal();
        if (!modal) {
          return { ok: false, message: 'Could not open Add Appendix/Description dialog for Lump Sum.' };
        }

        // Must tick the LOWER "Lump sum Type" checkbox (NOT upper "Heading / Description")
        const checkboxes = Array.from(modal.querySelectorAll('input[type="checkbox"]'))
          .filter(isVisible)
          .sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top);

        let lumpChk = checkboxes.find((cb) => {
          const labelTxt = (cb.closest('label')?.innerText || cb.parentElement?.innerText || '').toLowerCase();
          return labelTxt.includes('lump') && !labelTxt.includes('heading');
        }) || (checkboxes.length >= 2 ? checkboxes[checkboxes.length - 1] : checkboxes[0]);

        if (lumpChk && !lumpChk.checked) {
          clickEl(lumpChk);
          await sleep(450);
        }

        const selects = Array.from(modal.querySelectorAll('select')).filter((s) => isVisible(s) && !s.disabled);
        const lumpSelect = selects.find((s) => {
          const txt = Array.from(s.options).map((o) => o.text).join(' ').toLowerCase();
          return txt.includes('lump') || txt.includes('conveyance') || txt.includes('miscellaneous') || txt.includes('display board');
        }) || selects[0];

        if (!lumpSelect) {
          return { ok: false, message: 'Lump sum Type dropdown not found in dialog.' };
        }

        const kwLow = String(keyword || 'Miscellaneous').toLowerCase();
        const opt = Array.from(lumpSelect.options).find((o) => (o.text || '').toLowerCase().includes(kwLow))
          || Array.from(lumpSelect.options).find((o) => (o.text || '').toLowerCase().includes('miscellaneous'));
        if (opt) {
          lumpSelect.value = opt.value;
          lumpSelect.dispatchEvent(new Event('change', { bubbles: true }));
          await sleep(500);
        }

        // Skip Lump sum description if hidden/disabled (e.g. Conveyance - M)
        const inputs = Array.from(modal.querySelectorAll('input[type="text"], input[type="number"], input:not([type]), textarea'))
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
          return { ok: false, message: 'Lump sum amount input not found in dialog.' };
        }
        setNativeValue(amtInput, String(amount));
        await sleep(200);

        const saveBtn = findButtonByText([/^add$/i, /add\s*lump/i, /save/i], modal);
        if (!saveBtn) {
          return { ok: false, message: '"Add" button not found for Lump Sum.' };
        }
        clickEl(saveBtn);
        await waitForPortalIdle(950, 20000);
        dismissSwalIfAny();
        blurKeyboard();
        return { ok: true, message: `Added Lump Sum: ${keyword} (₹${amount})` };
      }

      function scrapeCurrentEstimate() {
        const cards = findHeadingCards();
        const headings = cards.map((card, idx) => {
          const titleEl = card.querySelector('.card-header, .accordion-button, h5, h6, strong, .heading-title') || card;
          const rawTitle = (titleEl.innerText || '').split('\n')[0].trim();
          const items = [];
          const codeRe = /\b(\d{1,2}(?:\.TM)?(?:\.[A-Za-z0-9]+){2,6})\b/gi;
          const text = card.innerText || '';
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
        const cards = findHeadingCards();
        const card = cards[headingIndex];
        if (!card) return { ok: false, message: `Heading #${headingIndex + 1} not found for deletion.` };
        const codeUpper = String(code).toUpperCase();
        const rows = Array.from(card.querySelectorAll('tr, li, .item-row, div')).filter(isVisible);
        const match = rows.find((r) => (r.innerText || '').toUpperCase().includes(codeUpper) && r.querySelector('.fa-trash, .bi-trash, button[title*="Delete"], a[title*="Delete"]'));
        if (!match) return { ok: false, message: `Delete icon not found for item ${code}.` };
        const delBtn = match.querySelector('.fa-trash, .bi-trash, button[title*="Delete"], a[title*="Delete"]')?.closest('button, a')
          || match.querySelector('.fa-trash, .bi-trash');
        clickEl(delBtn);
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
        isPortalLoading
      };
      window.__SECURE_AI_IPAD_V2__ = true;
    })();
    """#
}
