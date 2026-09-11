/**
 * AIInteractionServiceTest
 *
 * Test coverage for AIInteractionService.cls
 *
 * TEST SCENARIOS:
 *   Classification — Vehicle Breakdown (Critical urgency, breakdown procedure)
 *   Classification — Cancellation (Grounded in refund policy)
 *   Classification — Billing (Security deposit & charge details)
 *   Classification — Booking Change (Amendment procedures)
 *   Classification — General Enquiry (Default fallback)
 *   Guardrails     — Legal risk suppression (lawyer/court keywords)
 *   Guardrails     — Safety emergency suppression (injury/ambulance keywords)
 *   Guardrails     — Fraud/dispute suppression (unauthorized charge/scam keywords)
 *   Audit Logging  — Persisting AI interaction to AI_Interaction__c
 *   Case Update    — Applying AI recommendation to Case record
 *
 * @author   Muthukumar
 * @version  1.0
 */
@IsTest
private class AIInteractionServiceTest {

    @TestSetup
    static void setupTestData() {
        // Ensure Knowledge article exists for grounding in test context
        Knowledge__kav article = new Knowledge__kav(
            Title      = 'Test Cancellation and Refund Policy',
            UrlName    = 'test-cancellation-refund-' + System.currentTimeMillis(),
            Summary    = 'Test summary for cancellation and refund rules.',
            Details__c = 'Test policy details: 48h full refund, 24h partial refund.'
        );
        insert article;
        KbManagement.PublishingService.publishArticle(
            [SELECT KnowledgeArticleId FROM Knowledge__kav WHERE Id = :article.Id].KnowledgeArticleId,
            true
        );
    }

    // ─── Classification & Grounding Tests ────────────────────────────────────

    @IsTest
    static void testGenerateAssistance_BreakdownScenario() {
        Case c = new Case(
            Subject              = 'Engine smoke and vehicle breakdown on highway',
            Description          = 'My car broke down near Dublin. Smoke from engine and tyre damaged. Need towing.',
            Booking_Reference__c = 'BK1001',
            Supplier_Name__c     = 'Demo Rental Services',
            Vehicle_Class__c     = 'Economy SUV',
            Origin               = 'Phone'
        );
        insert c;

        Test.startTest();
        AIInteractionService.AIRecommendation rec = AIInteractionService.generateAssistance(c.Id);
        Test.stopTest();

        Assert.areEqual('Vehicle Breakdown', rec.intent,         'Intent should be Vehicle Breakdown');
        Assert.areEqual('Critical',          rec.urgency,        'Urgency should be Critical for breakdown');
        Assert.isTrue(rec.confidenceScore >= 0.90,               'Confidence score should be high');
        Assert.isFalse(rec.isRestricted,                         'Breakdown without legal terms should not be restricted');
        Assert.areEqual('Suggested',         rec.assistanceStatus);
        Assert.isNotNull(rec.suggestedResponse,                  'Suggested response should be generated');
        Assert.isTrue(rec.suggestedResponse.contains('Roadside Assistance'), 'Response should reference Roadside Assistance');
        Assert.isTrue(rec.caseSummary.contains('Vehicle Breakdown'), 'Summary should capture intent');
    }

    @IsTest
    static void testGenerateAssistance_CancellationScenario() {
        Case c = new Case(
            Subject              = 'Cancellation request for booking BK1001',
            Description          = 'I cannot travel and need to cancel my rental booking for a refund.',
            Booking_Reference__c = 'BK1001',
            Supplier_Name__c     = 'Demo Rental Services',
            Origin               = 'Email'
        );
        insert c;

        Test.startTest();
        AIInteractionService.AIRecommendation rec = AIInteractionService.generateAssistance(c.Id);
        Test.stopTest();

        Assert.areEqual('Cancellation', rec.intent);
        Assert.isFalse(rec.isRestricted);
        Assert.isTrue(rec.groundedStatus, 'Should be grounded in published Knowledge article');
        Assert.isTrue(rec.suggestedResponse.contains('Cancellation & Refund Policy'));
    }

    @IsTest
    static void testGenerateAssistance_BillingScenario() {
        Case c = new Case(
            Subject              = 'Unexpected card charge after dropoff',
            Description          = 'I was charged an extra deposit fee on my credit card. Please review this billing item.',
            Booking_Reference__c = 'BK1002',
            Origin               = 'Web'
        );
        insert c;

        Test.startTest();
        AIInteractionService.AIRecommendation rec = AIInteractionService.generateAssistance(c.Id);
        Test.stopTest();

        Assert.areEqual('Billing', rec.intent);
        Assert.areEqual('High',    rec.urgency);
        Assert.isFalse(rec.isRestricted);
        Assert.isTrue(rec.suggestedResponse.contains('security deposit'));
    }

    @IsTest
    static void testGenerateAssistance_BookingChangeScenario() {
        Case c = new Case(
            Subject              = 'Change pickup date and modify vehicle',
            Description          = 'I want to change my reservation to a later time and upgrade vehicle class.',
            Booking_Reference__c = 'BK1003',
            Pickup_Location__c   = 'Dublin Airport',
            Origin               = 'Web'
        );
        insert c;

        Test.startTest();
        AIInteractionService.AIRecommendation rec = AIInteractionService.generateAssistance(c.Id);
        Test.stopTest();

        Assert.areEqual('Booking Change', rec.intent);
        Assert.isFalse(rec.isRestricted);
        Assert.isTrue(rec.suggestedResponse.contains('Dublin Airport'));
    }

