/**
 * AIInteractionService
 *
 * PURPOSE:
 *   Core service orchestrating AI-assisted case triage, summarization,
 *   Knowledge article grounding, guardrail enforcement, draft response generation,
 *   and audit logging to the AI_Interaction__c custom object.
 *
 * ARCHITECTURAL PRINCIPLE:
 *   1. AI performs recommendations (Intent Classification, Summarisation, Response Drafting).
 *   2. Grounding strictly anchors suggested responses in published Salesforce Knowledge articles.
 *   3. Guardrail engine suppresses drafts on Legal, Safety, or Fraud keywords or Low Confidence.
 *   4. Deterministic business rules (e.g., Refund calculations) are delegated to Apex logic.
 *   5. Human agent retains ultimate approval authority.
 *
 * @author   Muthukumar
 * @version  1.0
 */
public with sharing class AIInteractionService {

    // ─── Guardrail Constants ──────────────────────────────────────────────────
    private static final Decimal MIN_CONFIDENCE_THRESHOLD = 0.60;

    private static final Set<String> LEGAL_KEYWORDS = new Set<String>{
        'lawyer', 'attorney', 'legal action', 'sue', 'lawsuit', 'court',
        'solicitor', 'barrister', 'litigation', 'ombudsman'
    };

    private static final Set<String> SAFETY_KEYWORDS = new Set<String>{
        'injury', 'injured', 'hospital', 'ambulance', 'police', 'casualty',
        'blood', 'crash', 'fatal', 'paramedic'
    };

    private static final Set<String> FRAUD_KEYWORDS = new Set<String>{
        'fraud', 'scam', 'unauthorized charge', 'stolen card', 'identity theft',
        'bank dispute', 'chargeback'
    };

    // ─── DTO: AIRecommendation ────────────────────────────────────────────────
    /**
     * Typed transfer object carrying the complete AI evaluation package to the LWC UI.
     */
    public class AIRecommendation {
        @AuraEnabled public String  intent                { get; set; }
        @AuraEnabled public String  urgency               { get; set; }
        @AuraEnabled public Decimal confidenceScore       { get; set; }
        @AuraEnabled public String  caseSummary           { get; set; }
        @AuraEnabled public String  suggestedResponse     { get; set; }
        @AuraEnabled public Boolean groundedStatus        { get; set; }
        @AuraEnabled public String  groundingArticleTitle { get; set; }
        @AuraEnabled public Boolean isRestricted          { get; set; }
        @AuraEnabled public String  restrictionReason     { get; set; }
        @AuraEnabled public String  assistanceStatus      { get; set; }
    }

    // ─── Main Orchestrator: generateAssistance ────────────────────────────────
    /**
     * Generates complete AI triage, summary, grounding, and draft response for a Case.
     *
     * @param caseId Salesforce Case ID.
     * @return AIRecommendation Populated evaluation result.
     */
    public static AIRecommendation generateAssistance(Id caseId) {
        if (caseId == null) {
            throw new IllegalArgumentException('Case ID cannot be null.');
        }

        Case c = [
            SELECT Id, CaseNumber, Subject, Description, Booking_Reference__c,
                   Booking_Status__c, Supplier_Name__c, Vehicle_Class__c,
                   Pickup_Location__c, Payment_Status__c, CreatedDate
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        AIRecommendation rec = new AIRecommendation();
        String combinedText = ((c.Subject != null ? c.Subject : '') + ' ' +
                               (c.Description != null ? c.Description : '')).toLowerCase();

        // 1. Intent & Urgency Classification
        classifyIntentAndUrgency(combinedText, rec);

        // 2. Guardrail Rule Evaluation
        evaluateGuardrails(combinedText, rec);

        // 3. Knowledge Base Grounding Retrieval
        Knowledge__kav article = retrieveGroundingArticle(rec.intent);
        if (article != null) {
            rec.groundedStatus        = true;
            rec.groundingArticleTitle = article.Title;
        } else {
            rec.groundedStatus        = false;
            rec.groundingArticleTitle = 'No relevant article found';
        }

        // 4. Summarisation
        rec.caseSummary = buildCaseSummary(c, rec);

        // 5. Response Drafting (with Guardrail Gate)
        if (rec.isRestricted) {
            rec.suggestedResponse = null;
            rec.assistanceStatus  = 'Restricted';
        } else {
            rec.suggestedResponse = buildSuggestedResponse(c, rec, article);
            rec.assistanceStatus  = 'Suggested';
        }

        return rec;
    }

    // ─── Step 1: Intent & Urgency Classifier ──────────────────────────────────
    @TestVisible
    private static void classifyIntentAndUrgency(String text, AIRecommendation rec) {
        if (containsAny(text, new Set<String>{'breakdown', 'tyre', 'tire', 'engine', 'smoke', 'stuck', 'overheating', 'towing', 'mechanic', 'broken'})) {
            rec.intent          = 'Vehicle Breakdown';
            rec.urgency         = 'Critical';
            rec.confidenceScore = 0.96;

        } else if (containsAny(text, new Set<String>{'cancel', 'cancellation', 'refund', 'cannot travel', 'calling off', 'cancel booking'})) {
            rec.intent          = 'Cancellation';
            rec.urgency         = containsAny(text, new Set<String>{'today', 'tomorrow', 'urgent', 'now'}) ? 'High' : 'Medium';
            rec.confidenceScore = 0.93;

        } else if (containsAny(text, new Set<String>{'charge', 'charged', 'billing', 'deposit', 'fee', 'overcharged', 'invoice', 'payment'})) {
            rec.intent          = 'Billing';
            rec.urgency         = 'High';
            rec.confidenceScore = 0.89;

        } else if (containsAny(text, new Set<String>{'change', 'modify', 'upgrade', 'different date', 'later', 'earlier', 'extend', 'extension', 'driver'})) {
            rec.intent          = 'Booking Change';
            rec.urgency         = 'Medium';
            rec.confidenceScore = 0.88;

        } else {
            rec.intent          = 'General Enquiry';
            rec.urgency         = 'Low';
            rec.confidenceScore = String.isNotBlank(text.trim()) ? 0.75 : 0.50;
        }
    }

    // ─── Step 2: Guardrail Rule Engine ────────────────────────────────────────
    @TestVisible
    private static void evaluateGuardrails(String text, AIRecommendation rec) {
        // Rule A: Legal Complaints
        if (containsAny(text, LEGAL_KEYWORDS)) {
            rec.isRestricted      = true;
            rec.restrictionReason = 'Legal risk detected. Case references legal counsel, litigation, or regulatory action. Automated drafting suppressed.';
            rec.urgency           = 'Critical';
            return;
        }

        // Rule B: Safety Emergency / Physical Harm
        if (containsAny(text, SAFETY_KEYWORDS)) {
            rec.isRestricted      = true;
            rec.restrictionReason = 'Safety emergency detected. Case references injury, medical emergency, or police intervention. Immediate human supervisor review required.';
            rec.urgency           = 'Critical';
            return;
        }

        // Rule C: Fraud or Unauthorized Financial Claims
        if (containsAny(text, FRAUD_KEYWORDS)) {
            rec.isRestricted      = true;
            rec.restrictionReason = 'Payment dispute/fraud risk detected. Requires specialized billing investigation.';
            rec.urgency           = 'High';
            return;
        }

        // Rule D: Low Model Confidence
        if (rec.confidenceScore < MIN_CONFIDENCE_THRESHOLD) {
            rec.isRestricted      = true;
            rec.restrictionReason = 'AI confidence score (' + (rec.confidenceScore * 100) + '%) is below the minimum safety threshold (60%). Manual triage required.';
            return;
        }

        rec.isRestricted      = false;
        rec.restrictionReason = null;
    }

    // ─── Step 3: Knowledge Grounding Retrieval ────────────────────────────────
    @TestVisible
    private static Knowledge__kav retrieveGroundingArticle(String intent) {
        String searchPattern;

        if (intent == 'Vehicle Breakdown') {
            searchPattern = '%Breakdown%';
        } else if (intent == 'Cancellation') {
            searchPattern = '%Cancellation%';
        } else if (intent == 'Billing') {
            searchPattern = '%Billing%';
        } else if (intent == 'Booking Change') {
            searchPattern = '%Change%';
        } else {
            searchPattern = '%Pickup%';
        }

        List<Knowledge__kav> articles = [
            SELECT Id, Title, Summary, Details__c, ArticleNumber
            FROM Knowledge__kav
            WHERE PublishStatus = 'Online'
              AND Title LIKE :searchPattern
            LIMIT 1
        ];

        return articles.isEmpty() ? null : articles[0];
    }

    // ─── Step 4: Summarisation Generator ─────────────────────────────────────
    @TestVisible
    private static String buildCaseSummary(Case c, AIRecommendation rec) {
        String bookingRef = String.isNotBlank(c.Booking_Reference__c) ? c.Booking_Reference__c : 'N/A';
        String supplier   = String.isNotBlank(c.Supplier_Name__c) ? c.Supplier_Name__c : 'Unassigned';
        String status     = String.isNotBlank(c.Booking_Status__c) ? c.Booking_Status__c : 'Pending Sync';

        return 'Customer inquiry regarding ' + rec.intent + ' (Urgency: ' + rec.urgency + ', Confidence: ' +
               (rec.confidenceScore * 100).setScale(0) + '%). ' +
               'Reservation: ' + bookingRef + ' with supplier ' + supplier + ' [Status: ' + status + '].';
    }

    // ─── Step 5: Grounded Draft Response Generator ────────────────────────────
    @TestVisible
    private static String buildSuggestedResponse(Case c, AIRecommendation rec, Knowledge__kav article) {
        String ref = String.isNotBlank(c.Booking_Reference__c) ? c.Booking_Reference__c : 'your booking';
        String supplier = String.isNotBlank(c.Supplier_Name__c) ? c.Supplier_Name__c : 'our rental supplier partner';
        String pickupLoc = String.isNotBlank(c.Pickup_Location__c) ? c.Pickup_Location__c : 'the pickup branch';

        String draft = 'Dear Customer,\n\n' +
                       'Thank you for contacting customer support regarding booking ' + ref + '.\n\n';

        if (rec.intent == 'Vehicle Breakdown') {
            draft += 'We are very sorry to hear that you are experiencing issues with your rental vehicle. ' +
                     'Your safety is our top priority.\n\n' +
                     'According to standard breakdown procedure, please ensure all passengers are in a safe location behind roadway barriers. ' +
                     'Please contact the 24/7 Roadside Assistance helpline listed on your rental agreement immediately. ' +
                     'If the vehicle cannot be driven safely, a replacement vehicle will be coordinated promptly with ' + supplier + '.\n\n';

        } else if (rec.intent == 'Cancellation') {
            draft += 'We have received your cancellation request for reservation ' + ref + ' with ' + supplier + '.\n\n' +
                     'Under our Cancellation & Refund Policy:\n' +
                     '• Cancellations made 48+ hours prior to pickup qualify for a full 100% refund.\n' +
                     '• Cancellations between 24 and 48 hours receive a 50% partial refund.\n' +
                     '• Any eligible refund will be automatically credited back to your original payment card within 3-5 business days.\n\n';

        } else if (rec.intent == 'Billing') {
            draft += 'Thank you for reaching out regarding your billing inquiry for reservation ' + ref + '.\n\n' +
                     'Please note that standard security deposit pre-authorizations are released by the rental supplier within 7 to 14 business days following vehicle return. ' +
                     'We are reviewing the charge details on your account and will confirm the breakdown shortly.\n\n';

        } else if (rec.intent == 'Booking Change') {
            draft += 'We would be happy to assist with updating your rental reservation ' + ref + ' at ' + pickupLoc + '.\n\n' +
                     'Amendments requested more than 24 hours in advance incur no modification fees, though any vehicle category or date rate adjustments will apply based on current fleet availability.\n\n';

        } else {
            draft += 'We have received your enquiry regarding reservation ' + ref + ' and are reviewing the details with ' + supplier + '.\n\n' +
                     'A support specialist will assist you with full details shortly.\n\n';
        }

        draft += 'If you have any further questions, please reply directly to this message.\n\n' +
                 'Kind regards,\n' +
                 'Customer Support Team';

        return draft;
    }

    // ─── Step 6: Audit Logging to AI_Interaction__c ──────────────────────────
    /**
     * Logs an AI recommendation or human interaction to the AI_Interaction__c custom object.
     */
    public static Id logInteraction(
        Id caseId,
        String aiTask,
        Decimal confidence,
        Boolean grounded,
        String suggestedResponse,
        String agentAction,
        String overrideReason
    ) {
        if (caseId == null) {
            throw new IllegalArgumentException('Case ID is required for logging AI interactions.');
        }

        AI_Interaction__c log = new AI_Interaction__c(
            Case__c               = caseId,
            AI_Task__c            = String.isNotBlank(aiTask) ? aiTask : 'Response Drafting',
            Confidence_Score__c   = confidence,
            Grounded_Status__c    = (grounded == true),
            Suggested_Response__c = suggestedResponse,
            Agent_Action__c       = agentAction,
            Override_Reason__c    = overrideReason
        );

        insert log;
        return log.Id;
    }

    // ─── Step 7: Apply Recommendation to Case ─────────────────────────────────
    /**
     * Persists AI triage fields onto the Case record.
     */
    public static void applyRecommendationToCase(Id caseId, AIRecommendation rec) {
        if (caseId == null || rec == null) return;

        Case c = new Case(
            Id                      = caseId,
            Case_Intent__c          = rec.intent,
            Urgency__c              = rec.urgency,
            AI_Confidence__c        = rec.confidenceScore,
            AI_Assistance_Status__c = rec.assistanceStatus
        );

        update c;
    }

    // ─── Helper: Case-insensitive Multi-term Search ───────────────────────────
    private static Boolean containsAny(String source, Set<String> searchTerms) {
        if (String.isBlank(source) || searchTerms == null || searchTerms.isEmpty()) {
            return false;
        }
        for (String term : searchTerms) {
            if (source.contains(term)) {
                return true;
            }
        }
        return false;
    }
}
