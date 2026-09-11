/**
 * BookingIntegrationQueueableTest
 *
 * Test coverage for BookingIntegrationQueueable.cls
 *
 * TEST SCENARIOS:
 *   Positive — Single Case ID execution updates booking fields successfully
 *   Positive — Set<Id> bulk execution processes multiple Cases
 *   Negative — 404 Not Found sets Case Booking_Status__c to 'Lookup Failed'
 *   Edge     — Case without Booking_Reference__c is safely bypassed
 *   Edge     — Empty or null Case ID inputs are gracefully handled
 *
 * @author   Muthukumar
 * @version  1.0
 */
@IsTest
private class BookingIntegrationQueueableTest {

    // ─── Callout Mock ────────────────────────────────────────────────────────
    private class MockHttpSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody(
                '{' +
                '  "success": true,' +
                '  "data": {' +
                '    "bookingReference": "BK1001",' +
                '    "status": "Confirmed",' +
                '    "supplier": "Demo Rental Services",' +
                '    "vehicle": "Economy SUV",' +
                '    "pickupLocation": "Dublin Airport — Terminal 1",' +
                '    "paymentStatus": "Paid"' +
                '  }' +
                '}'
            );
            return res;
        }
    }

    private class MockHttpNotFound implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(404);
            res.setBody('{"error": "booking_not_found", "message": "Not found"}');
            return res;
        }
    }

    // ─── Positive Tests ──────────────────────────────────────────────────────

    @IsTest
    static void testQueueable_SingleCaseSuccess() {
        // Arrange
        Case testCase = new Case(
            Subject              = 'Rental assistance inquiry',
            Booking_Reference__c = 'BK1001',
            Origin               = 'Web'
        );
        insert testCase;

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        // Act: Test.startTest / stopTest forces Queueable execution synchronously
        Test.startTest();
        System.enqueueJob(new BookingIntegrationQueueable(testCase.Id));
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
    static void testQueueable_BulkCasesSuccess() {
        // Arrange
        List<Case> caseList = new List<Case>{
            new Case(Subject = 'Case 1', Booking_Reference__c = 'BK1001', Origin = 'Email'),
            new Case(Subject = 'Case 2', Booking_Reference__c = 'BK1002', Origin = 'Email')
        };
        insert caseList;

        Set<Id> caseIds = new Set<Id>{ caseList[0].Id, caseList[1].Id };
        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        // Act
        Test.startTest();
        System.enqueueJob(new BookingIntegrationQueueable(caseIds));
        Test.stopTest();

        // Assert
        List<Case> updatedCases = [
            SELECT Id, Booking_Status__c, Supplier_Name__c
            FROM Case
            WHERE Id IN :caseIds
        ];

        Assert.areEqual(2, updatedCases.size());
        for (Case c : updatedCases) {
            Assert.areEqual('Confirmed',            c.Booking_Status__c);
            Assert.areEqual('Demo Rental Services', c.Supplier_Name__c);
        }
    }

    // ─── Error Handling Tests ────────────────────────────────────────────────

    @IsTest
    static void testQueueable_NotFoundSetsLookupFailed() {
        // Arrange
        Case testCase = new Case(
            Subject              = 'Invalid reference test',
            Booking_Reference__c = 'BK9999',
            Origin               = 'Web'
        );
        insert testCase;

        Test.setMock(HttpCalloutMock.class, new MockHttpNotFound());

        // Act
        Test.startTest();
        System.enqueueJob(new BookingIntegrationQueueable(testCase.Id));
        Test.stopTest();

        // Assert
        Case updatedCase = [
            SELECT Id, Booking_Status__c
            FROM Case
            WHERE Id = :testCase.Id
        ];

        Assert.areEqual('Lookup Failed', updatedCase.Booking_Status__c);
    }

    // ─── Edge Case Tests ─────────────────────────────────────────────────────

    @IsTest
    static void testQueueable_CaseWithoutBookingReferenceBypassed() {
        // Arrange: Case with no Booking_Reference__c
        Case testCase = new Case(
            Subject = 'General inquiry without booking ref',
            Origin  = 'Phone'
        );
        insert testCase;

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        // Act
        Test.startTest();
        System.enqueueJob(new BookingIntegrationQueueable(testCase.Id));
        Test.stopTest();

        // Assert: Case remains untouched
        Case queriedCase = [SELECT Id, Booking_Status__c FROM Case WHERE Id = :testCase.Id];
        Assert.isNull(queriedCase.Booking_Status__c);
    }

    @IsTest
    static void testQueueable_EmptyOrNullInputsHandledGracefully() {
        Test.startTest();
        // Null Id constructor
        System.enqueueJob(new BookingIntegrationQueueable((Id) null));
        // Empty Set constructor
        System.enqueueJob(new BookingIntegrationQueueable(new Set<Id>()));
        // Null Set constructor
        System.enqueueJob(new BookingIntegrationQueueable((Set<Id>) null));
        Test.stopTest();

        // Assert: Completed without unhandled exceptions
        Assert.isTrue(true, 'Empty and null inputs should execute cleanly');
    }
}
