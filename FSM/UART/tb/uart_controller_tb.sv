`timescale 1ns/1ps

module uart_controller_tb;

    //-------------------------------------------------------------------
    // Parameters (fast settings chosen purely to keep simulation short)
    //-------------------------------------------------------------------
    localparam int CLK_FREQ_HZ = 16_000_000;
    localparam int BAUD_RATE   = 1_000_000;
    localparam int DATA_BITS   = 8;
    localparam int CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ_HZ; // 62.5 -> use real
    localparam real CLK_PERIOD   = 1_000_000_000.0 / CLK_FREQ_HZ;
    localparam int  BIT_PERIOD_NS = 1_000_000_000 / BAUD_RATE;

    //-------------------------------------------------------------------
    // DUT signals
    //-------------------------------------------------------------------
    logic                   clk;
    logic                   rst_n;
    logic                   tx_start;
    logic [DATA_BITS-1:0]   tx_data;
    logic                   tx_busy;
    logic                   tx_done;
    logic                   tx_line;

    logic                   rx_line;
    logic [DATA_BITS-1:0]   rx_data;
    logic                   rx_valid;
    logic                   rx_frame_err;

    // Loopback mux: normally rx_line follows tx_line, except when we
    // force a corrupted frame for the framing-error corner case.
    logic force_bad_stop;
    assign rx_line = force_bad_stop ? 1'b0 : tx_line;

    //-------------------------------------------------------------------
    // DUT instantiation
    //-------------------------------------------------------------------
    uart_controller #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE),
        .DATA_BITS   (DATA_BITS)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .tx_start     (tx_start),
        .tx_data      (tx_data),
        .tx_busy      (tx_busy),
        .tx_done      (tx_done),
        .tx           (tx_line),
        .rx           (rx_line),
        .rx_data      (rx_data),
        .rx_valid     (rx_valid),
        .rx_frame_err (rx_frame_err)
    );

    //-------------------------------------------------------------------
    // Clock generation
    //-------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    //-------------------------------------------------------------------
    // Reset generation
    //-------------------------------------------------------------------
    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
    end

    //-------------------------------------------------------------------
    // Scoreboard / bookkeeping
    //-------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    //-------------------------------------------------------------------
    // Task: send a byte and check it is received correctly via loopback
    //-------------------------------------------------------------------
    task automatic send_and_check(input logic [DATA_BITS-1:0] data);
        logic [DATA_BITS-1:0] captured;
        bit                   got_valid;
        begin
            @(posedge clk);
            tx_data  <= data;
            tx_start <= 1'b1;
            @(posedge clk);
            tx_start <= 1'b0;

            got_valid = 1'b0;
            fork
                begin : wait_valid
                    @(posedge rx_valid);
                    captured  = rx_data;
                    got_valid = 1'b1;
                end
                begin : timeout
                    repeat (20 * ((CLK_FREQ_HZ/BAUD_RATE)*10)) @(posedge clk);
                end
            join_any
            disable fork;

            if (!got_valid) begin
                $display("[%0t] FAIL: timeout waiting for rx_valid, data=0x%0h", $time, data);
                fail_count++;
            end else if (captured !== data) begin
                $display("[%0t] FAIL: sent=0x%0h received=0x%0h", $time, data, captured);
                fail_count++;
            end else begin
                $display("[%0t] PASS: byte 0x%0h transmitted and received correctly", $time, data);
                pass_count++;
            end

            // Allow tx to fully return to idle before next transaction
            wait (tx_busy == 1'b0);
            @(posedge clk);
        end
    endtask

    //-------------------------------------------------------------------
    // Task: check tx_busy behaves correctly during a transfer
    //-------------------------------------------------------------------
    task automatic check_busy_flag();
        begin
            @(posedge clk);
            tx_data  <= 8'hA5;
            tx_start <= 1'b1;
            @(posedge clk);
            tx_start <= 1'b0;
            if (tx_busy !== 1'b1) begin
                $display("[%0t] FAIL: tx_busy did not assert after tx_start", $time);
                fail_count++;
            end else begin
                $display("[%0t] PASS: tx_busy asserted correctly after tx_start", $time);
                pass_count++;
            end
            wait (tx_busy == 1'b0);
            @(posedge clk);
        end
    endtask

    //-------------------------------------------------------------------
    // Task: corner case - corrupted stop bit forces rx_frame_err
    //-------------------------------------------------------------------
    task automatic check_framing_error();
        bit got_err;
        begin
            got_err = 1'b0;
            @(posedge clk);
            tx_data  <= 8'h3C;
            tx_start <= 1'b1;
            @(posedge clk);
            tx_start <= 1'b0;

            // Force the RX line low during the expected stop-bit window
            // (approx after start + 8 data bits) to corrupt the stop bit.
            repeat (9 * (CLK_FREQ_HZ/BAUD_RATE)) @(posedge clk);
            force_bad_stop = 1'b1;
            repeat (1 * (CLK_FREQ_HZ/BAUD_RATE)) @(posedge clk);

            fork
                begin
                    @(posedge rx_frame_err);
                    got_err = 1'b1;
                end
                begin
                    repeat (5 * (CLK_FREQ_HZ/BAUD_RATE)) @(posedge clk);
                end
            join_any
            disable fork;

            force_bad_stop = 1'b0;

            if (got_err) begin
                $display("[%0t] PASS: rx_frame_err correctly asserted on bad stop bit", $time);
                pass_count++;
            end else begin
                $display("[%0t] FAIL: rx_frame_err was not asserted on bad stop bit", $time);
                fail_count++;
            end
            wait (tx_busy == 1'b0);
            @(posedge clk);
            repeat (2 * (CLK_FREQ_HZ/BAUD_RATE)) @(posedge clk); // settle
        end
    endtask

    //-------------------------------------------------------------------
    // Main stimulus
    //-------------------------------------------------------------------
    initial begin
        $dumpfile("uart_controller_tb.vcd");
        $dumpvars(0, uart_controller_tb);

        tx_start        = 1'b0;
        tx_data         = '0;
        force_bad_stop  = 1'b0;

        wait (rst_n == 1'b1);
        repeat (3) @(posedge clk);

        $display("=========================================================");
        $display(" UART CONTROLLER SELF-CHECKING TESTBENCH");
        $display("=========================================================");

        // ---- Directed tests: known patterns / corner values ----
        send_and_check(8'h00);   // all zeros
        send_and_check(8'hFF);   // all ones
        send_and_check(8'hA5);   // alternating
        send_and_check(8'h5A);   // alternating (inverse)
        send_and_check(8'h01);   // single LSB set
        send_and_check(8'h80);   // single MSB set

        // ---- Busy flag corner-case check ----
        check_busy_flag();

        // ---- Randomized tests ----
        for (int i = 0; i < 20; i++) begin
            send_and_check($urandom_range(0, 255));
        end

        // ---- Framing error corner case ----
        check_framing_error();

        // ---- Back-to-back transmissions (stress corner case) ----
        for (int i = 0; i < 5; i++) begin
            send_and_check($urandom_range(0, 255));
        end

        //-------------------------------------------------------------
        // Final report
        //-------------------------------------------------------------
        $display("=========================================================");
        $display(" TEST SUMMARY: PASS = %0d, FAIL = %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display(" RESULT: ALL TESTS PASSED");
        else
            $display(" RESULT: TESTS FAILED");
        $display("=========================================================");

        $finish;
    end

    //-------------------------------------------------------------------
    // Watchdog timeout to guarantee simulation termination
    //-------------------------------------------------------------------
    initial begin
        #2_000_000; // 2 ms abso