    @IsTest
    static void testGenerateAssistance_GeneralEnquiryScenario() {
        Case c = new Case(
            Subject     = 'Opening hours inquiry',
            Description = 'What time does the counter open on Sunday?',
            Origin      = 'Web'
        );
        insert c;

        Test.startTest();
        AIInteractionService.AIRecommendation rec = AIInteractionService.generateAssistance(c.Id);
        Test.stopTest();

        Assert.areEqual('General Enquiry', rec.intent);
        Assert.areEqual('Low',             rec.urgency);
        Assert.isFalse(rec.isRestricted);
        Assert.isNotNull(rec.suggestedResponse);
    }

    // ─── Guardrail Enforcement Tests ─────────────────────────────────────────

    @IsTest
    static void testGuardrail_LegalRiskSuppressesDraft() {
        Case c = new Case(
            Subject     = 'Complaint regarding service failure',
            Description = 'Your service was terrible. I have contacted my lawyer and intend to sue in court.',
            Origin      = 'Web'
        );
        insert c;

        Test.startTest();
        AIInteractionService.AIRecommendation rec = AIInteractionService.generateAssistance(c.Id);
        Test.stopTest();

        Assert.isTrue(rec.isRestricted,                     'Legal keywords must trigger guardrail restriction');
        Assert.isNull(rec.suggestedResponse,                'Draft response must be suppressed for legal risk');
        Assert.areEqual('Restricted', rec.assistanceStatus, 'Status should be Restricted');
        Assert.isTrue(rec.restrictionReason.contains('Legal risk detected'));
    }

    @IsTest
    static void testGuardrail_SafetyEmergencySuppressesDraft() {
        Case c = new Case(
            Subject     = 'Severe car crash on highway',
            Description = 'We had a major accident. Passenger injured and police / ambulance on scene.',
            Origin      = 'Phone'
        );
        insert c;

        Test.startTest();
        AIInteractionService.AIRecommendation rec = AIInteractionService.generateAssistance(c.Id);
        Test.stopTest();

        Assert.isTrue(rec.isRestricted,      'Safety emergency must trigger guardrail restriction');
        Assert.isNull(rec.suggestedResponse, 'Draft response must be suppressed for safety emergencies');
        Assert.areEqual('Critical', rec.urgency);
        Assert.isTrue(rec.restrictionReason.contains('Safety emergency detected'));
    }

    @IsTest
    static void testGuardrail_FraudKeywordSuppressesDraft() {
        Case c = new Case(
            Subject     = 'Unauthorized charge dispute',
            Description = 'There is an unauthorized charge and scam on my card. Bank dispute filed for fraud.',
            Origin      = 'Email'
        );
        insert c;

        Test.startTest();
        AIInteractionService.AIRecommendation rec = AIInteractionService.generateAssistance(c.Id);
        Test.stopTest();

        Assert.isTrue(rec.isRestricted,      'Fraud keywords must trigger guardrail restriction');
        Assert.isNull(rec.suggestedResponse, 'Draft response must be suppressed for fraud allegations');
        Assert.isTrue(rec.restrictionReason.contains('fraud risk'));
    }

    // ─── Audit Logging & Case Field Application Tests ────────────────────────

    @IsTest
    static void testLogInteraction_PersistsAuditRecord() {
        Case c = new Case(Subject = 'Audit Log Test', Origin = 'Web');
        insert c;

        Test.startTest();
        Id logId = AIInteractionService.logInteraction(
            c.Id,
            'Response Drafting',
            0.95,
            true,
            'Dear Customer, test response...',
            'Accepted',
            null
        );
        Test.stopTest();

        Assert.isNotNull(logId, 'Audit log Id should be returned');
        AI_Interaction__c log = [
            SELECT Id, Case__c, AI_Task__c, Confidence_Score__c, Grounded_Status__c,
                   Suggested_Response__c, Agent_Action__c
            FROM AI_Interaction__c
            WHERE Id = :logId
        ];

        Assert.areEqual(c.Id,                log.Case__c);
        Assert.areEqual('Response Drafting', log.AI_Task__c);
        Assert.areEqual(0.95,                log.Confidence_Score__c);
        Assert.isTrue(log.Grounded_Status__c);
        Assert.areEqual('Accepted',          log.Agent_Action__c);
    }

    @IsTest
    static void testLogInteraction_NullCaseThrowsException() {
        try {
            AIInteractionService.logInteraction(null, 'Response Drafting', 0.9, true, 'test', 'Accepted', null);
            Assert.fail('Expected IllegalArgumentException for null Case ID');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('Case ID is required'));
        }
    }

    @IsTest
    static void testApplyRecommendationToCase_UpdatesCaseFields() {
        Case c = new Case(Subject = 'Field Update Test', Origin = 'Web');
        insert c;

        AIInteractionService.AIRecommendation rec = new AIInteractionService.AIRecommendation();
        rec.intent           = 'Billing';
        rec.urgency          = 'High';
        rec.confidenceScore  = 0.88;
        rec.assistanceStatus = 'Suggested';

        Test.startTest();
        AIInteractionService.applyRecommendationToCase(c.Id, rec);
        Test.stopTest();

        Case updated = [
            SELECT Id, Case_Intent__c, Urgency__c, AI_Confidence__c, AI_Assistance_Status__c
            FROM Case
            WHERE Id = :c.Id
        ];

        Assert.areEqual('Billing',   updated.Case_Intent__c);
        Assert.areEqual('High',      updated.Urgency__c);
        Assert.areEqual(0.88,        updated.AI_Confidence__c);
        Assert.areEqual('Suggested', updated.AI_Assistance_Status__c);
    }

    @IsTest
    static void testGenerateAssistance_NullCaseThrowsException() {
        try {
            AIInteractionService.generateAssistance(null);
            Assert.fail('Expected IllegalArgumentException for null Case ID');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('Case ID cannot be null'));
        }
    }
}
