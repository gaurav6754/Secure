import Foundation

/// JavaScript DOM automation engine injected directly into the in-app WKWebView.
/// Replaces desktop OpenCV/PyAutoGUI screen clicking with direct, reliable DOM interaction
/// for the Bihar MGNREGA SECURE portal (secure.dord.gov.in).
enum SecureAutomationJS {
    static let engineScript: String = #"""
    (function() {
      if (window.__SECURE_AI_IPAD__) return;

      const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

      function isVisible(el) {
        if (!el) return false;
        const style = window.getComputedStyle(el);
        if (style.display === 'none' || style.visibility === 'hidden' || parseFloat(style.opacity) === 0) return false;
        const rect = el.getBoundingClientRect();
        return rect.width > 1 && rect.height > 1;
      }

      function setNativeValue(el, value) {
        if (!el) return;
        const str = value == null ? '' : String(value);
        el.focus();
        const proto = el.tagName === 'TEXTAREA'
          ? window.HTMLTextAreaElement.prototype
          : (el.tagName === 'SELECT' ? window.HTMLSelectElement.prototype : window.HTMLInputElement.prototype);
        const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
        if (setter) setter.call(el, str);
        else el.value = str;
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        el.dispatchEvent(new Event('blur', { bubbles: true }));
      }

      function clickEl(el) {
        if (!el) return false;
        el.scrollIntoView({ behavior: 'instant', block: 'center' });
        el.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
        el.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true }));
        el.click();
        return true;
      }

      function isPortalLoading() {
        const selectors = [
          '.spinner', '.loader', '.loading', '.blockUI', '.ngx-spinner-overlay',
          '.swal2-loading', '[class*="spinner"]', '[class*="loader"]', '#preloader'
        ];
        for (const sel of selectors) {
          const nodes = document.querySelectorAll(sel);
          for (const n of nodes) {
            if (isVisible(n)) return true;
          }
        }
        return false;
      }

      async function waitForPortalIdle(minWaitMs = 650, maxWaitMs = 20000) {
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
        const candidates = root.querySelectorAll('button, a.btn, input[type="button"], input[type="submit"], [role="button"]');
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
          const txt = (confirmBtn.innerText || '').toLowerCase();
          if (txt.includes('ok') || txt.includes('close')) {
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

      function findHeadingCards() {
        const selectors = [
          '.accordion-item', '.card', '[class*="heading-card"]', '[class*="subhead"]',
          '.panel', 'li[class*="heading"]', '.list-group-item'
        ];
        const results = [];
        const seen = new Set();
        for (const sel of selectors) {
          for (const el of document.querySelectorAll(sel)) {
            if (!isVisible(el) || seen.has(el)) continue;
            const rect = el.getBoundingClientRect();
            // Left panel headings sit on the left half of the viewport
            if (rect.left < window.innerWidth * 0.55 && rect.height >= 24 && rect.width >= 120) {
              const hasPlusOrTrash = el.querySelector('.fa-plus, .fa-plus-circle, .bi-plus, button[title*="Add"], [title*="Item"], .fa-trash');
              if (hasPlusOrTrash) {
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
        // 1. Click Add Heading button/icon
        let addBtn = findButtonByText([/add\s*appendix/i, /add\s*heading/i, /new\s*heading/i, /\+\s*heading/i]);
        if (!addBtn) {
          // Look for top-left '+' icon near "Heading" or "Estimate"
          const icons = document.querySelectorAll('i.fa-plus, i.fa-plus-circle, i.bi-plus-circle, button[title*="Heading"], a[title*="Heading"]');
          for (const ic of icons) {
            const target = ic.closest('button, a') || ic;
            if (isVisible(target) && target.getBoundingClientRect().left < window.innerWidth * 0.5) {
              addBtn = target;
              break;
            }
          }
        }
        if (addBtn) {
          clickEl(addBtn);
          await sleep(450);
        }

        // 2. Find visible Heading input field
        const inputs = Array.from(document.querySelectorAll('input[type="text"], input:not([type]), textarea'))
          .filter((el) => isVisible(el) && !el.disabled && !el.readOnly);
        let headInput = inputs.find((el) => {
          const meta = `${el.placeholder || ''} ${el.name || ''} ${el.id || ''} ${el.getAttribute('aria-label') || ''}`.toLowerCase();
          return meta.includes('head') || meta.includes('description') || meta.includes('subhead');
        }) || inputs[0];

        if (!headInput) {
          return { ok: false, message: 'Heading input box not found on current page. Make sure an empty/draft SECURE estimate is open.' };
        }

        setNativeValue(headInput, headingText);
        await sleep(250);

        // 3. Click Add / Save button in modal or form
        const modal = headInput.closest('.modal, .modal-content, .card, form') || document;
        const saveBtn = findButtonByText([/^add$/i, /save/i, /submit/i, /add\s*heading/i], modal) || findButtonByText([/^add$/i, /save/i]);
        if (!saveBtn) {
          return { ok: false, message: 'Add/Save button for Heading not found.' };
        }
        clickEl(saveBtn);
        await waitForPortalIdle(850, 20000);
        dismissSwalIfAny();
        return { ok: true, message: `Added heading: ${headingText}` };
      }

      async function addItem(headingIndex, code, isTM) {
        dismissSwalIfAny();
        const cards = findHeadingCards();
        const targetCard = cards[headingIndex] || cards[cards.length - 1];
        if (targetCard) {
          const plusBtn = targetCard.querySelector('button[title*="Add"], a[title*="Add"], .fa-plus, .fa-plus-circle, .bi-plus')?.closest('button, a')
            || targetCard.querySelector('.fa-plus, .fa-plus-circle');
          if (plusBtn && isVisible(plusBtn)) {
            clickEl(plusBtn);
            await waitForPortalIdle(600, 15000);
          }
        }

        // 1. Select Sub Head Type (<select>)
        const selects = Array.from(document.querySelectorAll('select')).filter((s) => isVisible(s) && !s.disabled);
        const subheadSelect = selects.find((s) => {
          const txt = Array.from(s.options).map((o) => o.text).join(' ').toLowerCase();
          return txt.includes('sub head') || txt.includes('mgnrega') || txt.includes('54 -');
        }) || selects[0];

        if (subheadSelect) {
          const chapter = String(code).split('.')[0].trim();
          let chosen = null;
          for (const opt of Array.from(subheadSelect.options)) {
            const t = (opt.text || '').trim();
            if (isTM && t.toUpperCase().includes('54') && t.toUpperCase().includes('TM')) {
              chosen = opt;
              break;
            }
            if (!isTM && chapter === '54' && t.toUpperCase().includes('54') && !t.toUpperCase().includes('TM') && t.toLowerCase().includes('bihar')) {
              chosen = opt;
              break;
            }
            if (chapter !== '54' && t.startsWith(chapter)) {
              chosen = opt;
              break;
            }
          }
          if (chosen) {
            subheadSelect.value = chosen.value;
            subheadSelect.dispatchEvent(new Event('change', { bubbles: true }));
            await waitForPortalIdle(700, 15000);
          }
        }

        // 2. Search Specification / Activity code
        const searchInputs = Array.from(document.querySelectorAll('input[type="text"], input[type="search"], input:not([type])'))
          .filter((el) => isVisible(el) && !el.disabled);
        const searchBox = searchInputs.find((el) => {
          const meta = `${el.placeholder || ''} ${el.name || ''} ${el.id || ''}`.toLowerCase();
          return meta.includes('spec') || meta.includes('search') || meta.includes('code') || meta.includes('activity') || meta.includes('item');
        }) || searchInputs[searchInputs.length - 1];

        if (!searchBox) {
          return { ok: false, message: `Search input not found for SOR code ${code}` };
        }
        setNativeValue(searchBox, code);
        await sleep(250);

        const searchBtn = findButtonByText([/search/i, /find/i, /go/i]);
        if (searchBtn) {
          clickEl(searchBtn);
          await waitForPortalIdle(750, 15000);
        }

        // 3. Find matching result checkbox
        const rows = Array.from(document.querySelectorAll('tr, .list-group-item, .search-result-row')).filter(isVisible);
        const codeUpper = String(code).trim().toUpperCase();
        let matchedRow = rows.find((r) => (r.innerText || '').toUpperCase().includes(codeUpper) && r.querySelector('input[type="checkbox"]'));

        if (!matchedRow) {
          // SECURE hides codes already present in the heading -> cancel cleanly so next step proceeds
          const cancelBtn = findButtonByText([/cancel/i, /close/i]);
          if (cancelBtn) clickEl(cancelBtn);
          await sleep(300);
          return { ok: true, skipped: true, message: `Code ${code} not in search results (likely already present in heading). Closed search cleanly.` };
        }

        const chk = matchedRow.querySelector('input[type="checkbox"]');
        if (chk && !chk.checked) {
          clickEl(chk);
          await sleep(250);
        }

        const saveSpecBtn = findButtonByText([/save/i, /add\s*selected/i, /add\s*item/i, /submit/i]);
        if (!saveSpecBtn) {
          return { ok: false, message: `Save button not found after selecting ${code}` };
        }
        clickEl(saveSpecBtn);
        await waitForPortalIdle(950, 20000);
        dismissSwalIfAny();
        return { ok: true, message: `Added SOR item ${code}` };
      }

      async function fillMeasurements(headingIndex, code, rowsData) {
        dismissSwalIfAny();
        // Expand heading if collapsed and click item matching code (or ₹ 0 unfilled item)
        const cards = findHeadingCards();
        const card = cards[headingIndex] || cards[cards.length - 1];
        if (card) {
          const headerToggle = card.querySelector('[data-bs-toggle="collapse"], [data-toggle="collapse"], .accordion-button, .card-header');
          if (headerToggle && isVisible(headerToggle)) {
            const expanded = headerToggle.getAttribute('aria-expanded');
            if (expanded === 'false') {
              clickEl(headerToggle);
              await sleep(450);
            }
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
            await waitForPortalIdle(700, 15000);
          }
        }

        // Fill each measurement row
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

          // Locate editable measurement table rows on right panel
          const trs = Array.from(document.querySelectorAll('table tbody tr')).filter((tr) => {
            return isVisible(tr) && tr.querySelectorAll('input:not([type="hidden"]):not([type="checkbox"])').length >= 3;
          });
          const targetTr = trs[trs.length - 1];
          if (!targetTr) {
            return { ok: false, message: `Measurement input row not found for ${code} (row ${rIdx + 1})` };
          }
          const inputs = Array.from(targetTr.querySelectorAll('input:not([type="hidden"]):not([type="checkbox"]), textarea'))
            .filter((el) => isVisible(el) && !el.disabled && !el.readOnly);

          // Standard SECURE column order: [Description, No, L/D/A, B/B, D/C, Cf]
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
          return { ok: false, message: `Save Measurements button not found for ${code}` };
        }
        clickEl(saveBtn);
        await waitForPortalIdle(1000, 20000);
        dismissSwalIfAny();
        return { ok: true, message: `Saved ${rowsData.length} measurement row(s) for ${code}` };
      }

      async function addLumpSum(keyword, customDesc, amount) {
        dismissSwalIfAny();
        // Rule from v3.0.10: Must tick the LOWER 'Lump sum Type' checkbox (NOT the upper Heading checkbox)
        const checkboxes = Array.from(document.querySelectorAll('input[type="checkbox"]')).filter(isVisible);
        let lumpChk = checkboxes.find((cb) => {
          const labelTxt = (cb.closest('label')?.innerText || cb.parentElement?.innerText || '').toLowerCase();
          return labelTxt.includes('lump') && !labelTxt.includes('heading');
        });
        if (!lumpChk && checkboxes.length >= 2) {
          // Pick the lower checkbox on screen
          lumpChk = checkboxes.sort((a, b) => a.getBoundingClientRect().top - b.getBoundingClientRect().top)[checkboxes.length - 1];
        }
        if (lumpChk && !lumpChk.checked) {
          clickEl(lumpChk);
          await sleep(450);
        }

        // Select '-- Select Lump sum Type --' dropdown
        const selects = Array.from(document.querySelectorAll('select')).filter((s) => isVisible(s) && !s.disabled);
        const lumpSelect = selects.find((s) => {
          const txt = Array.from(s.options).map((o) => o.text).join(' ').toLowerCase();
          return txt.includes('lump') || txt.includes('conveyance') || txt.includes('miscellaneous') || txt.includes('display board');
        });

        if (!lumpSelect) {
          return { ok: false, message: 'Lump sum Type dropdown not found.' };
        }
        const kwLow = String(keyword || 'Miscellaneous').toLowerCase();
        const opt = Array.from(lumpSelect.options).find((o) => (o.text || '').toLowerCase().includes(kwLow))
          || Array.from(lumpSelect.options).find((o) => (o.text || '').toLowerCase().includes('miscellaneous'));
        if (opt) {
          lumpSelect.value = opt.value;
          lumpSelect.dispatchEvent(new Event('change', { bubbles: true }));
          await sleep(500);
        }

        // Rule from v3.0.10: Selecting options like 'Conveyance - M' hides 'Lump sum description' -> only fill if visible & enabled
        const inputs = Array.from(document.querySelectorAll('input[type="text"], input[type="number"], textarea'))
          .filter((el) => isVisible(el) && !el.disabled && !el.readOnly);
        const descInput = inputs.find((el) => {
          const meta = `${el.placeholder || ''} ${el.name || ''} ${el.id || ''}`.toLowerCase();
          return meta.includes('desc') && !meta.includes('head');
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
        setNativeValue(amtInput, String(amount));
        await sleep(200);

        const saveBtn = findButtonByText([/add\s*lump/i, /save/i, /^add$/i]);
        if (!saveBtn) {
          return { ok: false, message: 'Save/Add button for Lump Sum not found.' };
        }
        clickEl(saveBtn);
        await waitForPortalIdle(900, 20000);
        dismissSwalIfAny();
        return { ok: true, message: `Added Lump Sum: ${keyword} (₹${amount})` };
      }

      function scrapeCurrentEstimate() {
        const cards = findHeadingCards();
        const headings = cards.map((card, idx) => {
          const titleEl = card.querySelector('.card-header, .accordion-button, h5, h6, strong, .heading-title') || card;
          const rawTitle = (titleEl.innerText || '').split('\n')[0].trim();
          const items = [];
          const codeRe = /\b(\d{1,2}(?:\.TM)?(?:\.\d+[A-Za-z]?){1,5})\b/gi;
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
    })();
    """#
}
