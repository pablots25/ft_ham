//
//  LogbookManagerTests.swift
//  ft_ham
//
//  Created by Pablo Turrion on 18/1/26.
//


import XCTest
@testable import ft8_ham


final class LogbookManagerTests: XCTestCase {
    
    private var logbookManager: LogbookManager!
    
    override func setUp() {
        super.setUp()
        logbookManager = LogbookManager()
    }
    
    override func tearDown() {
        logbookManager = nil
        super.tearDown()
    }
    
    func testExportThenImportPreservesDate() throws {
        
        let manager = LogbookManager()
        
        let originalDate = Date(timeIntervalSince1970: 1_700_000_123)
        
        let entry = LogEntry(
            callsign: "EA1AA",
            grid: "IN80",
            date: originalDate,
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "12",
            rstRcvd: "-4",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )
        
        // Export
        let adifURL = manager.saveToADIF([entry])
        XCTAssertNotNil(adifURL)
        
        // Import
        let imported = try manager.loadEntries()
        XCTAssertEqual(imported.count, 1)
        
        let importedDate = imported.first!.date
        
        XCTAssertEqual(importedDate, originalDate)
    }
    
    
    // MARK: - ADIF Parsing Tests
    
    func testParseADIF_WithHHmmTime() {
        let adif = """
        <CALL:5>EA1AA <GRID:4>IN80 <MODE:3>FT8 <BAND:3>10m \
        <RST_SENT:2>12 <RST_RCVD:2>-4 \
        <QSO_DATE:8>20250118 <TIME_ON:4>1642 <EOR>
        """
        
        let entry = logbookManager
            .loadEntriesFromString(adif)
            .first!
        
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            in: TimeZone(secondsFromGMT: 0)!,
            from: entry.date
        )
        
