'use strict';

const SUPABASE_URL = 'https://okbcyeamtrgjhspiwwim.supabase.co';
const SUPABASE_KEY = 'sb_publishable_wE69j1eaOaeyXB-7e63w0w_DDVpV3kD';
const money = new Intl.NumberFormat('en-PH', {
  style: 'currency',
  currency: 'PHP',
  minimumFractionDigits: 2,
});

function textElement(tag, className, text) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  element.textContent = text;
  return element;
}

function formatDate(value, includeTime = false) {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.valueOf())) return '';
  return new Intl.DateTimeFormat('en-CA', {
    year: 'numeric', month: '2-digit', day: '2-digit',
    ...(includeTime ? { hour: '2-digit', minute: '2-digit' } : {}),
  }).format(date);
}

function showError() {
  const app = document.querySelector('#app');
  app.replaceChildren();
  const card = document.createElement('section');
  card.className = 'state-card';
  card.append(
    textElement('h1', '', 'This statement link is unavailable'),
    textElement('p', '', 'It may have been replaced or disabled. Please ask the bakery for a new link.'),
  );
  app.append(card);
}

function renderTransaction(sale) {
  const remaining = Number(sale.remaining || 0);
  const settled = Boolean(sale.paid) || remaining <= 0;
  const card = document.createElement('article');
  card.className = 'transaction';

  const details = document.createElement('div');
  const payments = Array.isArray(sale.payments) ? sale.payments : [];
  const paidDate = sale.date_paid || payments.at(-1)?.date;
  const itemDetails = sale.kind === 'cash_advance'
    ? formatDate(sale.sale_date)
    : `${formatDate(sale.sale_date)} · ${sale.quantity || 1} unit(s)`;
  details.append(
    textElement('h3', '', sale.product || 'Order'),
    textElement('p', '', itemDetails),
    textElement('p', '', settled
      ? `Paid${paidDate ? ` on ${formatDate(paidDate)}` : ''}`
      : `${money.format(remaining)} remaining`),
  );
  if (!settled && payments.length) {
    details.append(textElement(
      'p',
      'payment-dates',
      `Payments: ${payments.map((payment) => `${money.format(Number(payment.amount || 0))} on ${formatDate(payment.date)}`).join(', ')}`,
    ));
  }

  const amount = document.createElement('div');
  amount.className = `amount${settled ? ' paid' : ''}`;
  amount.append(textElement('span', 'value', money.format(Number(sale.amount || 0))));
  if (settled) amount.append(textElement('span', 'badge', 'PAID'));
  card.append(details, amount);
  return card;
}

function publicQrUrl(path) {
  const encoded = path.split('/').map(encodeURIComponent).join('/');
  return `${SUPABASE_URL}/storage/v1/object/public/qr-codes/${encoded}`;
}

function renderQr(url, label) {
  const card = document.createElement('figure');
  card.className = 'qr-card';
  const image = document.createElement('img');
  image.src = url;
  image.alt = label;
  image.loading = 'lazy';
  card.append(image, textElement('figcaption', '', label));
  return card;
}

function render(data) {
  const template = document.querySelector('#statement-template');
  const content = template.content.cloneNode(true);
  const businessName = data.business_name || 'My Bakery';
  const balance = Number(data.balance || 0);
  const sales = Array.isArray(data.sales) ? data.sales : [];
  const qrPaths = Array.isArray(data.qr_paths) ? data.qr_paths : [];

  document.title = `${businessName} · Statement of Account`;
  document.querySelector('#business-name').textContent = businessName;
  content.querySelector('#statement-date').textContent = formatDate(data.generated_at, true);
  content.querySelector('#customer-name').textContent = data.customer?.name || 'Customer';
  content.querySelector('#balance').textContent = money.format(balance);
  content.querySelector('#updated-at').textContent = `Updated ${formatDate(data.generated_at, true)}`;

  const transactions = content.querySelector('#transactions');
  const unpaidSales = sales.filter((sale) => !(Boolean(sale.paid) || Number(sale.remaining || 0) <= 0));
  const paidSales = sales.filter((sale) => Boolean(sale.paid) || Number(sale.remaining || 0) <= 0);
  const unpaidCount = content.querySelector('#unpaid-count');
  const paidCount = content.querySelector('#paid-count');
  const paidTransactions = content.querySelector('#paid-transactions');
  const hasTabMarkup = Boolean(unpaidCount && paidCount && paidTransactions);

  if (hasTabMarkup) {
    unpaidCount.textContent = `(${unpaidSales.length})`;
    paidCount.textContent = `(${paidSales.length})`;
  }
  if (unpaidSales.length) {
    unpaidSales.forEach((sale) => transactions.append(renderTransaction(sale)));
  } else {
    transactions.append(textElement('div', 'empty', 'No outstanding transactions — you’re all paid up. Thank you!'));
  }

  if (hasTabMarkup && paidSales.length) {
    paidSales.forEach((sale) => paidTransactions.append(renderTransaction(sale)));
  } else if (hasTabMarkup) {
    paidTransactions.append(
      textElement('div', 'empty', 'No paid transactions to show.'),
    );
  } else {
    // A previously cached copy of soa.html may not contain the tab markup yet.
    // Keep that page usable until the browser refreshes the HTML.
    paidSales.forEach((sale) => transactions.append(renderTransaction(sale)));
  }

  if (balance > 0) {
    const paymentSection = content.querySelector('#payment-section');
    paymentSection.hidden = false;
    const qrList = content.querySelector('#qr-list');
    if (qrPaths.length) {
      qrPaths.forEach((path, index) => qrList.append(renderQr(publicQrUrl(path), `Payment option ${index + 1}`)));
    } else {
      qrList.append(renderQr('assets/assets/images/qr_maribank.jpg', 'Payment QR'));
    }
  }

  content.querySelector('#footer-note').textContent =
    `Thank you for supporting ${businessName}! This is a read-only statement; contact us if anything needs to be corrected.`;
  document.querySelector('#app').replaceChildren(content);

  document.querySelector('#print-statement')?.addEventListener('click', () => window.print());
  document.querySelector('#share-statement')?.addEventListener('click', async () => {
    const share = { title: document.title, url: window.location.href };
    if (navigator.share) {
      await navigator.share(share);
    } else {
      await navigator.clipboard.writeText(window.location.href);
      window.alert('Statement link copied.');
    }
  });
  document.querySelector('#refresh-statement')?.addEventListener('click', () => window.location.reload());

  const tabs = [...document.querySelectorAll('.tab-button')];
  const panels = [...document.querySelectorAll('.tab-panel')];
  tabs.forEach((tab) => tab.addEventListener('click', () => {
    const selected = tab.dataset.tab;
    tabs.forEach((item) => {
      const active = item === tab;
      item.classList.toggle('active', active);
      item.setAttribute('aria-selected', String(active));
    });
    panels.forEach((panel) => {
      panel.hidden = panel.id !== `${selected}-panel`;
    });
  }));
}

async function start() {
  const token = new URLSearchParams(window.location.search).get('soa');
  if (!token) return showError();
  try {
    const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_customer_soa`, {
      method: 'POST',
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: `Bearer ${SUPABASE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ p_token: token }),
    });
    if (!response.ok) throw new Error(`SOA request failed: ${response.status}`);
    render(await response.json());
  } catch (_) {
    showError();
  }
}

start();
