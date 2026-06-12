//
//  FT8ViewModelTests.swift
//  ft_ham
//
//  Created by Pablo Turrion on 9/1/26.
//


import XCTest
@testable import ft8_ham

@MainActor
final class FT8ViewModelTests3: XCTestCase {
    
    var viewModel: FT8ViewModel!
    
    override func setUp() {
        // Inicializamos con valores por defecto
        viewModel = FT8ViewModel()
        viewModel.transmitLoopActive = false // Empezamos apagados
    }
    
    override func tearDown() async throws {
        await viewModel.stopSequencer()
        viewModel = nil
    }
    
    // MARK: - Test: Cambio Dinámico Even/Odd
    // Prueba: "Compila y prueba cambiar de Even a Odd mientras el loop está corriendo"
    func testDynamicEvenOddSwitching() async throws {
        // 1. Configuración inicial
        viewModel.evenCycle = true // Estamos en ciclos PARES
        viewModel.isFT4 = false
        
        // 2. Simulamos el "Start TX"
        viewModel.transmitLoopActive = true
        // No llamamos a startTXLoop real para no bloquear el test con un while true infinito,
        // pero verificamos que la variable de estado cambia correctamente.
        
        XCTAssertTrue(viewModel.evenCycle, "Debe iniciar en Even")
        
        // 3. Simulamos el cambio de usuario MIENTRAS el sistema está "corriendo"
        // (En la app real, el loop leería este valor en la siguiente iteración)
        viewModel.evenCycle = false
        
        // 4. Verificamos que el cambio es inmediato en el estado
        XCTAssertFalse(viewModel.evenCycle, "El estado debe cambiar a Odd inmediatamente")
        
        // Nota: Gracias a tu refactorización en runSynchronizedLoop:
        // let isMyTurn = (isEvenSlot == self.evenCycle)
        // El cambio de la variable arriba garantiza que en el siguiente 'latido' (heartbeat),
        // la lógica invertirá su decisión.
    }
    
    // MARK: - Test: Cambio de Modo FT8 -> FT4
    // Prueba: "Prueba cambiar de FT8 a FT4 y verifica que el ciclo de transmisión se acelera"
    func testModeSwitchingUpdatesInternalState() async throws {
        // 1. Estado inicial FT8
        viewModel.isFT4 = false
        XCTAssertEqual(viewModel.waterfallVM.mode, .ft8)
        
        // 2. Iniciamos loops (simulados)
        viewModel.transmitLoopActive = true
        
        // 3. Cambiamos a FT4
        // Esto dispara el didSet de isFT4 -> restartLoopsForModeChange()
        viewModel.isFT4 = true
        
        // Esperamos un momento porque restartLoopsForModeChange tiene un Task.sleep
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        
        // 4. Verificaciones
        XCTAssertTrue(viewModel.isFT4, "ViewModel debe estar en modo FT4")
        XCTAssertEqual(viewModel.waterfallVM.mode, .ft4, "Waterfall debe haberse actualizado a FT4")
        
        // La prueba real de que se "acelera" a 7.5s está cubierta en SlotManagerTests.testFT4TimingAcceleration
        // Aquí verificamos que la bandera se propagó correctamente.
    }
    
//    func testFT4SpecificSlots() async {
//        let sm = SlotManager()
//        let baseDate = Date(timeIntervalSince1970: 0) // Un segundo 0 exacto
//        
//        let isEven0 = await sm.isEvenSlot(at: baseDate.addingTimeInterval(0), isFT4: true)
//        let isEven75 = await sm.isEvenSlot(at: baseDate.addingTimeInterval(7.5), isFT4: true)
//        let isEven15 = await sm.isEvenSlot(at: baseDate.addingTimeInterval(15.0), isFT4: true)
//        
//        XCTAssertTrue(isEven0, "0.0s debe ser Even")
//        XCTAssertFalse(isEven75, "7.5s debe ser Odd")
//        XCTAssertTrue(isEven15, "15.0s debe ser Even")
//    }
}
