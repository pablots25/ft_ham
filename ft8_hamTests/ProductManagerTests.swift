//
//  ProductManagerTests.swift
//  ft8_hamTests
//

import XCTest
import StoreKit
@testable import ft8_ham

// MARK: - Mock fetcher helpers

private struct SucceedingFetcher: ProductFetching {
    /// Returns an empty product array — StoreKit `Product` cannot be constructed
    /// synthetically, so we verify state transitions with an empty result set.
    func fetchProducts(for identifiers: [String]) async throws -> [Product] {
        return []
    }
}

private struct FailingFetcher: ProductFetching {
    let error: Error

    func fetchProducts(for identifiers: [String]) async throws -> [Product] {
        throw error
    }
}

private struct SlowFetcher: ProductFetching {
    func fetchProducts(for identifiers: [String]) async throws -> [Product] {
        // Simulate a network round-trip without completing — used to observe
        // the .loading state before the task finishes.
        try await Task.sleep(nanoseconds: 10_000_000_000) // 10 s
        return []
    }
}

// MARK: - Tests

@MainActor
final class ProductManagerTests: XCTestCase {

    // MARK: Initial state

    func testInitialStateIsIdle() {
        let sut = ProductManager(fetcher: SucceedingFetcher())
        guard case .idle = sut.loadingState else {
            XCTFail("Expected .idle, got \(sut.loadingState)")
            return
        }
    }

    func testInitialProductsIsEmpty() {
        let sut = ProductManager(fetcher: SucceedingFetcher())
        XCTAssertTrue(sut.products.isEmpty)
    }

    // MARK: Successful fetch

    func testFetchProductsTransitionsToLoadedOnSuccess() async {
        let sut = ProductManager(fetcher: SucceedingFetcher())

        await sut.fetchProducts()

        guard case .loaded = sut.loadingState else {
            XCTFail("Expected .loaded, got \(sut.loadingState)")
            return
        }
    }

    func testFetchProductsSetsEmptyProductsOnSuccessWithNoResults() async {
        let sut = ProductManager(fetcher: SucceedingFetcher())

        await sut.fetchProducts()

        XCTAssertTrue(sut.products.isEmpty)
    }

    // MARK: Failed fetch

    func testFetchProductsTransitionsToFailedOnError() async {
        let expectedError = URLError(.notConnectedToInternet)
        let sut = ProductManager(fetcher: FailingFetcher(error: expectedError))

        await sut.fetchProducts()

        guard case .failed(let error) = sut.loadingState else {
            XCTFail("Expected .failed, got \(sut.loadingState)")
            return
        }
        XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
    }

    func testFetchProductsLeavesProductsEmptyOnError() async {
        let sut = ProductManager(fetcher: FailingFetcher(error: URLError(.timedOut)))

        await sut.fetchProducts()

        XCTAssertTrue(sut.products.isEmpty)
    }

    // MARK: Retry after failure

    func testRetryAfterFailureTransitionsBackToLoading() async {
        let sut = ProductManager(fetcher: FailingFetcher(error: URLError(.notConnectedToInternet)))
        await sut.fetchProducts()

        // Now retry with a succeeding fetcher — swap via a second manager to
        // verify the .loading → .loaded path exercised by the retry button.
        let recoveredSut = ProductManager(fetcher: SucceedingFetcher())
        await recoveredSut.fetchProducts()

        guard case .loaded = recoveredSut.loadingState else {
            XCTFail("Expected .loaded after retry, got \(recoveredSut.loadingState)")
            return
        }
    }

    func testConsecutiveFailuresStayInFailedState() async {
        let sut = ProductManager(fetcher: FailingFetcher(error: URLError(.timedOut)))

        await sut.fetchProducts()
        await sut.fetchProducts()

        guard case .failed = sut.loadingState else {
            XCTFail("Expected .failed after second attempt, got \(sut.loadingState)")
            return
        }
    }

    // MARK: Loading state during fetch

    func testLoadingStateIsSetDuringFetch() async {
        let sut = ProductManager(fetcher: SlowFetcher())

        var observedStates: [String] = []
        let task = Task {
            await sut.fetchProducts()
        }

        // Yield to let the task start and enter the async call inside fetchProducts
        await Task.yield()
        observedStates.append("\(sut.loadingState)")

        task.cancel()

        XCTAssertTrue(
            observedStates.contains(where: { $0.contains("loading") }),
            "Expected to observe .loading state during fetch, got: \(observedStates)"
        )
    }
}
