# TicketHub: Ticketing System Design

## 1. Context and requirements

TicketHub is a website for discovering concerts and events, choosing seats, paying for tickets, and viewing purchased tickets. It has 2 million registered users. The hardest problem is handling a sudden rush for a popular event while ensuring that each seat can be held or sold to only one buyer.

### Goals
- Make events easy to browse and search.
- Show event details, prices, and seat availability.
- Let a buyer hold available seats for a limited period and pay for them.
- Issue tickets only after payment is confirmed.
- Keep browsing responsive during a high-demand sale.
- Prevent duplicate holds, duplicate charges, and double-booked seats.

### Functional requirements
1. Visitors can browse and filter events by keyword and date.
2. Visitors can view an event and its seat map.
3. Signed-in users can hold one or more available seats for a limited time.
4. Users can release their own holds; expired holds become available again.
5. Users can create an order from a valid hold and pay through a payment provider.
6. The system confirms an order and issues tickets only after a verified successful payment.
7. Users can view only their own orders and tickets.
8. The system records failed payments and allows a user to retry while the hold remains valid.

### Non-functional requirements
- **Performance:** event listings target a 300 ms response time at the 95th percentile under normal load; seat-map reads target 500 ms. Checkout API responses target 1 second, excluding time spent waiting on the external payment provider.
- **Correctness:** one seat can have at most one active hold and at most one confirmed sale. Payment and order state must be reconciled safely.
- **Availability:** browsing should remain available during a sale. If checkout capacity is exhausted, the system should queue or reject requests clearly rather than corrupt inventory.
- **Fairness:** use a published waiting-room rule, per-user ticket limits, and rate limits to reduce bots and repeated requests.
- **Security:** HTTPS, authentication for holds/orders/tickets, authorization checks, input validation, secure password hashing, and verified payment webhooks. Do not store raw card details.
- **Scalability:** public event reads must scale separately from inventory-changing operations.
- **Durability:** confirmed purchases and payment outcomes must survive application restarts and be backed up.

### Scope and non-goals
The first version supports assigned seats and one primary region. Ticket resale, dynamic pricing, and active-active multi-region writes are out of scope. These can be considered later if user needs and measured traffic justify them.

## 2. Estimates: normal traffic and big-sale traffic

Given facts:
- 2,000,000 registered users.
- 50,000 visitors on a normal day, with 10 page views per visitor.
- 5,000 tickets sold on a normal day.
- For a popular concert, 200,000 people try to buy 20,000 seats in the first 10 minutes.

### Normal day
- Page views/day = 50,000 × 10 = **500,000**.
- Average page views/second = 500,000 ÷ 86,400 = **5.8 per second**.
- Planning assumption: busy periods reach 5 times the daily average, so plan for approximately **30 page views/second** before adding API calls and static assets.
- Ticket sales/day = **5,000**. Average sales rate = 5,000 ÷ 86,400 = **0.058 tickets/second**, or about **3.5 tickets/minute**. Actual sales are bursty, so this average does not describe checkout peaks.

### Popular concert sale
- Interested users in 10 minutes = 200,000.
- Average arrival rate = 200,000 ÷ 600 seconds = **333 people/second**.
- Competition = 200,000 ÷ 20,000 = **10 interested buyers per seat**.
- Assumption: each arriving buyer makes about 3 API requests during the rush (queue/status, seat or event lookup, and hold/checkout activity). Estimated demand = 200,000 × 3 ÷ 600 = **1,000 API requests/second**.
- Because retries, polling, and page interactions can increase load, use **2,000 API requests/second as an initial design target**, then verify it with load testing. This is a planning target, not a measured guarantee.

### Comparison and implication
The normal average is about 5.8 page views/second, while the sale scenario may generate roughly 1,000 API requests/second under the stated assumption—over 170 times the normal average page-view rate. The request types are not identical, so this is a scale comparison rather than an exact like-for-like ratio. The sudden load is concentrated on one event and on seat holds. Cache public event data, use a waiting room to smooth the burst, and send every inventory-changing operation to the authoritative database.

## 3. API design

Base URL: `/api/v1`. Requests and responses use JSON over HTTPS. Endpoints that create holds, orders, or tickets require authentication. The server must check ownership on every hold, order, and ticket request.

