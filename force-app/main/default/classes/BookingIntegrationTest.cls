/**
 * BookingIntegrationTest
 *
 * Test coverage for BookingIntegrationService.cls
 *
 * TEST SCENARIOS:
 *   Positive  — 200 OK successfully parses booking data (all fields mapped)
 *   Negative  — Blank/null booking reference validation
 *   Error     — 404 Not Found handling
 *   Error     — 500 Internal Server Error handling
 *   Error     — Network CalloutException (timeout/connection failure)
 *   Error     — Malformed / invalid JSON response body
 *   Error     — 200 OK response with missing "data" property
 *   DML       — Updating Case record with BookingData
 *   DML       — Null parameter validation for updateCaseWithBookingData
 *
 * @author   Muthukumar
 * @version  1.0
 */
@IsTest
private class BookingIntegrationTest {

    // ─── Test Callout Mock ───────────────────────────────────────────────────
    /**
     * Reusable HTTP mock for simulating different API response scenarios.
     */
    private class BookingHttpMock implements HttpCalloutMock {
        private Integer statusCode;
        private String  body;
        private Boolean throwCalloutException;

        public BookingHttpMock(Integer statusCode, String body) {
            this.statusCode            = statusCode;
            this.body                  = body;
            this.throwCalloutException = false;
        }

        public BookingHttpMock(Boolean throwCalloutException) {
            this.throwCalloutException = throwCalloutException;
            this.statusCode            = 0;
            this.body                  = null;
        }

        public HttpResponse respond(HttpRequest req) {
            if (this.throwCalloutException) {
                CalloutException ex = new CalloutException('Simulated network timeout');
                throw ex;
            }

            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(this.statusCode);
            res.setBody(this.body);
            return res;
        }
    }

    // ─── Sample JSON Fixtures ────────────────────────────────────────────────
    private static final String SUCCESS_RESPONSE_JSON =
        '{' +
        '  "success": true,' +
        '  "data": {' +
        '    "bookingReference": "BK1001",' +
        '    "status": "Confirmed",' +
        '    "supplier": "Demo Rental Services",' +
        '    "vehicle": "Economy SUV",' +
        '    "vehicleCategory": "SUV",' +
        '    "pickupLocation": "Dublin Airport — Terminal 1",' +
        '    "dropoffLocation": "Dublin Airport — Terminal 1",' +
        '    "pickupDateTime": "2026-09-14T12:00:00.000Z",' +
        '    "dropoffDateTime": "2026-09-21T12:00:00.000Z",' +
        '    "paymentStatus": "Paid",' +
        '    "totalAmount": 185.00,' +
        '    "currency": "EUR",' +
        '    "driverName": "Demo Customer A",' +
        '    "additionalNotes": "Free cancellation eligible — pickup more than 48 hours away."' +
        '  },' +
        '  "timestamp": "2026-09-11T12:00:00.000Z"' +
        '}';

    private static final String NOT_FOUND_RESPONSE_JSON =
        '{' +
        '  "error": "booking_not_found",' +
        '  "message": "No booking found for reference: BK9999.",' +
        '  "reference": "BK9999"' +
        '}';

    private static final String SERVER_ERROR_RESPONSE_JSON =
        '{' +
        '  "error": "upstream_error",' +
        '  "message": "The booking system is temporarily unavailable.",' +
        '  "reference": "BK0000"' +
        '}';

    // ─── Positive Callout Tests ──────────────────────────────────────────────

    @IsTest
    static void testGetBookingDetails_Success() {
        // Arrange
        Test.setMock(HttpCalloutMock.class, new BookingHttpMock(200, SUCCESS_RESPONSE_JSON));

        // Act
        Test.startTest();
        BookingIntegrationService.BookingData result =
            BookingIntegrationService.getBookingDetails('BK1001');
        Test.stopTest();

        // Assert
        Assert.isNotNull(result, 'Result should not be null');
        Assert.areEqual('BK1001',                result.bookingReference);
        Assert.areEqual('Confirmed',             result.status);
        Assert.areEqual('Demo Rental Services',   result.supplier);
        Assert.areEqual('Economy SUV',           result.vehicle);
        Assert.areEqual('SUV',                   result.vehicleCategory);
        Assert.areEqual('Dublin Airport — Terminal 1', result.pickupLocation);
        Assert.areEqual('Paid',                  result.paymentStatus);
        Assert.areEqual(185.00,                  result.totalAmount);
        Assert.areEqual('EUR',                   result.currencyCode);
        Assert.areEqual('Demo Customer A',       result.driverName);
        Assert.isTrue(result.additionalNotes.contains('Free cancellation'));
    }

