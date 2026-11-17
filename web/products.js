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

function formatDate(value) {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.valueOf())) return '';
  return new Intl.DateTimeFormat('en-CA', {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit',
  }).format(date);
}

function showError() {
  const app = document.querySelector('#app');
  app.replaceChildren();
  const card = document.createElement('section');
  card.className = 'state-card';
  card.append(
    textElement('h1', '', 'Products are unavailable right now'),
    textElement('p', '', 'Please check back later or contact the bakery directly.'),
  );
  app.append(card);
}

async function callRpc(name, body) {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body || {}),
  });
  if (!response.ok) {
    let message = `Request failed: ${response.status}`;
    try {
      const data = await response.json();
      if (data && data.message) message = data.message;
    } catch (_) { /* response body wasn't JSON - keep the generic message */ }
    throw new Error(message);
  }
  return response.json();
}

function openReserveDialog(product, identity) {
  const dialog = document.querySelector('#reserve-dialog');
  const form = document.querySelector('#reserve-form');
  const errorEl = document.querySelector('#reserve-error');
  const submitButton = document.querySelector('#reserve-submit');
  const nameLabel = document.querySelector('#reserve-name-label');
  const nameInput = document.querySelector('#reserve-name');
  const contactInput = document.querySelector('#reserve-contact');
  const contactLabel = document.querySelector('#reserve-contact-label');

  form.reset();
  errorEl.hidden = true;
  submitButton.disabled = false;
  submitButton.textContent = 'Send reservation';
  document.querySelector('#reserve-product-title').textContent = product.title;
  document.querySelector('#reserve-quantity').max = String(product.remaining);
  document.querySelector('#reserve-quantity').value = '1';

  // Arriving from the customer's own SOA link: pre-fill the name field
  // instead of making them retype it - still visible and editable, same
  // as everything else on the form. Contact also stays editable (and
  // optional - the server falls back to the phone on file) in case it's
  // stale.
  nameLabel.hidden = false;
  if (identity) {
    nameInput.value = identity.name;
    nameInput.required = true;
    // Editable in form terms, but the server always uses the name on your
    // account regardless of what's typed here - read-only avoids editing
    // something that silently wouldn't take effect.
    nameInput.readOnly = true;
    contactInput.required = false;
    contactLabel.firstChild.textContent = 'Phone or Messenger/Facebook name (leave blank to use what’s on file)';
  } else {
    nameInput.readOnly = false;
    nameInput.required = true;
    contactInput.required = true;
    contactLabel.firstChild.textContent = 'Phone or Messenger/Facebook name';
  }

  const onSubmit = async (event) => {
    event.preventDefault();
    errorEl.hidden = true;
    const name = nameInput.value.trim();
    const contact = contactInput.value.trim();
    const quantity = Number(document.querySelector('#reserve-quantity').value || 1);
    const note = document.querySelector('#reserve-note').value.trim();

    submitButton.disabled = true;
    submitButton.textContent = 'Sending…';
    try {
      await callRpc('submit_product_reservation', {
        p_product_id: product.id,
        p_customer_name: identity ? null : name,
        p_customer_contact: contact || null,
        p_quantity: quantity,
        p_note: note || null,
        p_soa_token: identity ? identity.token : null,
      });
      form.removeEventListener('submit', onSubmit);
      dialog.close();
      markReserved(product.id);
      if (identity) loadMyReservations(identity);
    } catch (err) {
      errorEl.textContent = err.message || 'Could not send your reservation. Please try again.';
      errorEl.hidden = false;
      submitButton.disabled = false;
      submitButton.textContent = 'Send reservation';
    }
  };
  form.addEventListener('submit', onSubmit);

  document.querySelector('#reserve-cancel').onclick = () => {
    form.removeEventListener('submit', onSubmit);
    dialog.close();
  };

  dialog.showModal();
}

function markReserved(productId) {
  const button = document.querySelector(`.reserve-button[data-product-id="${productId}"]`);
  if (!button) return;
  button.disabled = true;
  button.textContent = 'Reserved - thank you!';
}

const STATUS_LABEL = {
  pending: 'Pending',
  contacted: 'Contacted by the bakery',
  fulfilled: 'Fulfilled',
  cancelled: 'Cancelled',
};

