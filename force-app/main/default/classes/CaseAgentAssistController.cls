/**
 * CaseAgentAssistController
 *
 * PURPOSE:
 *   Apex controller exposing @AuraEnabled methods for the `caseAgentAssist`
 *   Lightning Web Component on the Case Record Page layout.
 *
 * RESPONSIBILITIES:
 *   1. Queries Case details and live booking data.
 *   2. Generates grounded AI recommendations and evaluates guardrails.
 *   3. Enqueues asynchronous booking sync requests.
 *   4. Persists human-in-the-loop decisions (Approved, Edited, Rejected, Escalated)
 *      and logs audit records to AI_Interaction__c.
 *
 * @author   Muthukumar
 * @version  1.0
 */
public with sharing class CaseAgentAssistController {

    // ─── DTO: CaseDetailsWrapper ──────────────────────────────────────────────
    public class CaseDetailsWrapper {
        @AuraEnabled public Case                                  caseRecord         { get; set; }
        @AuraEnabled public AIInteractionService.AIRecommendation aiRecommendation   { get; set; }
        @AuraEnabled public List<AI_Interaction__c>               recentInteractions { get; set; }
    }

    // ─── getCaseDetails ───────────────────────────────────────────────────────
    /**
     * Loads the Case record, runs AI assistance evaluation, and fetches recent AI logs.
     *
     * @param caseId Salesforce Case ID.
     * @return CaseDetailsWrapper Consolidated payload for the LWC.
     */
    @AuraEnabled
    public static CaseDetailsWrapper getCaseDetails(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('Case ID is required.');
        }

        CaseDetailsWrapper wrapper = new CaseDetailsWrapper();

        // 1. Fetch Case record
        wrapper.caseRecord = [
            SELECT Id, CaseNumber, Subject, Description, Priority, Status,
                   Booking_Reference__c, Booking_Status__c, Supplier_Name__c,
                   Vehicle_Class__c, Pickup_Location__c, Payment_Status__c,
                   Case_Intent__c, Urgency__c, AI_Confidence__c, AI_Assistance_Status__c
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        // 2. Generate live AI assistance
        wrapper.aiRecommendation = AIInteractionService.generateAssistance(caseId);

        // 3. Fetch past AI audit interactions for this Case
        wrapper.recentInteractions = [
            SELECT Id, AI_Task__c, Confidence_Score__c, Grounded_Status__c,
                   Suggested_Response__c, Agent_Action__c, Override_Reason__c, CreatedDate
            FROM AI_Interaction__c
            WHERE Case__c = :caseId
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];

        return wrapper;
    }

    // ─── refreshAIAssistance ──────────────────────────────────────────────────
    /**
     * Re-runs the AI triage, grounding, and draft generation engine on demand.
     *
     * @param caseId Salesforce Case ID.
     * @return AIRecommendation Refreshed recommendation.
     */
    @AuraEnabled
    public static AIInteractionService.AIRecommendation refreshAIAssistance(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('Case ID is required.');
        }
        try {
            return AIInteractionService.generateAssistance(caseId);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to generate AI assistance: ' + e.getMessage());
        }
    }

    // ─── saveAgentAction ──────────────────────────────────────────────────────
    /**
     * Records human-in-the-loop agent review action, updates the parent Case status,
     * and logs the decision to AI_Interaction__c for compliance and dashboard metrics.
     *
     * @param caseId          Salesforce Case ID.
     * @param agentAction     Accepted, Edited, Rejected, or Escalated.
     * @param responseText    The final approved/edited text (or null if rejected).
     * @param overrideReason  Agent reason when editing or rejecting.
     * @param confidenceScore Model confidence score.
     * @param groundedStatus  Whether the suggestion was grounded in Knowledge.
     * @return Id             Record ID of the created AI_Interaction__c audit log.
     */
    @AuraEnabled
    public static Id saveAgentAction(
        Id      caseId,
        String  agentAction,
        String  responseText,
        String  overrideReason,
        Decimal confidenceScore,
        Boolean groundedStatus
    ) {
        if (caseId == null) {
            throw new AuraHandledException('Case ID is required.');
        }
        if (String.isBlank(agentAction)) {
            throw new AuraHandledException('Agent action (Accepted, Edited, Rejected, Escalated) is required.');
        }

        try {
            // 1. Map agent action to Case AI_Assistance_Status__c picklist
            String newStatus;
            if (agentAction == 'Accepted') {
                newStatus = 'Approved';
            } else if (agentAction == 'Edited') {
                newStatus = 'Edited';
            } else if (agentAction == 'Rejected') {
                newStatus = 'Restricted';
            } else if (agentAction == 'Escalated') {
                newStatus = 'Escalated';
            } else {
                newStatus = 'Approved';
            }

            Case c = new Case(
                Id                      = caseId,
                AI_Assistance_Status__c = newStatus
            );
            update c;

            // 2. Insert audit log record
            Id logId = AIInteractionService.logInteraction(
                caseId,
                'Response Drafting',
                confidenceScore,
                groundedStatus,
                responseText,
                agentAction,
                overrideReason
            );

            return logId;

        } catch (Exception e) {
            throw new AuraHandledException('Error saving agent action: ' + e.getMessage());
        }
    }

    // ─── syncBookingData ──────────────────────────────────────────────────────
    /**
     * Triggers asynchronous Queueable refresh of external booking data.
     *
     * @param caseId Salesforce Case ID.
     */
    @AuraEnabled
    public static void syncBookingData(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('Case ID is required.');
        }
        try {
            System.enqueueJob(new BookingIntegrationQueueable(caseId));
        } catch (Exception e) {
            throw new AuraHandledException('Failed to enqueue booking sync: ' + e.getMessage());
        }
    }
}
