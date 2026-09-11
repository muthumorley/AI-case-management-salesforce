/**
 * RefundEligibilityCalculatorTest
 *
 * Test coverage for RefundEligibilityCalculator.cls
 *
 * TEST SCENARIOS:
 *   Positive  — Full refund (≥ 48h), Partial refund (24–47h)
 *   Negative  — No refund (< 24h), Pickup already passed
 *   Boundary  — Exactly 48h, Exactly 24h (edge of each policy tier)
 *   Error     — Null pickup datetime, Null booking amount, Negative amount
 *   Bulk      — 200 calculations in one transaction (governor limit awareness)
 *
 * @author   Muthukumar
 * @version  1.0
 */
@IsTest
private class RefundEligibilityCalculatorTest {

    // ─── Positive Tests ───────────────────────────────────────────────────────

    @IsTest
    static void testFullRefund_Over48Hours() {
        // Arrange: pickup is 72 hours from now → should qualify for full refund
        DateTime pickup = DateTime.now().addHours(72);
        Decimal  amount = 200.00;

        // Act
        Test.startTest();
        RefundEligibilityCalculator.RefundResult result =
            RefundEligibilityCalculator.calculate(pickup, amount);
        Test.stopTest();

        // Assert
        Assert.isTrue(result.isEligible,              'Should be eligible for full refund');
        Assert.areEqual(100, result.refundPercentage, 'Should be 100% refund');
        Assert.areEqual(200.00, result.refundAmount,  'Refund amount should equal the full booking amount');
        Assert.isTrue(result.cancellationTier.contains('Full'),   'Tier should say Full Refund');
        Assert.isTrue(result.policyMessage.contains('48 hours'),  'Message should reference 48-hour threshold');
    }

    @IsTest
    static void testPartialRefund_Between24And48Hours() {
        // Arrange: pickup is 36 hours from now → 50% refund tier
        DateTime pickup = DateTime.now().addHours(36);
        Decimal  amount = 200.00;

        // Act
        Test.startTest();
        RefundEligibilityCalculator.RefundResult result =
            RefundEligibilityCalculator.calculate(pickup, amount);
        Test.stopTest();

        // Assert
        Assert.isTrue(result.isEligible,              'Should be eligible for partial refund');
        Assert.areEqual(50, result.refundPercentage,  'Should be 50% refund');
        Assert.areEqual(100.00, result.refundAmount,  'Refund should be half of 200.00');
        Assert.isTrue(result.cancellationTier.contains('Partial'), 'Tier should say Partial Refund');
        Assert.isTrue(result.policyMessage.contains('50%'),        'Message should mention 50%');
    }

    @IsTest
    static void testPartialRefund_OddAmount_RoundsCorrectly() {
        // Arrange: booking amount that produces a recurring decimal when halved
        DateTime pickup = DateTime.now().addHours(30);
        Decimal  amount = 99.99;

        // Act
        Test.startTest();
        RefundEligibilityCalculator.RefundResult result =
            RefundEligibilityCalculator.calculate(pickup, amount);
        Test.stopTest();

        // Assert: 99.99 * 0.50 = 49.995 → rounds to 50.00 (HALF_UP)
        Assert.areEqual(50, result.refundPercentage, 'Should be 50% refund');
        Assert.areEqual(50.00, result.refundAmount,  '49.995 should round up to 50.00');
    }

    // ─── Negative Tests ───────────────────────────────────────────────────────

    @IsTest
    static void testNoRefund_LessThan24Hours() {
        // Arrange: pickup is only 12 hours away
        DateTime pickup = DateTime.now().addHours(12);
        Decimal  amount = 200.00;

        // Act
        Test.startTest();
        RefundEligibilityCalculator.RefundResult result =
            RefundEligibilityCalculator.calculate(pickup, amount);
        Test.stopTest();

        // Assert
        Assert.isFalse(result.isEligible,            'Should NOT be eligible');
        Assert.areEqual(0, result.refundPercentage,  'Refund percentage should be 0');
        Assert.areEqual(0, result.refundAmount,      'Refund amount should be 0');
        Assert.isTrue(result.cancellationTier.contains('No Refund'), 'Tier should say No Refund');
    }

    @IsTest
    static void testNoRefund_PickupAlreadyPassed() {
        // Arrange: pickup was 5 hours ago
        DateTime pickup = DateTime.now().addHours(-5);
        Decimal  amount = 200.00;

        // Act
        Test.startTest();
        RefundEligibilityCalculator.RefundResult result =
            RefundEligibilityCalculator.calculate(pickup, amount);
        Test.stopTest();

        // Assert
        Assert.isFalse(result.isEligible,           'Should NOT be eligible when pickup has passed');
        Assert.areEqual(0, result.refundPercentage, 'Refund percentage should be 0');
        Assert.isTrue(
            result.policyMessage.contains('already passed'),
            'Message should explain that the pickup date has already passed'
        );
    }

