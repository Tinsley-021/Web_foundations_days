# TicketHub: Ticketing System Design

## 1. Requirements

### Functional requirements
- Browse and search events.
- View event details and seat availability.
- Temporarily hold available seats.
- Pay for held seats and receive tickets.
- View tickets and order history.
- Release a hold or let it expire.

### Non-functional requirements
- **Speed:** Common event and seat-map reads should be fast, with a target under 300 ms when possible.
- **Correctness:** A seat must never be sold to more than one person. Order and payment status must remain consistent.
- **Fairness:** Limit automated abuse and give buyers a reasonable chance during high-demand sales. Expired holds return seats to availability.
- **Availability:** Browsing should remain available during traffic spikes, even if checkout must be queued or rate-limited.
- **Security:** Users can access only their own orders and tickets. Payment details are handled by a payment provider.

## 2. Estimates

There are 2 million registered users.

### Normal day
- 50,000 visitors × 10 page views = **500,000 page views/day**.
- Average: 500,000 ÷ 86,400 ≈ **5.8 page views/second**.
- 5,000 tickets sold/day ≈ **0.06 tickets/second on average**.

These are averages; actual traffic will have bursts.

### Popular concert sale
- 200,000 people try to buy 20,000 seats in 10 minutes.
- Average arrival rate: 200,000 ÷ 600 ≈ **333 people/second**.
- There are **10 potential buyers per seat**.

The sale creates a concentrated burst of seat-map reads, hold attempts, and checkout requests—far above normal traffic. The system scales reads separately and uses a waiting room, rate limits, and controlled checkout concurrency. The database remains the authority on seat availability.

## 3. API

Requests and responses use JSON. Authentication is required where appropriate.

| Method and endpoint | Purpose |
|---|---|
| `GET /events?query=&date=` | Browse and search events |
| `GET /events/{eventId}` | View event details |
| `GET /events/{eventId}/seats` | View the seat map and availability |
| `POST /holds` | Hold seats temporarily; return a hold ID and expiry |
| `DELETE /holds/{holdId}` | Release a hold |
| `POST /orders` | Create an order from a valid hold and initiate payment |
| `GET /orders/{orderId}` | View order and payment status |
| `GET /me/tickets` | View the signed-in user’s tickets |

Hold and order creation should support idempotency keys so retries do not create duplicate holds or charges.

## 4. Data model

- **Users** (`id`, `email`, `created_at`)  
  One user can have many orders and holds.

- **Events** (`id`, `name`, `venue`, `starts_at`, `sale_starts_at`)  
  One event has many seats.

- **Seats** (`id`, `event_id`, `section`, `row`, `number`, `price`, `status`, `hold_id`, `hold_expires_at`)  
  Each seat belongs to one event. A unique constraint on `(event_id, section, row, number)` prevents duplicate seat records.

- **Holds** (`id`, `user_id`, `expires_at`, `status`)  
  A hold belongs to a user and can cover multiple seats. Seats reference their active hold.

- **Orders** (`id`, `user_id`, `status`, `total`, `created_at`, `payment_reference`)  
  Each order belongs to one user and can contain multiple tickets.

- **OrderItems** (`id`, `order_id`, `seat_id`, `price`)  
  Connects orders to seats. A unique constraint on `seat_id` prevents a seat from appearing in two orders.

Foreign keys enforce relationships. Seat status values include `available`, `held`, and `sold`; order status values include `pending`, `paid`, and `cancelled`.

## 5. Architecture

```text
                         ┌──────────────────┐
                         │   Web / Mobile   │
                         └────────┬─────────┘
                                  │
                         ┌────────▼─────────┐
                         │ CDN + WAF        │
                         │ static files,    │
                         │ traffic filtering│
                         └────────┬─────────┘
                                  │
                         ┌────────▼─────────┐
                         │ Load balancer    │
                         └────────┬─────────┘
                                  │
                 ┌────────────────▼────────────────┐
                 │ Stateless application servers   │
                 │ events, seats, holds, orders    │
                 └───────┬───────────────┬────────┘
                         │               │
                 ┌───────▼──────┐  ┌─────▼──────────┐
                 │ Redis cache  │  │ Queue /        │
                 │ event reads  │  │ waiting room   │
                 └──────────────┘  └─────┬──────────┘
                                         │
                                  ┌──────▼──────────┐
                                  │ Relational DB   │
                                  │ transactions,   │
                                  │ constraints     │
                                  └──────┬──────────┘
                                         │
                                  ┌──────▼──────────┐
                                  │ Payment provider│
                                  └─────────────────┘