        XCTAssertEqual(components.year, 2025)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 18)
        XCTAssertEqual(components.hour, 16)
        XCTAssertEqual(components.minute, 42)
        XCTAssertEqual(components.second, 0)
    }
    
    func testParseADIF_WithHHmmssTime() {
        let adif = """
        <CALL:5>EA1AA <GRID:4>IN80 <MODE:3>FT8 <BAND:3>10m \
        <RST_SENT:2>12 <RST_RCVD:2>-4 \
        <QSO_DATE:8>20250118 <TIME_ON:6>164215 <EOR>
        """
        
        let entry = logbookManager
            .loadEntriesFromString(adif)
            .first!
        
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            in: TimeZone(secondsFromGMT: 0)!,
            from: entry.date
        )
        
        XCTAssertEqual(components.hour, 16)
        XCTAssertEqual(components.minute, 42)
        XCTAssertEqual(components.second, 15)
    }
    
    func testParseADIF_InvalidDateFallsBackToEpoch() {
        let adif = """
        <CALL:5>EA1AA <GRID:4>IN80 <MODE:3>FT8 <BAND:3>10m \
        <QSO_DATE:8>XXXXXXXX <TIME_ON:6>YYYYYY <EOR>
        """
        
        let entry = logbookManager
            .loadEntriesFromString(adif)
            .first!
        
        XCTAssertEqual(entry.date.timeIntervalSince1970, 0)
    }

    func testFilterEntriesSince_UsesStrictTimestampNotStartOfDay() {
        let manager = LogbookManager()
        let lastExport = Date(timeIntervalSince1970: 1_700_000_000)

        let entries: [LogEntry] = [
            LogEntry(callsign: "EA1OLD", grid: "IN80", date: lastExport.addingTimeInterval(-1), frequencyHz: nil, mode: "FT8", band: "20m", rstSent: "-10", rstRcvd: "-08", stationCallsign: nil, cqModifier: nil, mySigInfo: nil, country: nil, flag: nil),
            LogEntry(callsign: "EA1EDGE", grid: "IN80", date: lastExport, frequencyHz: nil, mode: "FT8", band: "20m", rstSent: "-10", rstRcvd: "-08", stationCallsign: nil, cqModifier: nil, mySigInfo: nil, country: nil, flag: nil),
            LogEntry(callsign: "EA1NEW", grid: "IN80", date: lastExport.addingTimeInterval(1), frequencyHz: nil, mode: "FT8", band: "20m", rstSent: "-10", rstRcvd: "-08", stationCallsign: nil, cqModifier: nil, mySigInfo: nil, country: nil, flag: nil)
        ]

        let filtered = manager.filterEntriesSince(entries, since: lastExport, upTo: lastExport.addingTimeInterval(120))

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.callsign, "EA1NEW")
    }

    func testADIFExportAndImport_PreservesFREQFieldInMHz() throws {
        let manager = LogbookManager()

        let entry = LogEntry(
            callsign: "EA1FREQ",
            grid: "IN80",
            date: Date(timeIntervalSince1970: 1_700_000_123),
            frequencyHz: 14_074_000,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )

        let adifURL = manager.saveToADIF([entry])
        XCTAssertNotNil(adifURL)

        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""
        XCTAssertTrue(content.contains("<FREQ:9>14.074000"))

        let imported = try manager.loadEntries()
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.frequencyHz ?? 0, 14_074_000, accuracy: 0.5)
    }

    // MARK: - ADIF Special Fields Tests

    func testExportIncludesMY_SIGForPOTA() {
        let manager = LogbookManager()
        UserDefaults.standard.set("EA-0012", forKey: "myPotaRef")

        let entry = LogEntry(
            callsign: "K1XYZ",
            grid: "FN31",
            date: Date(timeIntervalSince1970: 1_700_000_123),
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: nil,
            cqModifier: "POTA",
            mySigInfo: nil,
            country: nil,
            flag: nil
        )

        let adifURL = manager.saveToADIF([entry])
        XCTAssertNotNil(adifURL)

        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        XCTAssertTrue(content.contains("<MY_SIG:4>POTA"))

        UserDefaults.standard.removeObject(forKey: "myPotaRef")
    }

    func testExportDXDoesNotWriteMY_SIG() {
        // Geographic/directional modifiers are RX-side display aids; they don't map
        // to MY_SIG (Special Interest Group) in ADIF.
        let manager = LogbookManager()

        let entry = LogEntry(
            callsign: "K1XYZ",
            grid: "FN31",
            date: Date(timeIntervalSince1970: 1_700_000_123),
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: nil,
            cqModifier: "DX",
            mySigInfo: nil,
            country: nil,
            flag: nil
        )

        let adifURL = manager.saveToADIF([entry])
        XCTAssertNotNil(adifURL)

        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        XCTAssertFalse(content.contains("<MY_SIG:"))
    }

    func testParseADIFReadsMY_SIGIntoCQModifier() {
        let adif = "<CALL:5>EA1AA <GRID:4>IN80 <MODE:3>FT8 <BAND:3>20m <RST_SENT:2>12 <RST_RCVD:2>-4 <MY_SIG:4>POTA <QSO_DATE:8>20250118 <TIME_ON:6>164215 <EOR>"

        let entry = logbookManager
            .loadEntriesFromString(adif)
            .first!

        XCTAssertEqual(entry.cqModifier, "POTA")
    }

    func testExportDoesNotWriteEmptyMySigInfo() {
        let manager = LogbookManager()

        let entry = LogEntry(
            callsign: "K1XYZ",
            grid: "FN31",
            date: Date(timeIntervalSince1970: 1_700_000_123),
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: nil,
            cqModifier: "POTA",
            mySigInfo: nil,
            country: nil,
            flag: nil
        )

        let adifURL = manager.saveToADIF([entry])
        XCTAssertNotNil(adifURL)

        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        XCTAssertTrue(content.contains("<MY_SIG:4>POTA"))
        XCTAssertFalse(content.contains("<MY_SIG_INFO:"))
    }

    func testExportIncludesStationCallsignWhenSigPresent() {
        let manager = LogbookManager()
        UserDefaults.standard.set("EA1AAA", forKey: "callsign")
        UserDefaults.standard.set("EA-0012", forKey: "myPotaRef")

        let entry = LogEntry(
            callsign: "K1XYZ",
            grid: "FN31",
            date: Date(timeIntervalSince1970: 1_700_000_123),
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: "EA1AAA",
            cqModifier: "POTA",
            mySigInfo: nil,
            country: nil,
            flag: nil
        )


        let adifURL = manager.saveToADIF([entry])
        XCTAssertNotNil(adifURL)

        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        XCTAssertTrue(content.contains("<STATION_CALLSIGN:6>EA1AAA"))

        UserDefaults.standard.removeObject(forKey: "callsign")
        UserDefaults.standard.removeObject(forKey: "myPotaRef")
    }
    
    // MARK: - All CQ Modifiers Tests
    
    func testExportIncludesIOTAModifier() {
        let manager = LogbookManager()
        UserDefaults.standard.set("EU-005", forKey: "myIotaRef")
        
        let entry = LogEntry(
            callsign: "G4XYZ",
            grid: "IO91",
            date: Date(timeIntervalSince1970: 1_700_000_123),
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: "EA4IQL",
            cqModifier: "IOTA",
            mySigInfo: "EU-005",
            country: nil,
            flag: nil
        )
        
        let adifURL = manager.saveToADIF([entry])
        XCTAssertNotNil(adifURL)
        
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""
        
        XCTAssertTrue(content.contains("<MY_SIG:4>IOTA"))
        XCTAssertTrue(content.contains("<MY_SIG_INFO:6>EU-005"))
        
        UserDefaults.standard.removeObject(forKey: "myIotaRef")
    }
    
    func testExportDoesNotIncludeGeographicFilters() {
        let manager = LogbookManager()
        let geographicFilters = ["DX", "EU", "NA", "SA", "AF", "AS", "OC", "ANT"]
        
        for filter in geographicFilters {
            let entry = LogEntry(
                callsign: "K1XYZ",
                grid: "FN31",
                date: Date(timeIntervalSince1970: 1_700_000_123),
                frequencyHz: nil,
                mode: "FT8",
                band: "20m",
                rstSent: "-10",
                rstRcvd: "-08",
                stationCallsign: nil,
                cqModifier: filter,
                mySigInfo: nil,
            country: nil,
            flag: nil
            )
            
            let adifURL = manager.saveToADIF([entry])
            XCTAssertNotNil(adifURL, "Failed for \(filter)")
            
            let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""
            
            // Geographic filters should never produce MY_SIG or MY_SIG_INFO
            XCTAssertFalse(content.contains("<MY_SIG:"), "Geographic filter \(filter) incorrectly produced MY_SIG")
            XCTAssertFalse(content.contains("<MY_SIG_INFO:"), "Geographic filter \(filter) incorrectly produced MY_SIG_INFO")
        }
    }
    
    func testRoundTripAllActivationModifiers() throws {
        let manager = LogbookManager()
        
        // Set up all references
        UserDefaults.standard.set("EA-1234", forKey: "myPotaRef")
        UserDefaults.standard.set("EA/MD-001", forKey: "mySotaRef")
        UserDefaults.standard.set("EAFF-0456", forKey: "myWwffRef")
        UserDefaults.standard.set("EU-005", forKey: "myIotaRef")
        
        let activationModifiers = [
            ("POTA", "EA-1234"),
            ("SOTA", "EA/MD-001"),
            ("WWFF", "EAFF-0456"),
            ("IOTA", "EU-005")
        ]
        
        for (modifier, expectedRef) in activationModifiers {
            let entry = LogEntry(
                callsign: "K1XYZ",
                grid: "FN31",
                date: Date(timeIntervalSince1970: 1_700_000_123),
                frequencyHz: nil,
                mode: "FT8",
                band: "20m",
                rstSent: "-10",
                rstRcvd: "-08",
                stationCallsign: "EA4IQL",
                cqModifier: modifier,
                mySigInfo: expectedRef,
            country: nil,
            flag: nil
            )
            
            // Export
            let adifURL = manager.saveToADIF([entry])
            XCTAssertNotNil(adifURL, "Export failed for \(modifier)")
            
            // Import
            let imported = try manager.loadEntries()
            XCTAssertEqual(imported.count, 1, "Import count wrong for \(modifier)")
            
            let importedEntry = imported.first!
            XCTAssertEqual(importedEntry.cqModifier, modifier, "CQ modifier mismatch for \(modifier)")
            XCTAssertEqual(importedEntry.mySigInfo, expectedRef, "Reference mismatch for \(modifier)")
            XCTAssertEqual(importedEntry.stationCallsign, "EA4IQL", "Station callsign mismatch for \(modifier)")
        }
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "myPotaRef")
        UserDefaults.standard.removeObject(forKey: "mySotaRef")
        UserDefaults.standard.removeObject(forKey: "myWwffRef")
        UserDefaults.standard.removeObject(forKey: "myIotaRef")
    }
    
    func testExportUsesStoredMySigInfo() {
        let manager = LogbookManager()
        
        // Entry already has mySigInfo set - should use that instead of UserDefaults
        let entry = LogEntry(
            callsign: "K1XYZ",
            grid: "FN31",
            date: Date(timeIntervalSince1970: 1_700_000_123),
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: "EA4IQL",
            cqModifier: "POTA",
            mySigInfo: "EA-9999",  // Specific value in entry
            country: nil,
            flag: nil
        )
        
        // Set a different value in UserDefaults
        UserDefaults.standard.set("EA-0001", forKey: "myPotaRef")
        
        let adifURL = manager.saveToADIF([entry])
        XCTAssertNotNil(adifURL)
        
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""
        
        // Should use entry's mySigInfo, not UserDefaults
        XCTAssertTrue(content.contains("<MY_SIG_INFO:7>EA-9999"))
        XCTAssertFalse(content.contains("EA-0001"))
        
        UserDefaults.standard.removeObject(forKey: "myPotaRef")
    }

    @MainActor
    func testFullPipeline_CQ_POTA_ProducesCorrectADIF() {
        UserDefaults.standard.set("EA4IQL", forKey: "callsign")
        UserDefaults.standard.set("POTA", forKey: "cqModifier")
        UserDefaults.standard.set("EA-1234", forKey: "myPotaRef")

        let qso = QSOStatusManager()
        qso.startCallingCQ()

        let entry = qso.createLogEntry(
            dxCallsign: "K1XYZ",
            dxLocator: "FN31",
            qsoDate: Date(timeIntervalSince1970: 1_700_000_123),
            band: .band20m,
            isFT4: false,
            rstSent: -10,
            rstRcvd: -8
        )

        let manager = LogbookManager()
        let url = manager.saveToADIF([entry])!
        let content = try! String(contentsOf: url)

        XCTAssertTrue(content.contains("<STATION_CALLSIGN:6>EA4IQL"))
        XCTAssertTrue(content.contains("<MY_SIG:4>POTA"))
        XCTAssertTrue(content.contains("<MY_SIG_INFO:7>EA-1234"))
    }

    @MainActor
    func testFullPipeline_CQ_OtherWWA_RoundTripPreservesMY_SIG() throws {
        UserDefaults.standard.set("EA4IQL", forKey: "callsign")
        UserDefaults.standard.set("OTHER", forKey: "cqModifier")
        UserDefaults.standard.set("WWA", forKey: "cqModifierOther")

        let qso = QSOStatusManager()
        qso.startCallingCQ()

        let entry = qso.createLogEntry(
            dxCallsign: "K1XYZ",
            dxLocator: "FN31",
            qsoDate: Date(timeIntervalSince1970: 1_700_000_123),
            band: .band20m,
            isFT4: false,
            rstSent: -10,
            rstRcvd: -8
        )

        XCTAssertEqual(entry.cqModifier, "WWA")

        let manager = LogbookManager()
        let url = manager.saveToADIF([entry])
        XCTAssertNotNil(url)

        let content = try? String(contentsOf: url!, encoding: .utf8)
        XCTAssertTrue(content?.contains("<MY_SIG:3>WWA") ?? false)

        let imported = try manager.loadEntries()
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.cqModifier, "WWA")

        UserDefaults.standard.removeObject(forKey: "callsign")
        UserDefaults.standard.removeObject(forKey: "cqModifier")
        UserDefaults.standard.removeObject(forKey: "cqModifierOther")
    }
    
    // MARK: - Callsign Modifier Tests
    
    func testExportIncludesCallsignModifierInStationCallsign() {
        let manager = LogbookManager()
        
        let entry = LogEntry(
            callsign: "K1ABC",
            grid: "FN31",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: "EA4IQL/P",
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )
        
        let adifURL = manager.saveToADIF([entry])
        XCTAssertNotNil(adifURL)
        
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""
        
        let expectedStation = "EA4IQL/P"
        XCTAssertTrue(content.contains("<STATION_CALLSIGN:\(expectedStation.count)>\(expectedStation)"))
    }
    
    func testExportWithAllCallsignModifiers() {
        let manager = LogbookManager()
        let modifiers = ["P", "M", "MM", "AM", "QRP", "R"]
        
        for modifier in modifiers {
            let entry = LogEntry(
                callsign: "K1ABC",
                grid: "FN31",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                frequencyHz: nil,
                mode: "FT8",
                band: "20m",
                rstSent: "-10",
                rstRcvd: "-08",
                stationCallsign: "EA4IQL/\(modifier)",
                cqModifier: nil,
                mySigInfo: nil,
            country: nil,
            flag: nil
            )
            
            let adifURL = manager.saveToADIF([entry])
            XCTAssertNotNil(adifURL)
            
            let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""
            let expectedStation = "EA4IQL/\(modifier)"
            
            XCTAssertTrue(content.contains("<STATION_CALLSIGN:\(expectedStation.count)>\(expectedStation)"),
                         "Should export callsign with /\(modifier) modifier")
        }
    }
    
    func testRoundTripCallsignModifier() throws {
        let manager = LogbookManager()
        
        let originalEntry = LogEntry(
            callsign: "W1ABC",
            grid: "FN42",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: nil,
            mode: "FT8",
            band: "40m",
            rstSent: "+05",
            rstRcvd: "-12",
            stationCallsign: "EA4IQL/MM",
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )
        
        // Export
        let adifURL = manager.saveToADIF([originalEntry])
        XCTAssertNotNil(adifURL)
        
        // Import
        let importedEntries = try manager.loadEntries()
        XCTAssertEqual(importedEntries.count, 1)
        
        let imported = importedEntries[0]
        XCTAssertEqual(imported.stationCallsign, "EA4IQL/MM")
        XCTAssertEqual(imported.callsign, "W1ABC")
        XCTAssertEqual(imported.grid, "FN42")
    }
    
    func testExportWithBothModifiers() {
        let manager = LogbookManager()
        
        // Entry with both CQ modifier and callsign modifier
        let entry = LogEntry(
            callsign: "K2XYZ",
            grid: "FN31",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: "EA4IQL/P",
            cqModifier: "POTA",
            mySigInfo: "EA-1234",
            country: nil,
            flag: nil
        )
        
        let adifURL = manager.saveToADIF([entry])
        XCTAssertNotNil(adifURL)
        
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""
        
        // Should have both callsign modifier in STATION_CALLSIGN
        let expectedStation = "EA4IQL/P"
        XCTAssertTrue(content.contains("<STATION_CALLSIGN:\(expectedStation.count)>\(expectedStation)"))
        // And CQ modifier in MY_SIG field
        XCTAssertTrue(content.contains("<MY_SIG:4>POTA"))
        XCTAssertTrue(content.contains("<MY_SIG_INFO:7>EA-1234"))
    }
    
    func testImportADIFWithCallsignModifier() {
        let manager = LogbookManager()
        
        let adif = """
        <CALL:5>K1ABC <GRID:4>FN31 <MODE:3>FT8 <BAND:3>20m \
        <RST_SENT:3>-10 <RST_RCVD:3>-08 \
        <STATION_CALLSIGN:9>EA4IQL/P \
        <QSO_DATE:8>20231115 <TIME_ON:6>143000 <EOR>
        """
        
        let entries = manager.loadEntriesFromString(adif)
        
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].callsign, "K1ABC")
        XCTAssertEqual(entries[0].stationCallsign, "EA4IQL/P")
        XCTAssertEqual(entries[0].grid, "FN31")
    }
    
    // MARK: - Comprehensive ADIF Export Completeness Tests

    func testADIFHeader_ContainsVersionAndEOH() {
        let manager = LogbookManager()

        let entry = LogEntry(
            callsign: "EA1AA",
            grid: "IN80",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )

        let adifURL = manager.saveToADIF([entry])
        XCTAssertNotNil(adifURL)
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        XCTAssertTrue(content.hasPrefix("ADIF Export from FT8Ham"), "Header should start with app identification")
        XCTAssertTrue(content.contains("<ADIF_VER:5>3.1.4"), "Header must declare ADIF version 3.1.4")
        XCTAssertTrue(content.contains("<EOH>"), "Header must end with <EOH> marker")

        // EOH must appear before any record
        let eohRange = content.range(of: "<EOH>")!
        let eorRange = content.range(of: "<EOR>")!
        XCTAssertTrue(eohRange.upperBound < eorRange.lowerBound, "<EOH> must precede first <EOR>")
    }

    func testADIFExport_AllFieldsPresent_FullRecord() {
        // Verify a fully-populated record contains every expected ADIF tag
        let manager = LogbookManager()
        UserDefaults.standard.set("EA-5678", forKey: "myPotaRef")

        let fixedDate = Date(timeIntervalSince1970: 1_700_000_123) // 2023-11-14 22:15:23 UTC

        let entry = LogEntry(
            callsign: "W1AW",
            grid: "FN31pr",
            date: fixedDate,
            frequencyHz: 14_074_000,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "+05",
            stationCallsign: "EA4IQL/P",
            cqModifier: "POTA",
            mySigInfo: "EA-5678",
            country: "United States",
            flag: "🇺🇸"
        )

        let adifURL = manager.saveToADIF([entry])
        XCTAssertNotNil(adifURL)
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        // Every mandatory ADIF field must be present
        XCTAssertTrue(content.contains("<CALL:4>W1AW"), "Missing or incorrect CALL field")
        XCTAssertTrue(content.contains("<STATION_CALLSIGN:8>EA4IQL/P"), "Missing or incorrect STATION_CALLSIGN")
        XCTAssertTrue(content.contains("<FREQ:9>14.074000"), "Missing or incorrect FREQ (MHz with 6 decimals)")
        XCTAssertTrue(content.contains("<BAND:3>20m"), "Missing or incorrect BAND")
        XCTAssertTrue(content.contains("<MODE:3>FT8"), "Missing or incorrect MODE")
        XCTAssertTrue(content.contains("<RST_SENT:3>-10"), "Missing or incorrect RST_SENT")
        XCTAssertTrue(content.contains("<RST_RCVD:3>+05"), "Missing or incorrect RST_RCVD")
        XCTAssertTrue(content.contains("<QSO_DATE:8>20231114"), "Missing or incorrect QSO_DATE")
        XCTAssertTrue(content.contains("<TIME_ON:6>221523"), "Missing or incorrect TIME_ON")
        XCTAssertTrue(content.contains("<GRID:6>FN31pr"), "Missing or incorrect GRID")
        XCTAssertTrue(content.contains("<MY_SIG:4>POTA"), "Missing or incorrect MY_SIG")
        XCTAssertTrue(content.contains("<MY_SIG_INFO:7>EA-5678"), "Missing or incorrect MY_SIG_INFO")
        XCTAssertTrue(content.contains("<EOR>"), "Missing end-of-record marker")

        // country and flag are display-only, should NOT appear in ADIF
        XCTAssertFalse(content.contains("United States"), "Country name must not leak into ADIF")
        XCTAssertFalse(content.contains("🇺🇸"), "Flag emoji must not leak into ADIF")

        UserDefaults.standard.removeObject(forKey: "myPotaRef")
    }

    func testADIFExport_FieldLengthsAreCorrect() {
        // Validate the <TAG:n>value pattern: n must equal value.count
        let manager = LogbookManager()

        let entry = LogEntry(
            callsign: "JA1ABC",
            grid: "PM95",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: 7_074_000,
            mode: "FT8",
            band: "40m",
            rstSent: "-15",
            rstRcvd: "-03",
            stationCallsign: "EA4IQL",
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )

        let adifURL = manager.saveToADIF([entry])
        XCTAssertNotNil(adifURL)
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        // Parse every <TAG:n>value and verify n == value.count
        let tagPattern = try! NSRegularExpression(pattern: "<([A-Z_]+):(\\d+)>([^ <\\n]*)")
        let matches = tagPattern.matches(in: content, range: NSRange(content.startIndex..., in: content))

        XCTAssertGreaterThan(matches.count, 0, "Should find ADIF tags in output")

        for match in matches {
            let tagName = String(content[Range(match.range(at: 1), in: content)!])
            let declaredLength = Int(String(content[Range(match.range(at: 2), in: content)!]))!
            let value = String(content[Range(match.range(at: 3), in: content)!])

            XCTAssertEqual(declaredLength, value.count,
                           "Tag <\(tagName):\(declaredLength)> has value '\(value)' with actual length \(value.count)")
        }
    }

    func testADIFExport_NoFreqTag_WhenFrequencyIsNil() {
        let manager = LogbookManager()

        let entry = LogEntry(
            callsign: "K1ABC",
            grid: "FN31",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )

        let adifURL = manager.saveToADIF([entry])
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        XCTAssertFalse(content.contains("<FREQ:"), "FREQ tag must be omitted when frequency is nil")
    }

    func testADIFExport_NoGridTag_WhenGridIsEmpty() {
        let manager = LogbookManager()

        let entry = LogEntry(
            callsign: "K1ABC",
            grid: "",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )

        let adifURL = manager.saveToADIF([entry])
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        XCTAssertFalse(content.contains("<GRID:"), "GRID tag must be omitted when grid is empty")
    }

    func testADIFExport_NoStationCallsign_WhenNil() {
        let manager = LogbookManager()

        let entry = LogEntry(
            callsign: "K1ABC",
            grid: "FN31",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )

        let adifURL = manager.saveToADIF([entry])
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        XCTAssertFalse(content.contains("<STATION_CALLSIGN:"), "STATION_CALLSIGN must be omitted when nil")
    }

    func testADIFExport_FT4Mode() {
        let manager = LogbookManager()

        let entry = LogEntry(
            callsign: "DL1ABC",
            grid: "JO31",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: 14_080_000,  // FT4 20m frequency
            mode: "FT4",
            band: "20m",
            rstSent: "-12",
            rstRcvd: "-06",
            stationCallsign: "EA4IQL",
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )

        let adifURL = manager.saveToADIF([entry])
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        XCTAssertTrue(content.contains("<MODE:3>FT4"), "Mode should be FT4")
        XCTAssertTrue(content.contains("<FREQ:9>14.080000"), "FT4 frequency should be 14.080000 MHz")
        XCTAssertTrue(content.contains("<BAND:3>20m"), "Band should still be 20m")
    }

    func testADIFExport_MultipleQSOs_AllRecordsPresent() {
        let manager = LogbookManager()

        let entries: [LogEntry] = [
            LogEntry(callsign: "W1AW", grid: "FN31", date: Date(timeIntervalSince1970: 1_700_000_000),
                     frequencyHz: 14_074_000, mode: "FT8", band: "20m",
                     rstSent: "-10", rstRcvd: "-08", stationCallsign: "EA4IQL",
                     cqModifier: nil, mySigInfo: nil, country: nil, flag: nil),
            LogEntry(callsign: "JA1ABC", grid: "PM95", date: Date(timeIntervalSince1970: 1_700_001_000),
                     frequencyHz: 7_074_000, mode: "FT8", band: "40m",
                     rstSent: "-05", rstRcvd: "+02", stationCallsign: "EA4IQL",
                     cqModifier: nil, mySigInfo: nil, country: nil, flag: nil),
            LogEntry(callsign: "VK2ABC", grid: "QF56", date: Date(timeIntervalSince1970: 1_700_002_000),
                     frequencyHz: 21_074_000, mode: "FT8", band: "15m",
                     rstSent: "-18", rstRcvd: "-14", stationCallsign: "EA4IQL",
                     cqModifier: nil, mySigInfo: nil, country: nil, flag: nil)
        ]

        let adifURL = manager.saveToADIF(entries)
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        // Count EOR markers — one per QSO
        let eorCount = content.components(separatedBy: "<EOR>").count - 1
        XCTAssertEqual(eorCount, 3, "Should have exactly 3 EOR markers for 3 QSOs")

        // Each callsign must appear
        XCTAssertTrue(content.contains("<CALL:4>W1AW"))
        XCTAssertTrue(content.contains("<CALL:6>JA1ABC"))
        XCTAssertTrue(content.contains("<CALL:6>VK2ABC"))

        // Different bands/frequencies
        XCTAssertTrue(content.contains("<BAND:3>20m"))
        XCTAssertTrue(content.contains("<BAND:3>40m"))
        XCTAssertTrue(content.contains("<BAND:3>15m"))
        XCTAssertTrue(content.contains("<FREQ:9>14.074000"))
        XCTAssertTrue(content.contains("<FREQ:8>7.074000"))
        XCTAssertTrue(content.contains("<FREQ:9>21.074000"))
    }

    func testADIFExport_FrequencyFormattingAcrossBands() {
        // Verify frequency is always in MHz with 6 decimal places
        let manager = LogbookManager()

        let testCases: [(hz: Double, expectedMHz: String, band: String)] = [
            (1_840_000,  "1.840000",  "160m"),
            (3_574_000,  "3.574000",  "80m"),
            (7_074_000,  "7.074000",  "40m"),
            (10_136_000, "10.136000", "30m"),
            (14_074_000, "14.074000", "20m"),
            (21_074_000, "21.074000", "15m"),
            (28_074_000, "28.074000", "10m"),
            (50_313_000, "50.313000", "6m"),
        ]

        for (hz, expectedMHz, band) in testCases {
            let entry = LogEntry(
                callsign: "TEST",
                grid: "AA00",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                frequencyHz: hz,
                mode: "FT8",
                band: band,
                rstSent: "-10",
                rstRcvd: "-08",
                stationCallsign: nil,
                cqModifier: nil,
                mySigInfo: nil,
                country: nil,
                flag: nil
            )

            let adifURL = manager.saveToADIF([entry])
            let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

            XCTAssertTrue(content.contains("<FREQ:\(expectedMHz.count)>\(expectedMHz)"),
                          "Band \(band): expected FREQ \(expectedMHz), got content snippet around FREQ: \(content)")
        }
    }

    func testADIFExport_DateTimeAlwaysUTC() {
        let manager = LogbookManager()

        // 2024-07-04 15:30:45 UTC
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: 2024, month: 7, day: 4, hour: 15, minute: 30, second: 45)
        let date = utcCalendar.date(from: components)!

        let entry = LogEntry(
            callsign: "N1MM",
            grid: "FN31",
            date: date,
            frequencyHz: nil,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )

        let adifURL = manager.saveToADIF([entry])
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        XCTAssertTrue(content.contains("<QSO_DATE:8>20240704"), "Date should be formatted yyyyMMdd in UTC")
        XCTAssertTrue(content.contains("<TIME_ON:6>153045"), "Time should be formatted HHmmss in UTC")
    }

    func testADIFExport_EachRecordEndsWithEOR() {
        let manager = LogbookManager()

        let entries: [LogEntry] = (0..<5).map { i in
            LogEntry(
                callsign: "CALL\(i)",
                grid: "AA00",
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 100),
                frequencyHz: nil,
                mode: "FT8",
                band: "20m",
                rstSent: "-10",
                rstRcvd: "-08",
                stationCallsign: nil,
                cqModifier: nil,
                mySigInfo: nil,
                country: nil,
                flag: nil
            )
        }

        let adifURL = manager.saveToADIF(entries)
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        let eorCount = content.components(separatedBy: "<EOR>").count - 1
        XCTAssertEqual(eorCount, 5, "Each of the 5 records must have an <EOR> marker")
    }

    func testADIFExport_SOTAModifier() {
        let manager = LogbookManager()

        let entry = LogEntry(
            callsign: "HB9ABC",
            grid: "JN47",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: 14_074_000,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: "EA4IQL/P",
            cqModifier: "SOTA",
            mySigInfo: "EA4/MD-001",
            country: nil,
            flag: nil
        )

        let adifURL = manager.saveToADIF([entry])
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        XCTAssertTrue(content.contains("<MY_SIG:4>SOTA"), "SOTA modifier must produce MY_SIG tag")
        XCTAssertTrue(content.contains("<MY_SIG_INFO:10>EA4/MD-001"), "SOTA reference must appear in MY_SIG_INFO")
    }

    func testADIFExport_WWFFModifier() {
        let manager = LogbookManager()

        let entry = LogEntry(
            callsign: "F5ABC",
            grid: "JN18",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: 7_074_000,
            mode: "FT8",
            band: "40m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: "EA4IQL",
            cqModifier: "WWFF",
            mySigInfo: "EAFF-0456",
            country: nil,
            flag: nil
        )

        let adifURL = manager.saveToADIF([entry])
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        XCTAssertTrue(content.contains("<MY_SIG:4>WWFF"), "WWFF modifier must produce MY_SIG tag")
        XCTAssertTrue(content.contains("<MY_SIG_INFO:9>EAFF-0456"), "WWFF reference must appear in MY_SIG_INFO")
    }

    func testADIFExport_FullRoundTrip_AllFieldsPreserved() throws {
        // Export a fully-populated entry, then import it back; every field must survive
        let manager = LogbookManager()

        let originalDate = Date(timeIntervalSince1970: 1_700_000_123)

        let original = LogEntry(
            callsign: "W1AW",
            grid: "FN31pr",
            date: originalDate,
            frequencyHz: 14_074_000,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "+05",
            stationCallsign: "EA4IQL/P",
            cqModifier: "POTA",
            mySigInfo: "EA-5678",
            country: nil,
            flag: nil
        )

        let adifURL = manager.saveToADIF([original])
        XCTAssertNotNil(adifURL)

        let imported = try manager.loadEntries()
        XCTAssertEqual(imported.count, 1)

        let entry = imported[0]
        XCTAssertEqual(entry.callsign, "W1AW")
        XCTAssertEqual(entry.grid, "FN31pr")
        XCTAssertEqual(entry.date, originalDate)
        XCTAssertEqual(entry.frequencyHz ?? 0, 14_074_000, accuracy: 0.5)
        XCTAssertEqual(entry.mode, "FT8")
        XCTAssertEqual(entry.band, "20m")
        XCTAssertEqual(entry.rstSent, "-10")
        XCTAssertEqual(entry.rstRcvd, "+05")
        XCTAssertEqual(entry.stationCallsign, "EA4IQL/P")
        XCTAssertEqual(entry.cqModifier, "POTA")
        XCTAssertEqual(entry.mySigInfo, "EA-5678")
    }

    func testADIFExport_FrequencyUsesDecimalPoint_NotComma() {
        // ADIF spec requires decimal point — locale-independent
        let manager = LogbookManager()

        let entry = LogEntry(
            callsign: "DL1ABC",
            grid: "JO31",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: 14_074_000,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "-08",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )

        let adifURL = manager.saveToADIF([entry])
        let content = (try? String(contentsOf: adifURL!, encoding: .utf8)) ?? ""

        // Extract frequency value
        let freqPattern = try! NSRegularExpression(pattern: "<FREQ:\\d+>([^ <]+)")
        let match = freqPattern.firstMatch(in: content, range: NSRange(content.startIndex..., in: content))
        XCTAssertNotNil(match, "FREQ tag must be present")

        let freqValue = String(content[Range(match!.range(at: 1), in: content)!])
        XCTAssertFalse(freqValue.contains(","), "Frequency must use decimal point, not comma")
        XCTAssertTrue(freqValue.contains("."), "Frequency must contain a decimal point")
    }

    @MainActor
    func testCreateLogEntry_WithCallsignIncludingSuffix() {
        // In FT8/FT4, user enters callsign with suffix directly (e.g., "EA4IQL/P")
        UserDefaults.standard.set("EA4IQL/P", forKey: "callsign")
        
        let qso = QSOStatusManager()
        
        let entry = qso.createLogEntry(
            dxCallsign: "K1XYZ",
            dxLocator: "FN31",
            qsoDate: Date(timeIntervalSince1970: 1_700_000_000),
            band: .band20m,
            isFT4: false,
            rstSent: -10,
            rstRcvd: -8
        )
        
        // Callsign suffix is preserved as stored
        XCTAssertEqual(entry.stationCallsign, "EA4IQL/P")
        
        UserDefaults.standard.removeObject(forKey: "callsign")
    }
    
    @MainActor
    func testCreateLogEntry_WithCQModifier() {
        UserDefaults.standard.set("EA4IQL/MM", forKey: "callsign")
        UserDefaults.standard.set("POTA", forKey: "cqModifier")
        UserDefaults.standard.set("EA-1234", forKey: "myPotaRef")
        
        let qso = QSOStatusManager()
        qso.startCallingCQ()
        
        let entry = qso.createLogEntry(
            dxCallsign: "K1XYZ",
            dxLocator: "FN31",
            qsoDate: Date(timeIntervalSince1970: 1_700_000_000),
            band: .band20m,
            isFT4: false,
            rstSent: -10,
            rstRcvd: -8
        )
        
        // Callsign with suffix is preserved
        XCTAssertEqual(entry.stationCallsign, "EA4IQL/MM")
        // CQ modifier is separate
        XCTAssertEqual(entry.cqModifier, "POTA")
        XCTAssertEqual(entry.mySigInfo, "EA-1234")
        
        UserDefaults.standard.removeObject(forKey: "callsign")
        UserDefaults.standard.removeObject(forKey: "cqModifier")
        UserDefaults.standard.removeObject(forKey: "myPotaRef")
    }

    // MARK: - Error Handling Tests

    func testLoadEntriesThrowsForCorruptedFile() throws {
        // Write garbage content to the logbook file path so loadEntries() throws
        let manager = LogbookManager()
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let logURL = docs.appendingPathComponent("ft8_log.adi")

        // Write invalid (non-UTF8-parseable as ADIF) data
        let garbage = Data([0xFF, 0xFE, 0x00])
        try garbage.write(to: logURL)

        // Since the ADIF error-surfacing fix, loadEntries throws for unreadable
        // content instead of silently returning an empty list.
        XCTAssertThrowsError(try manager.loadEntries())

        // Clean up
        try? fileManager.removeItem(at: logURL)
    }

    func testImportFromADIFReturnsErrorForUnreadableFile() throws {
        let manager = LogbookManager()
        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/path/file.adi")
        let result = manager.importFromADIF(url: nonExistentURL, existingEntries: [])
        XCTAssertNotNil(result.error, "importFromADIF should return an error for an unreadable file")
        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.duplicates, 0)
    }

    // MARK: - Backup & Restore Tests

    private func makeTestEntry(callsign: String = "W1AW") -> LogEntry {
        LogEntry(
            callsign: callsign,
            grid: "FN31",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            frequencyHz: 14_074_000,
            mode: "FT8",
            band: "20m",
            rstSent: "-10",
            rstRcvd: "+05",
            stationCallsign: nil,
            cqModifier: nil,
            mySigInfo: nil,
            country: nil,
            flag: nil
        )
    }

    func testHasBackupReturnsFalseWhenNoBackupExists() throws {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let backupURL = docs.appendingPathComponent("ft8_log.adi.bak")
        try? fileManager.removeItem(at: backupURL)

        let manager = LogbookManager()
        XCTAssertFalse(manager.hasBackup, "hasBackup should be false when no backup file exists")
    }

    func testSaveInternalLogCreatesBackup() throws {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let logURL = docs.appendingPathComponent("ft8_log.adi")
        let backupURL = docs.appendingPathComponent("ft8_log.adi.bak")
        defer {
            try? fileManager.removeItem(at: backupURL)
        }

        let manager = LogbookManager()
        let entry = makeTestEntry()

        // Write the initial log so there is something to back up
        _ = manager.saveToADIF([entry])
        XCTAssertTrue(fileManager.fileExists(atPath: logURL.path), "Log file must exist before the backup test")

        try? fileManager.removeItem(at: backupURL)
        XCTAssertFalse(manager.hasBackup, "No backup should exist before saveInternalLog")

        _ = manager.saveInternalLog([entry])

        XCTAssertTrue(manager.hasBackup, "hasBackup should be true after saveInternalLog")
        XCTAssertTrue(fileManager.fileExists(atPath: backupURL.path), "Backup file must exist on disk")
    }

    func testHasBackupReturnsTrueAfterBackupIsCreated() throws {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let backupURL = docs.appendingPathComponent("ft8_log.adi.bak")
        defer { try? fileManager.removeItem(at: backupURL) }

        let manager = LogbookManager()
        _ = manager.saveToADIF([makeTestEntry()])
        _ = manager.saveInternalLog([makeTestEntry()])

        XCTAssertTrue(manager.hasBackup)
    }

    func testRestoreFromBackupThrowsWhenNoBackupExists() throws {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let backupURL = docs.appendingPathComponent("ft8_log.adi.bak")
        try? fileManager.removeItem(at: backupURL)

        let manager = LogbookManager()
        XCTAssertThrowsError(try manager.restoreFromBackup()) { error in
            guard let logbookError = error as? LogbookError else {
                XCTFail("Expected LogbookError, got \(type(of: error))")
                return
            }
            XCTAssertEqual(logbookError.errorDescription, "No backup file is available to restore from.")
        }
    }

    func testRestoreFromBackupRestoresEntries() throws {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let logURL = docs.appendingPathComponent("ft8_log.adi")
        let backupURL = docs.appendingPathComponent("ft8_log.adi.bak")
        defer {
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.removeItem(at: logURL)
        }

        let manager = LogbookManager()
        let entry = makeTestEntry(callsign: "EA4IQL")

        // Create a valid log and backup
        _ = manager.saveToADIF([entry])
        _ = manager.saveInternalLog([entry])
        XCTAssertTrue(manager.hasBackup, "Backup must exist before restore test")

        // Corrupt the main log file
        try "corrupted garbage".write(to: logURL, atomically: true, encoding: .utf8)

        // Restore should recover the backup
        let restored = try manager.restoreFromBackup()
        XCTAssertEqual(restored.count, 1, "Restored log should contain 1 entry")
        XCTAssertEqual(restored.first?.callsign, "EA4IQL")
    }

    func testLogbookErrorNoBackupAvailableDescription() {
        let error = LogbookError.noBackupAvailable
        XCTAssertEqual(error.errorDescription, "No backup file is available to restore from.")
    }

}
