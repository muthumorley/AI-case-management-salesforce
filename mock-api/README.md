# Mock Booking API

A lightweight Node.js Express server that simulates an external car rental reservation system for the **AI-Assisted Case Management System** Salesforce portfolio project.

> **Note**: All booking data, supplier names, and customer references are fictional and used for academic/portfolio demonstration only. This server does not connect to any real booking system.

---

## Quick Start

```bash
# Install dependencies
npm install

# Start the server (default port 3000)
npm start

# Or on a custom port
PORT=4000 npm start
```

The server starts at: `http://localhost:3000`

---

## Endpoint

### `GET /api/bookings/:bookingReference`

Returns booking details for the given reference number.

**Success Response (200)**
```json
{
  "success": true,
  "data": {
    "bookingReference": "BK1001",
    "status": "Confirmed",
    "supplier": "Demo Rental Services",
    "vehicle": "Economy SUV",
    "vehicleCategory": "SUV",
    "pickupLocation": "Dublin Airport — Terminal 1",
    "dropoffLocation": "Dublin Airport — Terminal 1",
    "pickupDateTime": "2026-09-13T10:00:00.000Z",
    "dropoffDateTime": "2026-09-17T10:00:00.000Z",
    "paymentStatus": "Paid",
    "totalAmount": 185.00,
    "currency": "EUR",
    "driverName": "Demo Customer A",
    "additionalNotes": "Free cancellation eligible — pickup more than 48 hours away."
  },
  "timestamp": "2026-09-10T11:00:00.000Z"
}
```

**Not Found Response (404)**
```json
{
  "error": "booking_not_found",
  "message": "No booking found for reference: BK9998. Please verify the reference and try again.",
  "reference": "BK9998",
  "timestamp": "2026-09-10T11:00:00.000Z"
}
```

**Server Error Response (500)** — triggered by reference `BK0000`
```json
{
  "error": "upstream_error",
  "message": "The booking system is temporarily unavailable. Please try again later.",
  "reference": "BK0000",
  "timestamp": "2026-09-10T11:00:00.000Z"
}
```

### `GET /health`

Simple health check endpoint.

```json
{
  "status": "ok",
  "service": "Mock Booking API",
  "version": "1.0.0"
}
```

---

## Test Booking References

| Reference | Status    | Supplier              | Scenario                         |
|-----------|-----------|----------------------|----------------------------------|
| BK1001    | Confirmed | Demo Rental Services | 72h away — Full refund eligible  |
| BK1002    | Confirmed | CityDrive Rentals    | 36h away — Partial refund (50%)  |
| BK1003    | Active    | Example Mobility     | 12h away — Non-refundable        |
| BK1004    | Confirmed | Demo Rental Services | 5 days away — Booking change     |
| BK1005    | Confirmed | CityDrive Rentals    | 4 days away — General enquiry    |
| BK9999    | Cancelled | Example Mobility     | Already cancelled & refunded     |
| BK0000    | —         | —                    | Simulates 500 server error       |

---

## Making a Request with curl

```bash
# Confirmed booking
curl http://localhost:3000/api/bookings/BK1001

# Not found
curl http://localhost:3000/api/bookings/BK9998

# Simulated server error
curl http://localhost:3000/api/bookings/BK0000

# Health check
curl http://localhost:3000/health
```

---

## Connecting to Salesforce

When testing the Salesforce integration locally, use [ngrok](https://ngrok.com/) to expose this server to the internet so Salesforce Developer Org can reach it:

```bash
# In one terminal: start the mock API
npm start

# In another terminal: expose it via ngrok
ngrok http 3000
```

ngrok will give you a public URL like `https://abc123.ngrok-free.app`. Use this as your **Named Credential** endpoint URL in Salesforce Setup.

---

## Connecting from Salesforce Setup (Named Credential)

1. **Setup → Named Credentials → New**
2. Label: `Mock Booking API`
3. Name: `Mock_Booking_API`
4. URL: `https://your-ngrok-url.ngrok-free.app`
5. Identity Type: `Anonymous`
6. Authentication Protocol: `No Authentication`
7. Allow Merge Fields in HTTP Header: `checked`
8. Allow Merge Fields in HTTP Body: `checked`

In Apex, reference it as:
```apex
HttpRequest req = new HttpRequest();
req.setEndpoint('callout:Mock_Booking_API/api/bookings/' + bookingRef);
req.setMethod('GET');
```
