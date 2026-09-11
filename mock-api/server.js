/**
 * Mock Booking REST API
 * ─────────────────────────────────────────────────────────────────────────────
 * PURPOSE:
 *   Simulates an external car rental reservation system for use with the
 *   AI-Assisted Case Management System (Salesforce portfolio project).
 *
 *   In a real enterprise context this would be a supplier's booking platform
 *   (e.g., a proprietary reservation system) exposed via REST API.
 *   For this portfolio project we use fictional data and fictional suppliers.
 *
 * ENDPOINT:
 *   GET /api/bookings/:bookingReference
 *
 * SUPPORTED SCENARIOS:
 *   BK1001–BK1005  → Confirmed/Active bookings (various suppliers & vehicles)
 *   BK9999          → Cancelled booking
 *   BK0000          → Triggers a simulated 500 server error
 *   Any other ref   → Returns 404 Booking Not Found
 *
 * DISCLAIMER:
 *   All supplier names, booking data, and customer references are fictional
 *   and used for portfolio/academic demonstration only.
 *
 * USAGE:
 *   npm start          (default port 3000)
 *   PORT=4000 npm start (custom port)
 *
 * @author  Muthukumar
 * @version 1.0
 */

require('dotenv').config();

const express = require('express');
const cors    = require('cors');

const app  = express();
const PORT = process.env.PORT || 3000;

// ─── Middleware ───────────────────────────────────────────────────────────────
app.use(cors());
app.use(express.json());

// ─── Request Logger ──────────────────────────────────────────────────────────
app.use((req, res, next) => {
    const timestamp = new Date().toISOString();
    console.log(`[${timestamp}] ${req.method} ${req.path}`);
    next();
});

// ─── Mock Booking Data ────────────────────────────────────────────────────────
// Fictional bookings with fictional supplier names.
// DO NOT use real company names or real customer data.
const MOCK_BOOKINGS = {

    'BK1001': {
        bookingReference : 'BK1001',
        status           : 'Confirmed',
        supplier         : 'Demo Rental Services',
        vehicle          : 'Economy SUV',
        vehicleCategory  : 'SUV',
        pickupLocation   : 'Dublin Airport — Terminal 1',
        dropoffLocation  : 'Dublin Airport — Terminal 1',
        pickupDateTime   : new Date(Date.now() + 72 * 60 * 60 * 1000).toISOString(), // 72h from now
        dropoffDateTime  : new Date(Date.now() + 168 * 60 * 60 * 1000).toISOString(), // 7 days from now
        paymentStatus    : 'Paid',
        totalAmount      : 185.00,
        currency         : 'EUR',
        driverName       : 'Demo Customer A',
        additionalNotes  : 'Free cancellation eligible — pickup more than 48 hours away.'
    },

    'BK1002': {
        bookingReference : 'BK1002',
        status           : 'Confirmed',
        supplier         : 'CityDrive Rentals',
        vehicle          : 'Compact Hatchback',
        vehicleCategory  : 'Compact',
        pickupLocation   : 'Cork Airport',
        dropoffLocation  : 'Cork City Centre — Grand Parade',
        pickupDateTime   : new Date(Date.now() + 36 * 60 * 60 * 1000).toISOString(), // 36h from now
        dropoffDateTime  : new Date(Date.now() + 84 * 60 * 60 * 1000).toISOString(),
        paymentStatus    : 'Paid',
        totalAmount      : 99.50,
        currency         : 'EUR',
        driverName       : 'Demo Customer B',
        additionalNotes  : 'Partial refund eligible — pickup between 24 and 48 hours away.'
    },

    'BK1003': {
        bookingReference : 'BK1003',
        status           : 'Active',
        supplier         : 'Example Mobility',
        vehicle          : 'Premium Sedan',
        vehicleCategory  : 'Premium',
        pickupLocation   : 'Shannon Airport',
        dropoffLocation  : 'Shannon Airport',
        pickupDateTime   : new Date(Date.now() + 12 * 60 * 60 * 1000).toISOString(), // 12h from now
        dropoffDateTime  : new Date(Date.now() + 60 * 60 * 1000 * 60).toISOString(),
        paymentStatus    : 'Pending Deposit',
        totalAmount      : 310.00,
        currency         : 'EUR',
        driverName       : 'Demo Customer C',
        additionalNotes  : 'Non-refundable — pickup less than 24 hours away.'
    },

    'BK1004': {
        bookingReference : 'BK1004',
        status           : 'Confirmed',
        supplier         : 'Demo Rental Services',
        vehicle          : 'Standard Estate',
        vehicleCategory  : 'Estate',
        pickupLocation   : 'Dublin Airport — Terminal 2',
        dropoffLocation  : 'Galway City Centre',
        pickupDateTime   : new Date(Date.now() + 120 * 60 * 60 * 1000).toISOString(), // 5 days from now
        dropoffDateTime  : new Date(Date.now() + 240 * 60 * 60 * 1000).toISOString(),
        paymentStatus    : 'Paid',
        totalAmount      : 245.00,
        currency         : 'EUR',
        driverName       : 'Demo Customer D',
        additionalNotes  : 'Booking change requested by customer.'
    },

    'BK1005': {
        bookingReference : 'BK1005',
        status           : 'Confirmed',
        supplier         : 'CityDrive Rentals',
        vehicle          : 'People Carrier (7-Seat)',
        vehicleCategory  : 'MPV',
        pickupLocation   : 'Dublin Airport — Terminal 1',
        dropoffLocation  : 'Dublin Airport — Terminal 1',
        pickupDateTime   : new Date(Date.now() + 96 * 60 * 60 * 1000).toISOString(),
        dropoffDateTime  : new Date(Date.now() + 192 * 60 * 60 * 1000).toISOString(),
        paymentStatus    : 'Paid',
        totalAmount      : 420.00,
        currency         : 'EUR',
        driverName       : 'Demo Customer E',
        additionalNotes  : 'General enquiry about pickup documentation requirements.'
    },

    'BK9999': {
        bookingReference : 'BK9999',
        status           : 'Cancelled',
        supplier         : 'Example Mobility',
        vehicle          : 'Economy Hatchback',
        vehicleCategory  : 'Economy',
        pickupLocation   : 'Dublin Airport — Terminal 1',
        dropoffLocation  : 'Dublin Airport — Terminal 1',
        pickupDateTime   : new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString(), // In the past
        dropoffDateTime  : new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
        paymentStatus    : 'Refunded',
        totalAmount      : 0.00,
        currency         : 'EUR',
        driverName       : 'Demo Customer F',
        additionalNotes  : 'Booking previously cancelled. Full refund processed.'
    }
};