    // ─── Boundary Tests ───────────────────────────────────────────────────────

    @IsTest
    static void testBoundary_Exactly48Hours_ShouldGetFullRefund() {
        // Arrange: pickup is exactly 48 hours away
        // 48h should qualify for full refund (≥ 48h threshold)
        DateTime pickup = DateTime.now().addHours(48);
        Decimal  amount = 150.00;

        // Act
        Test.startTest();
        RefundEligibilityCalculator.RefundResult result =
            RefundEligibilityCalculator.calculate(pickup, amount);
        Test.stopTest();

        // Assert
        Assert.areEqual(100, result.refundPercentage,
            'Exactly 48 hours should qualify for full refund (boundary inclusive)');
        Assert.isTrue(result.isEligible, 'Should be eligible at exactly 48 hours');
    }

    @IsTest
    static void testBoundary_Exactly24Hours_ShouldGetPartialRefund() {
        // Arrange: pickup is exactly 24 hours away
        DateTime pickup = DateTime.now().addHours(24);
        Decimal  amount = 150.00;

        // Act
        Test.startTest();
        RefundEligibilityCalculator.RefundResult result =
            RefundEligibilityCalculator.calculate(pickup, amount);
        Test.stopTest();

        // Assert
        Assert.areEqual(50, result.refundPercentage,
            'Exactly 24 hours should qualify for partial refund (boundary inclusive)');
        Assert.isTrue(result.isEligible, 'Should be eligible at exactly 24 hours');
    }

    @IsTest
    static void testBoundary_ZeroBookingAmount() {
        // Arrange: free booking (amount = 0) — edge case, should still evaluate eligibility
        DateTime pickup = DateTime.now().addHours(72);
        Decimal  amount = 0;

        // Act
        Test.startTest();
        RefundEligibilityCalculator.RefundResult result =
            RefundEligibilityCalculator.calculate(pickup, amount);
        Test.stopTest();

        // Assert: eligible with 100% of £0 = £0
        Assert.isTrue(result.isEligible,           'Zero-amount booking should still be eligible');
        Assert.areEqual(100, result.refundPercentage, 'Should be 100%');
        Assert.areEqual(0, result.refundAmount,       'Refund of £0 is £0');
    }

    // ─── Error Tests ──────────────────────────────────────────────────────────

    @IsTest
    static void testError_NullPickupDateTime_ThrowsException() {
        Boolean exceptionThrown = false;
        String  caughtMessage   = '';

        // Act
        Test.startTest();
        try {
            RefundEligibilityCalculator.calculate(null, 200.00);
        } catch (RefundEligibilityCalculator.RefundCalculationException e) {
            exceptionThrown = true;
            caughtMessage   = e.getMessage();
        }
        Test.stopTest();

        // Assert
        Assert.isTrue(exceptionThrown,
            'Should throw RefundCalculationException when pickupDateTime is null');
        Assert.isTrue(
            caughtMessage.contains('Pickup date/time is required'),
            'Exception message should clearly describe the problem'
        );
    }

    @IsTest
    static void testError_NullBookingAmount_ThrowsException() {
        Boolean exceptionThrown = false;

        // Act
        Test.startTest();
        try {
            RefundEligibilityCalculator.calculate(DateTime.now().addHours(72), null);
        } catch (RefundEligibilityCalculator.RefundCalculationException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        // Assert
        Assert.isTrue(exceptionThrown,
            'Should throw RefundCalculationException when bookingAmount is null');
    }

    @IsTest
    static void testError_NegativeBookingAmount_ThrowsException() {
        Boolean exceptionThrown = false;

        // Act
        Test.startTest();
        try {
            RefundEligibilityCalculator.calculate(DateTime.now().addHours(72), -50.00);
        } catch (RefundEligibilityCalculator.RefundCalculationException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        // Assert
        Assert.isTrue(exceptionThrown,
            'Should throw RefundCalculationException for a negative booking amount');
    }

    // ─── Bulk Test ────────────────────────────────────────────────────────────

    @IsTest
    static void testBulk_200CalculationsInOneTx_GovernorLimitSafe() {
        // Demonstrates this method is safe for high-volume use
        // (zero SOQL queries, zero DML — purely in-memory arithmetic)
        DateTime pickup = DateTime.now().addHours(72);

        Test.startTest();
        for (Integer i = 0; i < 200; i++) {
            RefundEligibilityCalculator.RefundResult result =
                RefundEligibilityCalculator.calculate(pickup, Decimal.valueOf(100 + i));
            Assert.isTrue(result.isEligible,
                'Bulk calculation index ' + i + ' should succeed and be eligible');
        }
        Test.stopTest();
        // If this test completes without a LimitException, we've proven governor safety
    }
}
