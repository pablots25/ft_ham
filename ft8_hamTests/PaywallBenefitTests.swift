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

    func test_visible_hidesFeaturesWhoseFlagIsOff() {
        let visible = PaywallBenefit.visible { _ in false }.flatMap(\.features)
        for feature in PremiumFeature.allCases {
            XCTAssertEqual(
                visible.contains(feature), feature.featureFlag == nil,
                "\(feature) visibility must follow its flag"
            )
        }
    }

    func test_visible_showsEveryFeatureWhenAllFlagsAreOn() {
        let visible = PaywallBenefit.visible { _ in true }
        XCTAssertEqual(visible.map(\.title), PaywallBenefit.all.map(\.title))
        XCTAssertEqual(visible.flatMap(\.features), PaywallBenefit.all.flatMap(\.features))
    }

    func test_visible_honorsEachFlagIndependently() {
        let visible = PaywallBenefit.visible { $0 == .enableICloudSync }.flatMap(\.features)
        XCTAssertTrue(visible.contains(.iCloudSync))
        XCTAssertFalse(visible.contains(.bandHopping))
        XCTAssertFalse(visible.contains(.presence))
        XCTAssertFalse(visible.contains(.iPadDashboard))
    }

    func test_visible_dropsExtrasBenefitWhenDashboardFlagIsOff() {
        let titles = PaywallBenefit.visible { _ in false }.map(\.title)
        XCTAssertFalse(titles.contains(String(localized: "Extras")))
    }

    func test_visible_keepsBenefitWithOnlyExtrasLeft() {
        let benefit = PaywallBenefit(title: "Test", icon: "star", color: .blue,
                                     features: [.iCloudSync], extras: ["Example"])
        var filtered = benefit
        filtered.features = benefit.features.filter { $0.featureFlag == nil }
        XCTAssertTrue(filtered.features.isEmpty)
        XCTAssertFalse(filtered.extras.isEmpty, "extras alone keep a benefit listed")
    }

    func test_paywall_doesNotPromisePrioritySupport() {
        let extras = PaywallBenefit.all.flatMap(\.extras)
        XCTAssertFalse(extras.contains("Priority Support"))
        XCTAssertFalse(extras.contains(String(localized: "Priority Support")))
        for benefit in PaywallBenefit.all {
            XCTAssertFalse(benefit.summary.contains("Priority Support"), "\(benefit.title) promises support")
        }
    }

    func test_visible_neverListsAnEmptyBenefit() {
        for benefit in PaywallBenefit.visible(isEnabled: { _ in false }) {
            XCTAssertFalse(benefit.features.isEmpty && benefit.extras.isEmpty, "\(benefit.title) is empty")
        }
    }

    func test_paywall_doesNotPromiseFutureFeatures() {
        let extras = PaywallBenefit.all.flatMap(\.extras)
        XCTAssertFalse(extras.contains("Future Features"))
    }

    func test_summary_joinsItemsAsAList() {
        let benefit = PaywallBenefit(
            title: "Test",
            icon: "star",
            color: .blue,
            features: [.catControl, .bandHopping],
            extras: ["Example"]
        )
        XCTAssertEqual(
            benefit.summary,
            ["CAT Control", "Band Hopping", "Example"].formatted(.list(type: .and))
        )
    }
}