    // ─── Input Validation Tests ──────────────────────────────────────────────

    @IsTest
    static void testGetBookingDetails_BlankReferenceThrowsException() {
        // Act & Assert for null
        try {
            BookingIntegrationService.getBookingDetails(null);
            Assert.fail('Expected BookingIntegrationException for null reference');
        } catch (BookingIntegrationService.BookingIntegrationException e) {
            Assert.isTrue(e.getMessage().contains('cannot be blank'), 'Message should note blank reference');
        }

        // Act & Assert for empty string
        try {
            BookingIntegrationService.getBookingDetails('   ');
            Assert.fail('Expected BookingIntegrationException for whitespace reference');
        } catch (BookingIntegrationService.BookingIntegrationException e) {
            Assert.isTrue(e.getMessage().contains('cannot be blank'), 'Message should note blank reference');
        }
    }

    // ─── HTTP Error Status Tests ─────────────────────────────────────────────

    @IsTest
    static void testGetBookingDetails_NotFound404() {
        // Arrange
        Test.setMock(HttpCalloutMock.class, new BookingHttpMock(404, NOT_FOUND_RESPONSE_JSON));

        // Act & Assert
        Test.startTest();
        try {
            BookingIntegrationService.getBookingDetails('BK9999');
            Assert.fail('Expected BookingIntegrationException for 404 response');
        } catch (BookingIntegrationService.BookingIntegrationException e) {
            Assert.isTrue(e.getMessage().contains('Booking not found'),
                'Exception message should state booking not found. Actual: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetBookingDetails_ServerError500() {
        // Arrange
        Test.setMock(HttpCalloutMock.class, new BookingHttpMock(500, SERVER_ERROR_RESPONSE_JSON));

        // Act & Assert
        Test.startTest();
        try {
            BookingIntegrationService.getBookingDetails('BK0000');
            Assert.fail('Expected BookingIntegrationException for 500 response');
        } catch (BookingIntegrationService.BookingIntegrationException e) {
            Assert.isTrue(e.getMessage().contains('unexpected error'),
                'Exception message should state unexpected error. Actual: ' + e.getMessage());
            Assert.isTrue(e.getMessage().contains('500'),
                'Exception message should include status code 500. Actual: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // ─── Network Failure Tests ───────────────────────────────────────────────

    @IsTest
    static void testGetBookingDetails_CalloutException() {
        // Arrange
        Test.setMock(HttpCalloutMock.class, new BookingHttpMock(true));

        // Act & Assert
        Test.startTest();
        try {
            BookingIntegrationService.getBookingDetails('BK1001');
            Assert.fail('Expected BookingIntegrationException on network timeout');
        } catch (BookingIntegrationService.BookingIntegrationException e) {
            Assert.isTrue(e.getMessage().contains('Network error'),
                'Exception message should describe network error. Actual: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // ─── JSON Parsing Edge Case Tests ────────────────────────────────────────

    @IsTest
    static void testGetBookingDetails_InvalidJson() {
        // Arrange: 200 OK but body is unparseable
        Test.setMock(HttpCalloutMock.class, new BookingHttpMock(200, '<html>502 Bad Gateway</html>'));

        // Act & Assert
        Test.startTest();
        try {
            BookingIntegrationService.getBookingDetails('BK1001');
            Assert.fail('Expected BookingIntegrationException on invalid JSON');
        } catch (BookingIntegrationService.BookingIntegrationException e) {
            Assert.isTrue(e.getMessage().contains('Failed to parse API response JSON'),
                'Exception message should state JSON parse failure. Actual: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetBookingDetails_MissingDataField() {
        // Arrange: valid JSON object but without the "data" node
        Test.setMock(HttpCalloutMock.class, new BookingHttpMock(200, '{"success": true, "message": "no data"}'));

        // Act & Assert
        Test.startTest();
        try {
            BookingIntegrationService.getBookingDetails('BK1001');
            Assert.fail('Expected BookingIntegrationException when "data" field is missing');
        } catch (BookingIntegrationService.BookingIntegrationException e) {
            Assert.isTrue(e.getMessage().contains('contained no "data" field'),
                'Exception message should note missing data field. Actual: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetBookingDetails_CorruptedDataNode() {
        // Arrange: valid JSON, contains "data", but data type doesn't map to BookingData
        Test.setMock(HttpCalloutMock.class, new BookingHttpMock(200, '{"success": true, "data": 12345}'));

        // Act & Assert
        Test.startTest();
        try {
            BookingIntegrationService.getBookingDetails('BK1001');
            Assert.fail('Expected BookingIntegrationException on unmappable data node');
        } catch (BookingIntegrationService.BookingIntegrationException e) {
            Assert.isTrue(e.getMessage().contains('Failed to map API response'),
                'Exception message should indicate mapping failure. Actual: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // ─── Case Update DML Tests ───────────────────────────────────────────────

    @IsTest
    static void testUpdateCaseWithBookingData_Success() {
        // Arrange: create a test Case record
        Case testCase = new Case(
            Subject               = 'Customer enquiry on reservation',
            Description           = 'I want to check my booking details',
            Booking_Reference__c  = 'BK1001',
            Origin                = 'Web'
        );
        insert testCase;

        BookingIntegrationService.BookingData data = new BookingIntegrationService.BookingData();
        data.bookingReference = 'BK1001';
        data.status           = 'Confirmed';
        data.supplier         = 'Demo Rental Services';
        data.vehicle          = 'Economy SUV';
        data.pickupLocation   = 'Dublin Airport — Terminal 1';
        data.paymentStatus    = 'Paid';

        // Act
        Test.startTest();
        BookingIntegrationService.updateCaseWithBookingData(testCase.Id, data);
        Test.stopTest();

        // Assert
        Case updatedCase = [
            SELECT Id, Booking_Status__c, Supplier_Name__c, Vehicle_Class__c,
                   Pickup_Location__c, Payment_Status__c
            FROM Case
            WHERE Id = :testCase.Id
        ];

        Assert.areEqual('Confirmed',                  updatedCase.Booking_Status__c);
        Assert.areEqual('Demo Rental Services',       updatedCase.Supplier_Name__c);
        Assert.areEqual('Economy SUV',                updatedCase.Vehicle_Class__c);
        Assert.areEqual('Dublin Airport — Terminal 1', updatedCase.Pickup_Location__c);
        Assert.areEqual('Paid',                       updatedCase.Payment_Status__c);
    }

    @IsTest
    static void testUpdateCaseWithBookingData_NullCaseId() {
        BookingIntegrationService.BookingData data = new BookingIntegrationService.BookingData();

        try {
            BookingIntegrationService.updateCaseWithBookingData(null, data);
            Assert.fail('Expected exception when caseId is null');
        } catch (BookingIntegrationService.BookingIntegrationException e) {
            Assert.isTrue(e.getMessage().contains('Case Id cannot be null'),
                'Message should validate null case ID');
        }
    }

    @IsTest
    static void testUpdateCaseWithBookingData_NullBookingData() {
        Case testCase = new Case(Subject = 'Test Case', Origin = 'Web');
        insert testCase;

        try {
            BookingIntegrationService.updateCaseWithBookingData(testCase.Id, null);
            Assert.fail('Expected exception when booking is null');
        } catch (BookingIntegrationService.BookingIntegrationException e) {
            Assert.isTrue(e.getMessage().contains('BookingData cannot be null'),
                'Message should validate null booking data');
        }
    }
}
