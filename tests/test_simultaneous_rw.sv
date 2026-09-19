//=============================================================================
// Test: test_simultaneous_rw
// Description: Validates concurrent write and read operations. Tests steady-state
//              occupancy during continuous simultaneous transactions when partially
//              filled, and verifies non-overflow simultaneous RW at full capacity.
//=============================================================================

task automatic run_test_simultaneous_rw();
    int errs;
    logic [7:0] rdata;
    print_test_header("test_simultaneous_rw", "Concurrent write and read at partial and full capacity.");

    driver.reset_dut(3);
    scoreboard.reset_model();
    driver.idle(2);

    // 1. Pre-fill with 8 items
    log_info("Pre-filling FIFO with 8 items...");
    for (int i = 0; i < 8; i++) begin
        driver.drive_write(8'h10 + i[7:0]);
    end
    driver.drive_write_stop();
    driver.idle(2);

    if (dut.count !== 8) begin
        log_error($sformatf("Pre-fill failed! count=%0d (exp 8)", dut.count));
    end

    // 2. Perform 16 consecutive simultaneous write and read operations
    log_info("Executing 16 simultaneous read/write operations at count=8...");
    for (int i = 0; i < 16; i++) begin
        driver.simultaneous_rw(8'h80 + i[7:0], rdata);
        if (dut.count !== 8) begin
            log_error($sformatf("Simultaneous RW: count changed! count=%0d (exp 8) at iter %0d", dut.count, i));
        end
    end

    driver.idle(2);

    // 3. Fill to capacity (add 8 more items to reach 16)
    log_info("Filling remaining 8 items to reach full capacity...");
    for (int i = 0; i < 8; i++) begin
        driver.drive_write(8'hA0 + i[7:0]);
    end
    driver.drive_write_stop();
    driver.idle(2);

    if (dut.count !== 16 || !dut.full) begin
        log_error($sformatf("Full pre-fill failed! count=%0d, full=%0b", dut.count, dut.full));
    end

    // 4. Perform 8 simultaneous write and read operations while FULL
    log_info("Executing 8 simultaneous read/write operations at FULL capacity (count=16)...");
    for (int i = 0; i < 8; i++) begin
        driver.simultaneous_rw(8'hF0 + i[7:0], rdata);
        if (dut.count !== 16 || !dut.full) begin
            log_error($sformatf("Simultaneous RW while full: count changed! count=%0d, full=%0b", dut.count, dut.full));
        end
        if (dut.overflow) begin
            log_error("Simultaneous RW while full incorrectly asserted overflow!");
        end
    end

    driver.idle(2);

    // 5. Drain all 16 items
    log_info("Draining FIFO after simultaneous RW tests...");
    for (int i = 0; i < 16; i++) begin
        driver.drive_read(rdata);
    end
    driver.drive_read_stop();
    driver.idle(3);

    if (!dut.empty || dut.count !== 0) begin
        log_error($sformatf("FIFO should be empty after drain! empty=%0b, count=%0d", dut.empty, dut.count));
    end

    driver.idle(5);
    scoreboard.report_summary(errs);
    errs += assertions.get_assertion_failures();
    print_test_footer("test_simultaneous_rw", errs);
endtask
