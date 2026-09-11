/**
 * RefundEligibilityCalculator
 *
 * PURPOSE:
 *   Deterministic Apex engine for calculating rental booking cancellation
 *   refund eligibility based on a fictional policy (hours before pickup).
 *
 * ARCHITECTURE NOTE — AI BOUNDARY:
 *   This class is the clearest AI/deterministic boundary in the project.
 *   The LLM is NEVER involved in this calculation. It may explain the
 *   result to an agent in plain English, but the calculation itself
 *   lives entirely here, in auditable, testable, version-controlled Apex.
 *
 * FICTIONAL CANCELLATION POLICY (Demo/Portfolio use only):
 *   ≥ 48 hours before pickup → 100% refund (Full Refund tier)
 *   24–47 hours before pickup → 50% refund  (Partial Refund tier)
 *   < 24 hours before pickup  → 0% refund   (No Refund tier)
 *   Pickup date already past  → 0% refund   (No Refund tier)
 *
 * @author   Muthukumar
 * @version  1.0
 */
public with sharing class RefundEligibilityCalculator {

    // ─── Fictional Policy Constants ───────────────────────────────────────────
    // Centralised here so policy changes require editing one place only.
    @TestVisible private static final Integer FULL_REFUND_THRESHOLD_HOURS    = 48;
    @TestVisible private static final Integer PARTIAL_REFUND_THRESHOLD_HOURS = 24;
    @TestVisible private static final Integer FULL_REFUND_PERCENTAGE         = 100;
    @TestVisible private static final Integer PARTIAL_REFUND_PERCENTAGE      = 50;
    @TestVisible private static final Integer NO_REFUND_PERCENTAGE           = 0;

    // ─── Inner Result Class ───────────────────────────────────────────────────
    /**
     * Encapsulates everything the caller needs to know about the refund decision.
     * Returned as a single object so we never return multiple values separately.
     */
    public class RefundResult {
        /** True if the customer qualifies for any refund amount. */
        @AuraEnabled public Boolean isEligible       { get; private set; }
        /** Refund percentage applicable (0, 50, or 100). */
        @AuraEnabled public Integer refundPercentage { get; private set; }
        /** Calculated refund amount in the same currency as bookingAmount. */
        @AuraEnabled public Decimal refundAmount     { get; private set; }
        /** Human-readable policy explanation (used by AI to explain to agent). */
        @AuraEnabled public String  policyMessage    { get; private set; }
        /** Short tier label for display in LWC (e.g., "Full Refund (48h+)"). */
        @AuraEnabled public String  cancellationTier { get; private set; }

        /**
         * Constructor — called only from RefundEligibilityCalculator.calculate().
         * Private setter access enforces immutability of results.
         */
        public RefundResult(
            Boolean isEligible,
            Integer refundPercentage,
            Decimal refundAmount,
            String  policyMessage,
            String  cancellationTier
        ) {
            this.isEligible       = isEligible;
            this.refundPercentage = refundPercentage;
            this.refundAmount     = refundAmount;
            this.policyMessage    = policyMessage;
            this.cancellationTier = cancellationTier;
        }
    }

    // ─── Custom Exception ─────────────────────────────────────────────────────
    /**
     * Thrown when inputs are invalid (null dates, negative amounts).
     * Using a typed exception instead of a generic System.Exception lets callers
     * catch specifically and respond appropriately.
     */
    public class RefundCalculationException extends Exception {}

    // ─── Main Calculation Method ──────────────────────────────────────────────
    /**
     * Calculates refund eligibility for a rental booking cancellation.
     *
     * @param pickupDateTime  Scheduled pickup date and time for the rental.
     * @param bookingAmount   Total amount paid for the booking (positive Decimal).
     * @return RefundResult   Immutable result object with eligibility, percentage, amount, and message.
     * @throws RefundCalculationException  If pickupDateTime is null or bookingAmount is invalid.
     *
     * GOVERNOR LIMITS: Zero SOQL queries — purely in-memory arithmetic.
     * Safe to call in bulk, from triggers, or Queueable contexts.
     */
    @AuraEnabled
    public static RefundResult calculate(DateTime pickupDateTime, Decimal bookingAmount) {

        // ── Input Validation ─────────────────────────────────────────────────
        if (pickupDateTime == null) {
            throw new RefundCalculationException(
                'Pickup date/time is required for refund calculation. ' +
                'Please retrieve it from the booking system before calling this method.'
            );
        }
        if (bookingAmount == null || bookingAmount < 0) {
            throw new RefundCalculationException(
                'A valid booking amount (zero or positive) is required for refund calculation.'
            );
        }

        // ── Hours-Until-Pickup Calculation ───────────────────────────────────
        // getTime() returns milliseconds since epoch → convert to hours.
        // A 5-second grace window handles execution latency during comparison.
        Long millisUntilPickup = pickupDateTime.getTime() - DateTime.now().getTime();
        Long effectiveMillis   = millisUntilPickup > 0 ? (millisUntilPickup + 5000L) : millisUntilPickup;
        Long hoursUntilPickup  = effectiveMillis / (1000L * 60L * 60L);

        // ── Policy Tier Application ───────────────────────────────────────────
        if (hoursUntilPickup >= FULL_REFUND_THRESHOLD_HOURS) {
            // ≥ 48 hours → Full Refund
            return new RefundResult(
                true,
                FULL_REFUND_PERCENTAGE,
                bookingAmount,
                'Full refund applicable. Cancellation was made more than 48 hours before the ' +
                'scheduled pickup time. The full booking amount will be returned.',
                'Full Refund (48h+)'
            );

        } else if (hoursUntilPickup >= PARTIAL_REFUND_THRESHOLD_HOURS) {
            // 24–47 hours → 50% Refund
            Decimal partialAmount = (bookingAmount * 0.50).setScale(2, System.RoundingMode.HALF_UP);
            return new RefundResult(
                true,
                PARTIAL_REFUND_PERCENTAGE,
                partialAmount,
                'Partial refund applicable (50%). Cancellation was made between 24 and 48 hours ' +
                'before the scheduled pickup time. Half the booking amount will be returned.',
                'Partial Refund (24–48h)'
            );

        } else if (hoursUntilPickup >= 0) {
            // < 24 hours but pickup not yet passed → No Refund
            return new RefundResult(
                false,
                NO_REFUND_PERCENTAGE,
                0,
                'No refund applicable. Cancellation was made less than 24 hours before the ' +
                'scheduled pickup time. The booking amount is non-refundable at this stage.',
                'No Refund (< 24h)'
            );

        } else {
            // Pickup date already in the past → No Refund
            return new RefundResult(
                false,
                NO_REFUND_PERCENTAGE,
                0,
                'No refund applicable. The scheduled pickup date has already passed.',
                'No Refund (Pickup Passed)'
            );
        }
    }
}
