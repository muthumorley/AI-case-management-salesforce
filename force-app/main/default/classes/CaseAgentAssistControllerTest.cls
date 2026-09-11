/**
 * CaseAgentAssistControllerTest
 *
 * Test coverage for CaseAgentAssistController.cls
 *
 * TEST SCENARIOS:
 *   Query      — getCaseDetails fetches Case, AI recommendations, and past audit logs
 *   Refresh    — refreshAIAssistance re-runs evaluation on demand
 *   Action     — saveAgentAction records 'Accepted' and updates Case status to 'Approved'
 *   Action     — saveAgentAction records 'Edited' with override reason and updates to 'Edited'
 *   Action     — saveAgentAction records 'Rejected' and updates to 'Restricted'
 *   Action     — saveAgentAction records 'Escalated' and updates to 'Escalated'
 *   Queueable  — syncBookingData enqueues async booking lookup
 *   Validation — Null ID handling raises AuraHandledException
 *
 * @author   Muthukumar
 * @version  1.0
 */
@IsTest
private class CaseAgentAssistControllerTest {

    private class MockHttpSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody(
                '{ "success": true, "data": { "bookingReference": "BK1001", "status": "Confirmed", "supplier": "Demo Rental Services", "vehicle": "Economy SUV", "pickupLocation": "Dublin Airport — Terminal 1", "paymentStatus": "Paid" } }'
            );
            return res;
        }
    }

    @TestSetup
    static void setupTestData() {
        Knowledge__kav article = new Knowledge__kav(
            Title      = 'Cancellation and Refund Policy',
            UrlName    = 'test-cancel-refund-' + System.currentTimeMillis(),
            Summary    = 'Policy guidelines',
            Details__c = '48h refund rules'
        );
        insert article;
        KbManagement.PublishingService.publishArticle(
            [SELECT KnowledgeArticleId FROM Knowledge__kav WHERE Id = :article.Id].KnowledgeArticleId,
            true
        );
    }

    @IsTest
    static void testGetCaseDetails_Success() {
        Case c = new Case(
            Subject              = 'Cancellation request for BK1001',
            Description          = 'I need to cancel booking BK1001',
            Booking_Reference__c = 'BK1001',
            Supplier_Name__c     = 'Demo Rental Services',
            Origin               = 'Web'
        );
        insert c;

        // Insert an existing audit record to test recent logs query
        AIInteractionService.logInteraction(c.Id, 'Response Drafting', 0.95, true, 'Draft 1', 'Accepted', null);

        Test.startTest();
        CaseAgentAssistController.CaseDetailsWrapper wrapper =
            CaseAgentAssistController.getCaseDetails(c.Id);
        Test.stopTest();

        Assert.isNotNull(wrapper,                          'Wrapper should not be null');
        Assert.isNotNull(wrapper.caseRecord,              'Case record should be populated');
        Assert.areEqual(c.Id,                             wrapper.caseRecord.Id);
        Assert.isNotNull(wrapper.aiRecommendation,        'AI recommendation should be generated');
        Assert.areEqual('Cancellation',                   wrapper.aiRecommendation.intent);
        Assert.areEqual(1,                                wrapper.recentInteractions.size(), 'Should return 1 audit record');
    }

    @IsTest
    static void testRefreshAIAssistance_Success() {
        Case c = new Case(
            Subject     = 'Car tyre damaged and broken engine',
            Description = 'Breakdown on motorway',
            Origin      = 'Phone'
        );
        insert c;

        Test.startTest();
        AIInteractionService.AIRecommendation rec =
            CaseAgentAssistController.refreshAIAssistance(c.Id);
        Test.stopTest();

        Assert.isNotNull(rec);
        Assert.areEqual('Vehicle Breakdown', rec.intent);
    }

    @IsTest
    static void testSaveAgentAction_Accepted() {
        Case c = new Case(Subject = 'Test Case', Origin = 'Web');
        insert c;

        Test.startTest();
        Id logId = CaseAgentAssistController.saveAgentAction(
            c.Id,
            'Accepted',
            'Approved response text',
            null,
            0.95,
            true
        );
        Test.stopTest();

        Assert.isNotNull(logId);
        Case updated = [SELECT AI_Assistance_Status__c FROM Case WHERE Id = :c.Id];
        Assert.areEqual('Approved', updated.AI_Assistance_Status__c);

        AI_Interaction__c log = [SELECT Agent_Action__c FROM AI_Interaction__c WHERE Id = :logId];
        Assert.areEqual('Accepted', log.Agent_Action__c);
    }

    @IsTest
    static void testSaveAgentAction_Edited() {
        Case c = new Case(Subject = 'Test Case', Origin = 'Web');
        insert c;

        Test.startTest();
        Id logId = CaseAgentAssistController.saveAgentAction(
            c.Id,
            'Edited',
            'Customer asked for French response',
            'Translated text to French',
            0.92,
            true
        );
        Test.stopTest();

        Case updated = [SELECT AI_Assistance_Status__c FROM Case WHERE Id = :c.Id];
        Assert.areEqual('Edited', updated.AI_Assistance_Status__c);

        AI_Interaction__c log = [SELECT Override_Reason__c FROM AI_Interaction__c WHERE Id = :logId];
        Assert.areEqual('Translated text to French', log.Override_Reason__c);
    }

    @IsTest
    static void testSaveAgentAction_Rejected() {
        Case c = new Case(Subject = 'Test Case', Origin = 'Web');
        insert c;

        Test.startTest();
        Id logId = CaseAgentAssistController.saveAgentAction(
            c.Id,
            'Rejected',
            null,
            'Not aligned with customer tone',
            0.70,
            false
        );
        Test.stopTest();

        Case updated = [SELECT AI_Assistance_Status__c FROM Case WHERE Id = :c.Id];
        Assert.areEqual('Restricted', updated.AI_Assistance_Status__c);
    }

    @IsTest
    static void testSaveAgentAction_Escalated() {
        Case c = new Case(Subject = 'Test Case', Origin = 'Web');
        insert c;

        Test.startTest();
        Id logId = CaseAgentAssistController.saveAgentAction(
            c.Id,
            'Escalated',
            null,
            'Customer demanded manager',
            0.85,
            false
        );
        Test.stopTest();

        Case updated = [SELECT AI_Assistance_Status__c FROM Case WHERE Id = :c.Id];
        Assert.areEqual('Escalated', updated.AI_Assistance_Status__c);
    }

    @IsTest
    static void testSyncBookingData_Success() {
        Case c = new Case(Subject = 'Sync test', Booking_Reference__c = 'BK1001', Origin = 'Web');
        insert c;

        Test.setMock(HttpCalloutMock.class, new MockHttpSuccess());

        Test.startTest();
        CaseAgentAssistController.syncBookingData(c.Id);
        Test.stopTest();

        Case updated = [SELECT Booking_Status__c FROM Case WHERE Id = :c.Id];
        Assert.areEqual('Confirmed', updated.Booking_Status__c);
    }

    @IsTest
    static void testValidation_NullArgumentsThrowException() {
        try {
            CaseAgentAssistController.getCaseDetails(null);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }

        try {
            CaseAgentAssistController.refreshAIAssistance(null);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }

        try {
            CaseAgentAssistController.saveAgentAction(null, 'Accepted', 'text', null, 0.9, true);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }

        try {
            CaseAgentAssistController.syncBookingData(null);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
    }
}
