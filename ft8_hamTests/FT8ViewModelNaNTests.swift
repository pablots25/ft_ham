//
//  FT8ViewModelNaNTests.swift
//  ft8_hamTests
//
//  Tests for FT8ViewModel SNR setters to ensure NaN/Infinite values are handled safely
//

import XCTest
@testable import ft8_ham

@MainActor
final class FT8ViewModelNaNTests: XCTestCase {
    
    private var viewModel: FT8ViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = FT8ViewModel()
    }
    
    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }
    
    // MARK: - lastReceivedSNR Tests
    
    func testLastReceivedSNR_SetWithNaN_DoesNotCrash() {
        // Set to a valid value first
        viewModel.lastReceivedSNR = -10.5
        XCTAssertEqual(viewModel.lastReceivedSNR, -11.0,
                      "Initial value should be rounded to -11")
        
        // Attempt to set NaN - should be ignored
        XCTAssertNoThrow({
            self.viewModel.lastReceivedSNR = .nan
        }, "Setting lastReceivedSNR to NaN should not crash")
        
        // Value should remain unchanged (still -11)
        XCTAssertEqual(viewModel.lastReceivedSNR, -11.0,
                      "NaN value should be rejected, keeping previous value")
    }
    
    func testLastReceivedSNR_SetWithInfinity_DoesNotCrash() {
        viewModel.lastReceivedSNR = -10.5
        XCTAssertEqual(viewModel.lastReceivedSNR, -11.0,
                      "Baseline should be rounded to -11")

        XCTAssertNoThrow({
            self.viewModel.lastReceivedSNR = .infinity
        }, "Setting lastReceivedSNR to infinity should not crash")
        
        XCTAssertEqual(viewModel.lastReceivedSNR, -11.0,
                      "Infinity value should be rejected, keeping previous value")
    }
    
    func testLastReceivedSNR_SetWithNegativeInfinity_DoesNotCrash() {
        viewModel.lastReceivedSNR = -10.5
        XCTAssertEqual(viewModel.lastReceivedSNR, -11.0,
                      "Baseline should be rounded to -11")

        XCTAssertNoThrow({
            self.viewModel.lastReceivedSNR = -.infinity
        }, "Setting lastReceivedSNR to -infinity should not crash")
        
        XCTAssertEqual(viewModel.lastReceivedSNR, -11.0,
                      "Negative infinity value should be rejected, keeping previous value")
    }
    
    func testLastReceivedSNR_SetWithValidValue_WorksCorrectly() {
        viewModel.qsoManager.lastReceivedSNR = Int.min // Reset
        
        viewModel.lastReceivedSNR = -12.7
        
        // Should be rounded to -13
        XCTAssertEqual(viewModel.qsoManager.lastReceivedSNR, -13,
                      "Valid value should be properly rounded and stored")
    }
    
    func testLastReceivedSNR_SetWithZero_WorksCorrectly() {
        viewModel.qsoManager.lastReceivedSNR = Int.min // Reset
        
        viewModel.lastReceivedSNR = 0.0
        
        XCTAssertEqual(viewModel.qsoManager.lastReceivedSNR, 0,
                      "Zero should be stored correctly")
    }
    
    // MARK: - lastSentSNR Tests
    
    func testLastSentSNR_SetWithNaN_DoesNotCrash() {
        // Set to a valid value first
        viewModel.qsoManager.lastSentSNR = -15
        
        // Attempt to set NaN - should be ignored
        XCTAssertNoThrow({
            self.viewModel.lastSentSNR = .nan
        }, "Setting lastSentSNR to NaN should not crash")
        
        // Value should remain unchanged
        XCTAssertEqual(viewModel.qsoManager.lastSentSNR, -15,
                      "NaN value should be rejected, keeping previous value")
    }
    
    func testLastSentSNR_SetWithInfinity_DoesNotCrash() {
        viewModel.qsoManager.lastSentSNR = -15 // Set initial value
        
        XCTAssertNoThrow({
            self.viewModel.lastSentSNR = .infinity
        }, "Setting lastSentSNR to infinity should not crash")
        
        XCTAssertEqual(viewModel.qsoManager.lastSentSNR, -15,
                      "Infinity value should be rejected, keeping previous value")
    }
    
    func testLastSentSNR_SetWithNegativeInfinity_DoesNotCrash() {
        viewModel.qsoManager.lastSentSNR = -15 // Set initial value
        
        XCTAssertNoThrow({
            self.viewModel.lastSentSNR = -.infinity
        }, "Setting lastSentSNR to -infinity should not crash")
        
        XCTAssertEqual(viewModel.qsoManager.lastSentSNR, -15,
                      "Negative infinity value should be rejected, keeping previous value")
    }
    
    func testLastSentSNR_SetWithValidValue_WorksCorrectly() {
        viewModel.lastSentSNR = 18.4
        
        // Should be rounded to 18
        XCTAssertEqual(viewModel.qsoManager.lastSentSNR, 18,
                      "Valid value should be properly rounded and stored")
    }
    
    func testLastSentSNR_SetWithValidNegativeValue_WorksCorrectly() {
        viewModel.lastSentSNR = -22.6
        
        // Should be rounded to -23
        XCTAssertEqual(viewModel.qsoManager.lastSentSNR, -23,
                      "Valid negative value should be properly rounded and stored")
    }
    
    // MARK: - Sequence of Non-Finite Values
    
    func testSequenceOfNonFiniteValues_DoesNotCrash() {
        let nonFiniteValues: [Double] = [.nan, .infinity, -.infinity, .nan, .infinity]
        
        for value in nonFiniteValues {
            XCTAssertNoThrow({
                self.viewModel.lastReceivedSNR = value
                self.viewModel.lastSentSNR = value
            }, "Setting SNR to \(value) should not crash")
        }
    }
    
    // MARK: - Mixed Valid and Invalid Values
    
    func testMixedValidAndInvalidValues_HandleCorrectly() {
        // Set valid value
        viewModel.lastReceivedSNR = -10.5
        let initialValue = viewModel.qsoManager.lastReceivedSNR
        
        // Try to set invalid
        viewModel.lastReceivedSNR = .nan
        
        // Should keep the valid value
        XCTAssertEqual(viewModel.qsoManager.lastReceivedSNR, initialValue,
                      "Invalid value should not overwrite valid value")
        
        // Set another valid value
        viewModel.lastReceivedSNR = 5.2
        
        // Should update
        XCTAssertEqual(viewModel.qsoManager.lastReceivedSNR, 5,
                      "Valid value should update correctly after rejected invalid value")
    }
    
    // MARK: - Getter Tests
    
    func testLastReceivedSNR_GetterWithInvalidSNR_ReturnsDoubleMin() {
        viewModel.qsoManager.lastReceivedSNR = Int.min
        
        let retrieved = viewModel.lastReceivedSNR
        
        XCTAssertEqual(retrieved, Double(Int.min),
                      "Getter should return Double(Int.min) when underlying value is Int.min")
    }
    
    func testLastSentSNR_GetterWithInvalidSNR_ReturnsDoubleMin() {
        viewModel.qsoManager.lastSentSNR = Int.min
        
        let retrieved = viewModel.lastSentSNR
        
        XCTAssertEqual(retrieved, Double(Int.min),
                      "Getter should return Double(Int.min) when underlying value is Int.min")
    }
}
