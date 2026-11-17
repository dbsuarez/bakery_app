// Sends an email to the bakery owner whenever a new row lands in
// public.product_reservations (a lead from the public announce/reserve
// page, web/products.html). Triggered by a Postgres AFTER INSERT trigger
// via pg_net - see docs/migrations/20261118_reservation_email_notify.sql.
//
// Deploy with --no-verify-jwt (the caller is Postgres via pg_net, not an
// authenticated app user); the TRIGGER_SECRET header check below is what
// actually guards this endpoint instead.
//
// Required Edge Function secrets (set via `supabase secrets set`):
//   RESEND_API_KEY   - from resend.com dashboard
//   TRIGGER_SECRET   - shared secret also embedded in the SQL trigger
//   NOTIFY_TO_EMAIL  - where to send the alert (e.g. dbsuarez@gmail.com)

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
const TRIGGER_SECRET = Deno.env.get('TRIGGER_SECRET');
const NOTIFY_TO_EMAIL = Deno.env.get('NOTIFY_TO_EMAIL');
// Resend's sandbox sender - only deliverable to the email address that
// owns the Resend account until a real sending domain is verified there.
const FROM_EMAIL = 'My Bakery <onboarding@resend.dev>';

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }
  if (!RESEND_API_KEY || !TRIGGER_SECRET || !NOTIFY_TO_EMAIL) {
    console.error('Missing RESEND_API_KEY, TRIGGER_SECRET or NOTIFY_TO_EMAIL secret');
    return new Response('Not configured', { status: 500 });
  }
  if (req.headers.get('x-trigger-secret') !== TRIGGER_SECRET) {
    return new Response('Unauthorized', { status: 401 });
  }

  let payload: {
    product_title?: string;
    customer_name?: string;
    customer_contact?: string;
    quantity?: number;
    note?: string | null;
  };
  try {
    payload = await req.json();
  } catch {
    return new Response('Invalid JSON body', { status: 400 });
  }

  const {
    product_title: productTitle = 'a product',
    customer_name: customerName = 'Someone',
    customer_contact: customerContact = '(no contact given)',
    quantity = 1,
    note,
  } = payload;

  const subject = `New reservation: ${productTitle} x${quantity}`;
  const text = [
    `${customerName} reserved ${quantity} unit(s) of "${productTitle}".`,
    '',
    `Contact: ${customerContact}`,
    note ? `Note: ${note}` : null,
    '',
    'Open the app > Batches > Reservations to follow up and mark it handled.',
  ]
    .filter((line) => line !== null)
    .join('\n');

  const resendResponse = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: [NOTIFY_TO_EMAIL],
      subject,
      text,
    }),
  });

  if (!resendResponse.ok) {
    const detail = await resendResponse.text();
    console.error('Resend API error', resendResponse.status, detail);
    return new Response('Failed to send email', { status: 502 });
  }

  return new Response('ok', { status: 200 });
});
