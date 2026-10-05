//
//  PaywallBenefitTests.swift
//  ft8_hamTests
//
//  Tests for the grouped benefit rows on the premium paywall.
//

import XCTest
@testable import ft8_ham

final class PaywallBenefitTests: XCTestCase {

    func test_everyPremiumFeature_isListedExactlyOnce() {
        let listed = PaywallBenefit.all.flatMap(\.features)
        for feature in PremiumFeature.allCases {
            XCTAssertEqual(
                listed.filter { $0 == feature }.count, 1,
                "\(feature) must appear in exactly one paywall benefit"
            )
        }
    }

    func test_paywall_staysShort() {
        XCTAssertLessThanOrEqual(PaywallBenefit.all.count, 4)
    }

    func test_benefits_haveUniqueTitlesAndIcons() {
        XCTAssertEqual(Set(PaywallBenefit.all.map(\.title)).count, PaywallBenefit.all.count)
        XCTAssertEqual(Set(PaywallBenefit.all.map(\.icon)).count, PaywallBenefit.all.count)
    }

    func test_summary_namesEveryFeatureAndExtra() {
        for benefit in PaywallBenefit.all {
            for name in benefit.features.map(\.displayName) + benefit.extras {
                XCTAssertTrue(
                    benefit.summary.contains(name),
                    "\"\(benefit.summary)\" should mention \(name)"
                )
            }
        }
    }

    func test_summary_joinsItemsAsAList() {
        let benefit = PaywallBenefit(
            title: "Test",
            icon: "star",
            color: .blue,
            features: [.catControl, .bandHopping],
            extras: ["Priority Support"]
        )
        XCTAssertEqual(
            benefit.summary,
            ["CAT Control", "Band Hopping", "Priority Support"].formatted(.list(type: .and))
        )
    }
}
