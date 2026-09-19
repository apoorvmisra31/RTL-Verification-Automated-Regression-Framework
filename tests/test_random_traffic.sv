//=============================================================================
// Test: test_random_traffic
// Description: Constrained random stimulus test with repeatable pseudo-random
//              seed. Executes 200 mixed cycles of random writes, reads,
//              simultaneous transactions, and bursts, followed by a full drain.
//=============================================================================

task automatic run_test_random_traffic(input int seed = 42);
    int errs;
    int rand_val;
    logic [7:0] rand_data;
    logic [7:0] rdata;
    int op_choice;
    int dummy_seed;

    print_test_header("test_random_traffic", $sformatf("200 cycles of constrained random traffic (seed=%0d).", seed));

    // Initialize PRNG seed
    dummy_seed = $urandom(seed);

    driver.reset_dut(3);
    scoreboard.reset_model();
    driver.idle(2);

    log_info($sformatf("Starting 200 cycles of randomized traffic with seed %0d...", seed));

    for (int cycle = 0; cycle < 200; cycle++) begin
        rand_val  = $urandom;
        op_choice = rand_val % 100;
        rand_data = $urandom & 8'hFF;

        if (op_choice < 35) begin
            // 35% Write (if not full, or occasionally test overflow attempt)
            if (!dut.full || (rand_val[7:6] == 2'b00)) begin
                driver.write_single(rand_data);
            end else begin
                driver.idle(1);
            end
        end else if (op_choice < 70) begin
            // 35% Read (if not empty, or occasionally test underflow attempt)
            if (!dut.empty || (rand_val[7:6] == 2'b01)) begin
                driver.read_single(rdata);
            end else begin
                driver.idle(1);
            end
        end else if (op_choice < 90) begin
            // 20% Simultaneous Read and Write
            if (!dut.empty) begin
                driver.simultaneous_rw(rand_data, rdata);
            end else begin
                driver.write_single(rand_data);
            end
        end else begin
            // 10% Idle cycle
            driver.idle(1);
        end

        // Periodically inject a mini burst (every ~40 cycles)
        if (cycle % 40 == 0 && cycle > 0) begin
            if (dut.count <= 10) begin
                for (int b = 0; b < 3; b++) begin
                    driver.drive_write($urandom & 8'hFF);
                end
                driver.drive_write_stop();
            end else if (dut.count >= 4) begin
                for (int b = 0; b < 3; b++) begin
                    driver.drive_read(rdata);
                end
                driver.drive_read_stop();
            end
        end
    end

    driver.idle(5);

    // Drain all remaining items in the FIFO
    log_info($sformatf("Stimulus complete. Draining remaining %0d items from FIFO...", dut.count));
    while (!dut.empty) begin
        driver.read_single(rdata);
    end

    driver.idle(5);

    if (!dut.empty || dut.count !== 0) begin
        log_error("FIFO was not empty after final drain!");
    end

    if (scoreboard.get_pending_items() !== 0) begin
        log_error($sformatf("Scoreboard still has %0d items pending after final drain!", scoreboard.get_pending_items()));
    end

    scoreboard.report_summary(errs);
    errs += assertions.get_assertion_failures();
    print_test_footer("test_random_traffic", errs);
endtask