| Method and endpoint | Purpose and example | Success | Important errors |
|---|---|---|---|
| `GET /events?query=music&date=2026-11-01&page=1&limit=20` | Search and paginate public events | `200 OK` with events and pagination metadata | `400 Bad Request` for invalid date/page/limit |
| `GET /events/{eventId}` | Get event name, venue, dates, and sale status | `200 OK` | `404 Not Found` |
| `GET /events/{eventId}/seats` | Get seat IDs, sections, prices, and displayed availability | `200 OK` | `404 Not Found` |
| `POST /events/{eventId}/holds` | Hold a set of seats for a short period | `201 Created` with hold ID and expiry | `401 Unauthorized`, `409 Conflict` if any seat is unavailable, `422 Unprocessable Entity` for invalid selection |
| `DELETE /holds/{holdId}` | Release a hold owned by the signed-in user | `204 No Content` | `401 Unauthorized`, `403 Forbidden`, `404 Not Found` |
| `POST /orders` | Create an order from a valid hold and start payment | `201 Created` with order ID and `PENDING_PAYMENT` status | `401 Unauthorized`, `409 Conflict` for expired/invalid hold, `422 Unprocessable Entity` |
| `GET /me/orders/{orderId}` | View order/payment status for the signed-in user | `200 OK` | `401 Unauthorized`, `403 Forbidden`, `404 Not Found` |
| `GET /me/tickets` | List tickets belonging to the signed-in user | `200 OK` | `401 Unauthorized` |
| `POST /payments/webhook` | Accept a signed payment-provider result | `200 OK` once safely recorded | `400 Bad Request` for invalid signature/body |

### Example: create a hold

Request:

```http
POST /api/v1/events/evt_123/holds
Authorization: Bearer <access-token>
Content-Type: application/json
Idempotency-Key: hold-request-123

{
  "seatIds": ["A-12", "A-13"]
}
```

Response (`201 Created`):

```json
{
  "holdId": "hold_789",
  "eventId": "evt_123",
  "seatIds": ["A-12", "A-13"],
  "expiresAt": "2026-10-19T15:10:00Z"
}
```

If either seat is unavailable, return `409 Conflict` and do not partially hold the requested seats. The server validates the event and seat IDs, checks the user's ticket limit, and performs the hold in one transaction.

### Example: create an order

Request:

```http
POST /api/v1/orders
Authorization: Bearer <access-token>
Content-Type: application/json
Idempotency-Key: order-request-456

{
  "holdId": "hold_789",
  "paymentMethodToken": "token-from-payment-provider"
}
```

Response (`201 Created`):

```json
{
  "orderId": "order_456",
  "status": "PENDING_PAYMENT",
  "totalCents": 12000,
  "currency": "USD"
}
```

The payment token comes from the payment provider; TicketHub never stores raw card details. The verified webhook changes the order to `PAID` or `PAYMENT_FAILED`. The same idempotency key returns the existing logical result after a retry instead of creating a second order or charge.

## 4. Data model

Use PostgreSQL (a relational database) because seat holds and purchases require transactions, foreign keys, unique constraints, and a single authoritative view of inventory. Prices are stored in integer minor units (for example, cents) to avoid floating-point rounding errors.

### Tables and key relationships

- **users:** one user can create many holds and orders.
- **events:** one event has many seats.
- **seats:** each seat belongs to one event and has a current inventory state.
- **holds:** one hold belongs to one user and one event; a hold can include multiple seats.
- **hold_items:** joins holds to seats.
- **orders:** one order belongs to one user and one event.
- **order_items:** joins orders to seats; each sold seat can appear in only one order item.
- **payments:** records payment attempts and unique provider references.

### SQL schema

