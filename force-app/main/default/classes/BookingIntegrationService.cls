/**
 * BookingIntegrationService
 *
 * PURPOSE:
 *   Handles outbound HTTP callouts to the external Mock Booking API.
 *   Retrieves rental reservation data by booking reference and provides
 *   a method to write that data back to the Salesforce Case record.
 *
 * INTEGRATION PATTERN:
 *   Uses a Salesforce Named Credential ('Mock_Booking_API') so the
 *   endpoint URL and any future authentication headers are stored
 *   securely in Salesforce Setup — never hardcoded in source code.
 *
 * CALLOUT NOTE:
 *   This class must NOT be called from a synchronous trigger context.
 *   Use BookingIntegrationQueueable to invoke it asynchronously.
 *   (Salesforce governor rule: no callouts in synchronous trigger execution
 *   if the trigger was fired by a DML operation in the same transaction.)
 *
 * SUPPORTED HTTP RESPONSES FROM MOCK API:
 *   200 OK   → Parse BookingData and return
 *   404      → Throw BookingIntegrationException('Booking not found')
 *   Other    → Throw BookingIntegrationException with HTTP status
 *
 * @author   Muthukumar
 * @version  1.0
 */
public with sharing class BookingIntegrationService {

    // ─── Configuration ────────────────────────────────────────────────────────
    // Named Credential label set in Salesforce Setup → Named Credentials
    // URL updated to your ngrok URL when running locally:
    //   e.g. https://abc123.ngrok-free.app
    @TestVisible private static final String NAMED_CREDENTIAL = 'callout:Mock_Booking_API';
    @TestVisible private static final String BOOKINGS_PATH    = '/api/bookings/';
    @TestVisible private static final Integer TIMEOUT_MS      = 10000; // 10 seconds

    // ─── Inner: BookingData ───────────────────────────────────────────────────
    /**
     * Typed wrapper for the booking data returned by the API.
     * Field names match the JSON keys in the mock API response exactly
     * so JSON.deserialize() maps them automatically.
     */
    public class BookingData {
        public String  bookingReference  { get; set; }
        public String  status            { get; set; }
        public String  supplier          { get; set; }
        public String  vehicle           { get; set; }
        public String  vehicleCategory   { get; set; }
        public String  pickupLocation    { get; set; }
        public String  dropoffLocation   { get; set; }
        public String  pickupDateTime    { get; set; }
        public String  paymentStatus     { get; set; }
        public Decimal totalAmount       { get; set; }
        public String  currencyCode      { get; set; }
        public String  driverName        { get; set; }
        public String  additionalNotes   { get; set; }
    }

    // ─── Custom Exception ─────────────────────────────────────────────────────
    /**
     * Thrown when the API returns a non-200 response or the response
     * cannot be parsed. Callers (e.g. BookingIntegrationQueueable) catch
     * this specifically to log errors without swallowing unexpected exceptions.
     */
    public class BookingIntegrationException extends Exception {}

    // ─── getBookingDetails ────────────────────────────────────────────────────
    /**
     * Fetches booking details from the external mock booking API.
     *
     * @param  bookingReference  The booking reference (e.g., 'BK1001'). Must not be blank.
     * @return BookingData       Parsed booking information from the API response.
     * @throws BookingIntegrationException  On blank input, 404, or non-200 HTTP response.
     *
     * GOVERNOR LIMITS: One HTTP callout per call. Zero SOQL queries.
     * Must be called from an async context (Queueable, Future, Batch) only.
     */
    public static BookingData getBookingDetails(String bookingReference) {

        // ── Input Validation ─────────────────────────────────────────────────
        if (String.isBlank(bookingReference)) {
            throw new BookingIntegrationException(
                'Booking reference cannot be blank. Provide a valid reference (e.g., BK1001).'
            );
        }

        // ── Build HTTP Request ────────────────────────────────────────────────
        String endpoint = NAMED_CREDENTIAL
            + BOOKINGS_PATH
            + EncodingUtil.urlEncode(bookingReference.trim().toUpperCase(), 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(TIMEOUT_MS);
        req.setHeader('Accept', 'application/json');

        // ── Send Request ──────────────────────────────────────────────────────
        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (System.CalloutException e) {
            // Network-level failure (timeout, DNS, TLS etc.)
            throw new BookingIntegrationException(
                'Network error calling booking API: ' + e.getMessage()
            );
        }

        Integer statusCode = res.getStatusCode();

        // ── Handle Response ───────────────────────────────────────────────────
        if (statusCode == 200) {
            return parseSuccessResponse(res.getBody(), bookingReference);

        } else if (statusCode == 404) {
            throw new BookingIntegrationException(
                'Booking not found for reference: ' + bookingReference +
                '. The customer should verify the reference number.'
            );

        } else {
            // 500 or any other non-success code
            String truncatedBody = res.getBody() != null
                ? res.getBody().abbreviate(300)
                : '(empty response)';
            throw new BookingIntegrationException(
                'Booking API returned an unexpected error. ' +
                'HTTP Status: ' + statusCode + '. ' +
                'Response: '    + truncatedBody
            );
        }
    }

    // ─── updateCaseWithBookingData ────────────────────────────────────────────
    /**
     * Writes the retrieved booking data to the corresponding Salesforce Case record.
     * Uses a minimal Case object (Id + only updated fields) to avoid overwriting
     * unrelated fields accidentally.
     *
     * @param caseId   Salesforce Case record Id to update.
     * @param booking  BookingData object returned by getBookingDetails().
     * @throws BookingIntegrationException  If caseId or booking is null.
     *
     * GOVERNOR LIMITS: One DML operation (update). Zero SOQL queries.
     */
    public static void updateCaseWithBookingData(Id caseId, BookingData booking) {

        if (caseId == null) {
            throw new BookingIntegrationException('Case Id cannot be null.');
        }
        if (booking == null) {
            throw new BookingIntegrationException('BookingData cannot be null.');
        }

        Case c = new Case(
            Id               = caseId,
            Booking_Status__c  = booking.status,
            Supplier_Name__c   = booking.supplier,
            Vehicle_Class__c   = booking.vehicle,
            Pickup_Location__c = booking.pickupLocation,
            Payment_Status__c  = booking.paymentStatus
        );

        try {
            update c; // with sharing enforced at class level
        } catch (DmlException e) {
            throw new BookingIntegrationException(
                'Failed to update Case ' + caseId + ' with booking data: ' + e.getMessage()
            );
        }
    }

    // ─── Private: parseSuccessResponse ───────────────────────────────────────
    /**
     * Parses a 200 OK response body from the booking API.
     * Extracts the nested 'data' object and deserialises it into BookingData.
     *
     * Private method — tested indirectly through getBookingDetails().
     */
    private static BookingData parseSuccessResponse(String responseBody, String bookingReference) {
        Map<String, Object> responseMap;
        try {
            responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        } catch (Exception e) {
            throw new BookingIntegrationException(
                'Failed to parse API response JSON for reference: ' + bookingReference +
                '. Raw response: ' + responseBody.abbreviate(200)
            );
        }

        Object dataObj = responseMap.get('data');
        if (dataObj == null) {
            throw new BookingIntegrationException(
                'API returned 200 but the response body contained no "data" field. ' +
                'Reference: ' + bookingReference
            );
        }

        try {
            String dataJson = JSON.serialize(dataObj);
            // 'currency' is a reserved keyword in Apex; replace key before deserializing
            dataJson = dataJson.replace('"currency":', '"currencyCode":');
            return (BookingData) JSON.deserialize(dataJson, BookingData.class);
        } catch (Exception e) {
            throw new BookingIntegrationException(
                'Failed to map API response to BookingData for reference: ' + bookingReference +
                '. Error: ' + e.getMessage()
            );
        }
    }
}