// ─── GET /api/bookings/:bookingReference ──────────────────────────────────────
/**
 * Retrieve booking details by reference number.
 *
 * Responses:
 *   200 OK           — Booking found, returns booking JSON
 *   404 Not Found    — Booking reference does not exist in our records
 *   500 Server Error — Simulated upstream failure (triggered by BK0000)
 */
app.get('/api/bookings/:bookingReference', (req, res) => {
    const ref = req.params.bookingReference.trim().toUpperCase();

    // Simulated server error — useful for testing Salesforce error-handling paths
    if (ref === 'BK0000') {
        console.error(`[SIMULATED ERROR] Upstream booking system failure for ref: ${ref}`);
        return res.status(500).json({
            error     : 'upstream_error',
            message   : 'The booking system is temporarily unavailable. Please try again later.',
            reference : ref,
            timestamp : new Date().toISOString()
        });
    }

    const booking = MOCK_BOOKINGS[ref];

    if (!booking) {
        console.warn(`[NOT FOUND] No booking found for reference: ${ref}`);
        return res.status(404).json({
            error     : 'booking_not_found',
            message   : `No booking found for reference: ${ref}. Please verify the reference and try again.`,
            reference : ref,
            timestamp : new Date().toISOString()
        });
    }

    console.log(`[SUCCESS] Returning booking data for: ${ref}`);
    return res.status(200).json({
        success   : true,
        data      : booking,
        timestamp : new Date().toISOString()
    });
});

// ─── GET /health ──────────────────────────────────────────────────────────────
// Simple health check endpoint — useful for Named Credential validation
app.get('/health', (req, res) => {
    res.status(200).json({
        status    : 'ok',
        service   : 'Mock Booking API',
        version   : '1.0.0',
        timestamp : new Date().toISOString()
    });
});

// ─── 404 Handler ──────────────────────────────────────────────────────────────
app.use((req, res) => {
    res.status(404).json({
        error   : 'endpoint_not_found',
        message : `Endpoint ${req.method} ${req.path} does not exist on this server.`,
        hint    : 'Try GET /api/bookings/:bookingReference'
    });
});

// ─── Start Server ─────────────────────────────────────────────────────────────
app.listen(PORT, () => {
    console.log('─────────────────────────────────────────');
    console.log('  Mock Booking API — Started');
    console.log(`  Listening on: http://localhost:${PORT}`);
    console.log('');
    console.log('  Available test bookings:');
    console.log('    BK1001  → Confirmed (Demo Rental Services, Full refund eligible)');
    console.log('    BK1002  → Confirmed (CityDrive Rentals, Partial refund eligible)');
    console.log('    BK1003  → Active    (Example Mobility, Non-refundable)');
    console.log('    BK1004  → Confirmed (Demo Rental Services, Booking change)');
    console.log('    BK1005  → Confirmed (CityDrive Rentals, General enquiry)');
    console.log('    BK9999  → Cancelled (Already refunded)');
    console.log('    BK0000  → Simulates 500 server error');
    console.log('');
    console.log('  Health check: GET /health');
    console.log('─────────────────────────────────────────');
});

module.exports = app; // Exported for testing