```sql
CREATE TABLE users (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name TEXT NOT NULL,
  venue TEXT NOT NULL,
  starts_at TIMESTAMPTZ NOT NULL,
  sale_starts_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL CHECK
    (status IN ('DRAFT', 'ON_SALE', 'SOLD_OUT', 'CANCELLED'))
);

CREATE TABLE seats (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_id BIGINT NOT NULL REFERENCES events(id),
  section TEXT NOT NULL,
  row_label TEXT NOT NULL,
  seat_number TEXT NOT NULL,
  price_minor INTEGER NOT NULL CHECK (price_minor >= 0),
  status TEXT NOT NULL CHECK (status IN ('AVAILABLE', 'HELD', 'SOLD')),
  hold_expires_at TIMESTAMPTZ,
  held_by_user_id BIGINT REFERENCES users(id),
  UNIQUE (event_id, section, row_label, seat_number)
);

CREATE TABLE holds (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  event_id BIGINT NOT NULL REFERENCES events(id),
  status TEXT NOT NULL CHECK (status IN ('ACTIVE', 'EXPIRED', 'RELEASED', 'CONVERTED')),
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE hold_items (
  hold_id BIGINT NOT NULL REFERENCES holds(id),
  seat_id BIGINT NOT NULL REFERENCES seats(id),
  PRIMARY KEY (hold_id, seat_id),
  UNIQUE (seat_id)
);

CREATE TABLE orders (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  event_id BIGINT NOT NULL REFERENCES events(id),
  status TEXT NOT NULL CHECK
    (status IN ('PENDING_PAYMENT', 'PAID', 'PAYMENT_FAILED', 'CANCELLED', 'REFUNDED')),
  total_minor INTEGER NOT NULL CHECK (total_minor >= 0),
  currency CHAR(3) NOT NULL,
  idempotency_key TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, idempotency_key)
);

CREATE TABLE order_items (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders(id),
  seat_id BIGINT NOT NULL REFERENCES seats(id),
  price_minor INTEGER NOT NULL CHECK (price_minor >= 0),
  UNIQUE (seat_id)
);

CREATE TABLE payments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders(id),
  provider_reference TEXT UNIQUE,
  status TEXT NOT NULL CHECK
    (status IN ('PENDING', 'SUCCEEDED', 'FAILED', 'REFUNDED')),
  amount_minor INTEGER NOT NULL CHECK (amount_minor >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX events_starts_at_idx ON events(starts_at);
CREATE INDEX seats_event_status_idx ON seats(event_id, status);
CREATE INDEX holds_expiry_idx ON holds(status, expires_at);
CREATE INDEX orders_user_created_idx ON orders(user_id, created_at DESC);
```

`UNIQUE (event_id, section, row_label, seat_number)` prevents duplicate seat definitions. `UNIQUE (seat_id)` on `hold_items` ensures a seat can be part of only one active hold record at a time, and `UNIQUE (seat_id)` on `order_items` prevents a seat from appearing in two orders. When a hold is released or expires, its `hold_items` rows must be deleted inside the same transaction that makes the seats available; the hold history remains in `holds`. A sold seat is never released by the hold-expiry worker.

### How the design prevents double-booking

The database is the source of truth. Redis and the seat map may display slightly stale availability, but neither is allowed to approve a hold or sale.

1. When a hold request arrives, the application starts a PostgreSQL transaction and locks all requested seat rows with `SELECT ... FOR UPDATE`, always in ascending seat-ID order to reduce deadlocks.
2. It checks that every seat is `AVAILABLE`, or that any existing hold has genuinely expired and can safely be cleared. It also checks the event is on sale and the user's ticket limit.
3. It creates one `holds` record, inserts its `hold_items`, and updates all seats to `HELD` with the same expiry and user. All changes commit together. If any seat fails validation, the transaction rolls back, so the user does not receive a partial hold.
4. A competing request for the same seat waits for the row lock. After the first transaction commits, the second request sees that the seat is held and receives `409 Conflict`.
5. At checkout, the application locks the hold and its seats, verifies that the hold belongs to the user and has not expired, and creates a pending order with an idempotency key.
6. After a verified successful payment result, a transaction checks the order is not already paid, marks the order and payment as successful, changes the seats to `SOLD`, inserts the `order_items`, and marks the hold `CONVERTED`. The unique constraint on `order_items.seat_id` is a final database safeguard.
7. Payment webhooks can arrive more than once or out of order. Process them idempotently using the provider reference and order state. If payment succeeds after a hold has expired and the seats have been reallocated, do not confirm those seats; trigger a defined refund/compensation process.
8. A background worker releases expired holds in a transaction. It re-checks `expires_at` and seat status before deleting hold-item rows and changing seats back to `AVAILABLE`, so it cannot release a sold seat.

The hold is time-limited (for example, five minutes). The exact duration is a product decision. Transactions, locks, and constraints work together: the lock serializes simultaneous attempts, while constraints guard against application bugs.

## 5. Architecture and scaling

```text
                    ┌──────────────────────┐
                    │ Web and mobile users │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │ CDN + WAF            │
                    │ static files, filtering│
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │ Waiting room / queue │
                    │ sale admission control│
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │ Load balancer        │
                    └──────────┬───────────┘
                               │
              ┌────────────────▼────────────────┐
              │ Stateless application servers   │
              │ event, seat, hold, order, ticket│
              └────────┬─────────────┬──────────┘
                       │             │
              ┌────────▼──────┐  ┌───▼────────────────┐
              │ Redis cache   │  │ PostgreSQL primary │
              │ public reads  │  │ authoritative writes│
              └───────────────┘  └───────┬────────────┘
                                         │
                                ┌────────▼─────────┐
                                │ Read replicas    │
                                │ browse queries   │
                                └──────────────────┘

              ┌────────────────────────────────────┐
              │ Job queue + background workers     │
              │ expire holds, send tickets,        │
              │ reconcile payment outcomes         │
              └─────────────────┬──────────────────┘
                                │
                       ┌────────▼──────────┐
                       │ Payment provider  │
                       └───────────────────┘
```