function renderMyReservation(reservation, identity, onChanged) {
  const template = document.querySelector('#my-reservation-template');
  const row = template.content.cloneNode(true);
  const article = row.querySelector('.my-reservation');
  const cancelled = reservation.status === 'cancelled';
  if (cancelled) article.classList.add('cancelled');

  row.querySelector('.my-reservation-title').textContent =
    `${reservation.product_title} x ${reservation.quantity}`;
  row.querySelector('.my-reservation-meta').textContent =
    `${STATUS_LABEL[reservation.status] || reservation.status} · ${formatDate(reservation.created_at)}`
    + (reservation.note ? ` · ${reservation.note}` : '');

  const qtyInput = row.querySelector('.my-reservation-qty');
  qtyInput.value = String(reservation.quantity);

  row.querySelector('.my-reservation-update').addEventListener('click', async (event) => {
    const button = event.currentTarget;
    const quantity = Number(qtyInput.value || 0);
    if (!Number.isInteger(quantity) || quantity < 1) return;
    button.disabled = true;
    try {
      await callRpc('update_my_reservation_quantity', {
        p_soa_token: identity.token,
        p_reservation_id: reservation.id,
        p_quantity: quantity,
      });
      await onChanged();
    } catch (err) {
      window.alert(err.message || 'Could not update that reservation.');
      button.disabled = false;
    }
  });

  row.querySelector('.my-reservation-cancel').addEventListener('click', async (event) => {
    const button = event.currentTarget;
    if (!window.confirm('Cancel this reservation?')) return;
    button.disabled = true;
    try {
      await callRpc('cancel_my_reservation', {
        p_soa_token: identity.token,
        p_reservation_id: reservation.id,
      });
      await onChanged();
    } catch (err) {
      window.alert(err.message || 'Could not cancel that reservation.');
      button.disabled = false;
    }
  });

  return row;
}

async function loadMyReservations(identity) {
  const section = document.querySelector('#my-reservations-section');
  const list = document.querySelector('#my-reservations');
  if (!identity) {
    section.hidden = true;
    return;
  }
  try {
    const reservations = await callRpc('get_my_reservations', { p_soa_token: identity.token });
    list.replaceChildren();
    if (!Array.isArray(reservations) || reservations.length === 0) {
      section.hidden = true;
      return;
    }
    reservations.forEach((reservation) => {
      list.append(renderMyReservation(reservation, identity, () => loadMyReservations(identity)));
    });
    section.hidden = false;
  } catch (_) {
    // Don't block the rest of the page over this secondary panel.
    section.hidden = true;
  }
}

function renderProductCard(product, identity) {
  const template = document.querySelector('#product-card-template');
  const card = template.content.cloneNode(true);
  const photo = card.querySelector('.product-photo');
  if (product.image_url) {
    photo.src = product.image_url;
  } else {
    photo.remove();
  }
  card.querySelector('.product-title').textContent = product.title;
  card.querySelector('.product-remaining').textContent = `${product.remaining} left`;
  card.querySelector('.product-price').textContent = money.format(Number(product.unit_price || 0));
  const button = card.querySelector('.reserve-button');
  button.dataset.productId = product.id;
  button.addEventListener('click', () => openReserveDialog(product, identity));
  return card;
}

function render(data, identity) {
  const template = document.querySelector('#products-template');
  const content = template.content.cloneNode(true);
  const businessName = data.business_name || 'My Bakery';
  const products = Array.isArray(data.products) ? data.products : [];

  document.title = `${businessName} · Available Products`;
  document.querySelector('#business-name').textContent = businessName;
  content.querySelector('#generated-at').textContent = `Updated ${formatDate(data.generated_at)}`;
  if (identity) {
    content.querySelector('#products-help').textContent =
      `Hi ${identity.name}! Tap "Reserve" on anything you'd like - we already know who you are, `
      + 'so just confirm the quantity and we\'ll follow up.';
    const backLink = content.querySelector('#back-to-soa');
    backLink.href = `soa.html?soa=${encodeURIComponent(identity.token)}`;
    backLink.hidden = false;
  }

  const grid = content.querySelector('#product-grid');
  if (products.length) {
    products.forEach((product) => grid.append(renderProductCard(product, identity)));
  } else {
    grid.append(textElement('div', 'empty', 'Nothing available to reserve right now - check back soon!'));
  }

  document.querySelector('#app').replaceChildren(content);
}

async function resolveIdentity(token) {
  if (!token) return null;
  try {
    const data = await callRpc('get_customer_soa', { p_token: token });
    const name = data?.customer?.name;
    return name ? { token, name } : null;
  } catch (_) {
    // An invalid/expired soa token just falls back to the anonymous flow
    // rather than blocking the whole products page.
    return null;
  }
}

async function start() {
  const token = new URLSearchParams(window.location.search).get('soa');
  try {
    const [products, identity] = await Promise.all([
      callRpc('get_available_products'),
      resolveIdentity(token),
    ]);
    render(products, identity);
    if (identity) loadMyReservations(identity);
  } catch (_) {
    showError();
  }
}

start();