### What each component does and why it exists

- **CDN:** serves images, CSS, JavaScript, and other static files near users, reducing application load.
- **WAF and rate limits:** block common malicious traffic and limit abusive repeated requests.
- **Waiting room/queue:** controls the rate users enter a high-demand sale. It reduces the chance that all 200,000 users hit checkout at once. The queue rule must be documented and consistently applied.
- **Load balancer:** spreads requests across healthy application servers and stops sending traffic to unhealthy ones.
- **Stateless application servers:** hold no essential session or inventory state only in local memory. Any server can process the next request, allowing horizontal scaling and failover.
- **Redis:** caches public event details and other read-heavy data. It is not authoritative for seat availability because cached data can be stale.
- **PostgreSQL primary:** owns holds, seats, orders, and payment state. Transactions and constraints protect correctness.
- **Read replicas:** serve event/search queries to reduce load on the primary. Replication can lag, so replicas must not authorize holds or confirm purchases.
- **Job queue and workers:** handle hold expiry, ticket emails, and payment reconciliation asynchronously, avoiding long user-facing requests.
- **Payment provider:** handles sensitive payment details. Signed webhooks report outcomes; idempotent processing prevents duplicate confirmation.

### Big-sale operating plan
1. Load-test the application at the estimated 2,000 requests/second target before the event.
2. Pre-warm cached event pages and seat-map metadata, but validate every hold against PostgreSQL.
3. Open a waiting room and admit buyers at a controlled rate based on measured database capacity.
4. Scale stateless application instances horizontally and keep browse traffic separate from inventory-changing checkout work.
5. Apply per-user ticket limits, rate limits, request timeouts, bounded retries with backoff, and idempotency keys.
6. Monitor p95/p99 latency, queue wait time, HTTP 5xx and 409 rates, database CPU, lock waits, connection-pool use, hold expiry, and payment-webhook delay.
7. If checkout capacity is reached, keep event pages available and show a clear queue/retry message rather than bypassing inventory checks.

### Trade-offs

**1. Redis cache and read replicas versus simpler database-only reads**
- **Benefit:** public event browsing is faster and places less read pressure on PostgreSQL.
- **Cost:** cached data may be stale and replicas may lag. This is acceptable for displaying availability, but not for confirming a hold or sale; those operations always use the primary.

**2. Waiting room versus immediate access**
- **Benefit:** smooths the burst and gives the system a controlled admission rate.
- **Cost:** users wait and may dislike the experience. A published queue policy helps fairness, but the queue itself does not prevent double-booking.

**3. Temporary holds versus no holds**
- **Benefit:** gives buyers time to complete checkout while protecting their selected seats.
- **Cost:** abandoned holds temporarily hide seats from other buyers. A short expiry and reliable worker reduce the impact; the duration must balance convenience and availability.

**4. PostgreSQL transactions versus a distributed inventory system**
- **Benefit:** relational transactions, row locks, and constraints make the first version easier to reason about and test.
- **Cost:** the primary can become a bottleneck at very high scale. Start with indexing, connection-pool tuning, and load tests; consider partitioning or a more complex inventory architecture only if measured results justify it.

## 6. Risks, open questions, and validation

- **Traffic assumption:** the 3 API requests per interested buyer and 2,000 requests/second target are estimates. A load test should measure realistic page polling, retries, and checkout behaviour.
- **Payment arrives after hold expiry:** define whether the system refunds automatically or offers customer support. It must never silently assign a seat already sold to someone else.
- **Queue fairness:** choose and publish first-come-first-served or another explicit rule, including how bots and duplicate sessions are handled.
- **Hold duration and ticket limits:** product owners must set the hold expiry and maximum tickets per user.
- **Cancellation/refund rules:** decide when a cancelled or refunded seat can return to inventory, and ensure the uniqueness model supports that lifecycle safely.
- **Disaster recovery:** configure backups, test restores, and define acceptable recovery time and data loss.
- **Operational validation:** test simultaneous requests for the same seat, duplicate webhook delivery, expired holds, database failover, and a full-sale load test before launch.

## Conclusion

TicketHub should use a relational database as the authoritative inventory store, transactions and row locks to serialize competing seat holds, and uniqueness constraints as a final safeguard against duplicate sales. A waiting room, CDN, cache, read replicas, and horizontally scaled stateless application servers address the high-demand traffic pattern. Each component is included to solve a stated problem, and the assumptions should be verified with load testing before a real concert sale.
