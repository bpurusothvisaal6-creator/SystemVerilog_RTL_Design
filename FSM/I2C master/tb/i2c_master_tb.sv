`timescale 1ns/1ps

module i2c_master_tb;

    localparam int CLK_FREQ_HZ = 20_000_000;
    localparam int I2C_CLK_HZ  = 400_000;
    localparam int ADDR_WIDTH  = 7;
    localparam real CLK_PERIOD = 1_000_000_000.0 / CLK_FREQ_HZ;

    localparam logic [6:0] SLAVE_ADDR_OK  = 7'h50;
    localparam logic [6:0] SLAVE_ADDR_BAD = 7'h55; // no BFM responds to this address

    //-------------------------------------------------------------------
    // DUT signals
    //-------------------------------------------------------------------
    logic                  clk;
    logic                  rst_n;
    logic                  start_txn;
    logic [ADDR_WIDTH-1:0] slave_addr;
    logic                  rw;
    logic [7:0]            wr_data;
    logic                  repeated_start;
    logic [7:0]            rd_data;
    logic                  rd_valid;
    logic                  busy;
    logic                  done;
    logic                  ack_error;

    wire scl, sda;
    pullup(scl);
    pullup(sda);

    //-------------------------------------------------------------------
    // DUT instantiation
    //-------------------------------------------------------------------
    i2c_master #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .I2C_CLK_HZ  (I2C_CLK_HZ),
        .ADDR_WIDTH  (ADDR_WIDTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .start_txn      (start_txn),
        .slave_addr     (slave_addr),
        .rw             (rw),
        .wr_data        (wr_data),
        .repeated_start (repeated_start),
        .rd_data        (rd_data),
        .rd_valid       (rd_valid),
        .busy           (busy),
        .done           (done),
        .ack_error      (ack_error),
        .scl            (scl),
        .sda            (sda)
    );

    //-------------------------------------------------------------------
    // Clock / reset generation
    //-------------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
    end

    //-------------------------------------------------------------------
    // Behavioral I2C slave BFM (address SLAVE_ADDR_OK, testbench-only)
    //-------------------------------------------------------------------
    logic [7:0] slave_tx_pattern;   // next byte the BFM returns on a read
    logic [7:0] slave_rx_captured;  // last byte the BFM captured on a write
    logic       slave_saw_txn;

    initial begin
        logic [7:0] addr_rw_byte;
        logic [7:0] data_byte;
        logic [6:0] rcv_addr;
        logic       rcv_rw;

        slave_tx_pattern  = 8'h00;
        slave_rx_captured = 8'h00;

        forever begin
            @(negedge sda);
            if (scl !== 1'b1) begin
                continue; // spurious edge, not a real START condition
            end
            slave_saw_txn = 1'b0;

            // ---- Receive address + R/W byte ----
            addr_rw_byte = 8'h00;
            for (int i = 0; i < 8; i++) begin
                @(posedge scl);
                addr_rw_byte = {addr_rw_byte[6:0], sda};
                @(negedge scl);
            end
            rcv_addr = addr_rw_byte[7:1];
            rcv_rw   = addr_rw_byte[0];

            if (rcv_addr == SLAVE_ADDR_OK) begin
                slave_saw_txn = 1'b1;
                force sda = 1'b0; // drive ACK low
                @(posedge scl);
                @(negedge scl);
                release sda;

                if (rcv_rw == 1'b0) begin
                    // ---- WRITE: receive one data byte, then ACK ----
                    data_byte = 8'h00;
                    for (int i = 0; i < 8; i++) begin
                        @(posedge scl);
                        data_byte = {data_byte[6:0], sda};
                        @(negedge scl);
                    end
                    slave_rx_captured = data_byte;
                    force sda = 1'b0;
                    @(posedge scl);
                    @(negedge scl);
                    release sda;
                end else begin
                    // ---- READ: drive one data byte, then sample master ack ----
                    for (int i = 0; i < 8; i++) begin
                        if (slave_tx_pattern[7-i] == 1'b0) force sda = 1'b0;
                        else release sda;
                        @(posedge scl);
                        @(negedge scl);
                    end
                    release sda;
                    @(posedge scl); // sample master's ACK/NACK (informational only)
                    @(negedge scl);
                end
            end else begin
                // Address mismatch: leave the bus alone (NACK by omission)
            end
        end
    end

    //-------------------------------------------------------------------
    // Scoreboard
    //-------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    //-------------------------------------------------------------------
    // Task: issue one transaction and wait for completion
    //-------------------------------------------------------------------
    task automatic do_txn(input logic [ADDR_WIDTH-1:0] addr,
                           input logic                 read_op,
                           input logic [7:0]            data_out,
                           input logic                  rstart);
        begin
            @(posedge clk);
            slave_addr     <= addr;
            rw             <= read_op;
            wr_data        <= data_out;
            repeated_start <= rstart;
            start_txn      <= 1'b1;
            @(posedge clk);
            start_txn      <= 1'b0;
            wait (done == 1'b1);
            @(posedge clk);
        end
    endtask

    //-------------------------------------------------------------------
    // Main stimulus
    //-------------------------------------------------------------------
    initial begin
        $dumpfile("i2c_master_tb.vcd");
        $dumpvars(0, i2c_master_tb);

        start_txn      = 1'b0;
        slave_addr     = '0;
        rw             = 1'b0;
        wr_data        = '0;
        repeated_start = 1'b0;

        wait (rst_n == 1'b1);
        repeat (3) @(posedge clk);

        $display("=========================================================");
        $display(" I2C MASTER CONTROLLER SELF-CHECKING TESTBENCH");
        $display("=========================================================");

        //---------------------------------------------------------------
        // Test 1: WRITE transaction, directed values
        //---------------------------------------------------------------
        begin
            automatic logic [7:0] pattern[4] = '{8'h00, 8'hFF, 8'hA5, 8'h5A};
            for (int i = 0; i < 4; i++) begin
                do_txn(SLAVE_ADDR_OK, 1'b0, pattern[i], 1'b0);
                if (ack_error !== 1'b0) begin
                    $display("[%0t] FAIL: unexpected ack_error on write 0x%0h", $time, pattern[i]);
                    fail_count++;
                end else if (slave_rx_captured !== pattern[i]) begin
                    $display("[%0t] FAIL: slave captured 0x%0h expected 0x%0h", $time, slave_rx_captured, pattern[i]);
                    fail_count++;
                end else begin
                    $display("[%0t] PASS: write 0x%0h received correctly by slave", $time, pattern[i]);
                    pass_count++;
                end
            end
        end

        //---------------------------------------------------------------
        // Test 2: READ transaction, directed values
        //---------------------------------------------------------------
        begin
            automatic logic [7:0] pattern[4] = '{8'h00, 8'hFF, 8'h3C, 8'hC3};
            for (int i = 0; i < 4; i++) begin
                slave_tx_pattern = pattern[i];
                do_txn(SLAVE_ADDR_OK, 1'b1, 8'h00, 1'b0);
                if (ack_error !== 1'b0) begin
                    $display("[%0t] FAIL: unexpected ack_error on read", $time);
                    fail_count++;
                end else if (rd_data !== pattern[i]) begin
                    $display("[%0t] FAIL: master read 0x%0h expected 0x%0h", $time, rd_data, pattern[i]);
                    fail_count++;
                end else begin
                    $display("[%0t] PASS: read 0x%0h received correctly by master", $time, rd_data);
                    pass_count++;
                end
            end
        end

        //---------------------------------------------------------------
        // Test 3: Address NACK (unmapped address) -> ack_error must assert
        //---------------------------------------------------------------
        do_txn(SLAVE_ADDR_BAD, 1'b0, 8'hDE, 1'b0);
        if (ack_error !== 1'b1) begin
            $display("[%0t] FAIL: ack_error not asserted for unmapped address", $time);
            fail_count++;
        end else begin
            $display("[%0t] PASS: ack_error correctly asserted for unmapped address", $time);
            pass_count++;
        end

        //---------------------------------------------------------------
        // Test 4: Repeated START - write a "pointer" byte then read it
        // back on a chained transaction (bus never released to idle
        // between the two).
        //---------------------------------------------------------------
        slave_tx_pattern = 8'h7E;
        do_txn(SLAVE_ADDR_OK, 1'b0, 8'h11, 1'b1); // write, keep bus held
        if (busy !== 1'b1) begin
            $display("[%0t] FAIL: bus not held busy after repeated_start write", $time);
            fail_count++;
        end else begin
            $display("[%0t] PASS: bus correctly held busy for repeated START", $time);
            pass_count++;
        end
        do_txn(SLAVE_ADDR_OK, 1'b1, 8'h00, 1'b0); // repeated START + read, then STOP
        if (rd_data !== 8'h7E) begin
            $display("[%0t] FAIL: repeated-START read got 0x%0h expected 0x7E", $time, rd_data);
            fail_count++;
        end else begin
            $display("[%0t] PASS: repeated-START read returned correct byte", $time);
            pass_count++;
        end

        //---------------------------------------------------------------
        // Test 5: Randomized write transactions
        //---------------------------------------------------------------
        for (int i = 0; i < 15; i++) begin
            automatic logic [7:0] rnd = $urandom_range(0, 255);
            do_txn(SLAVE_ADDR_OK, 1'b0, rnd, 1'b0);
            if (slave_rx_captured !== rnd) begin
                $display("[%0t] FAIL: random write mismatch: got 0x%0h expected 0x%0h", $time, slave_rx_captured, rnd);
                fail_count++;
            end else begin
                $display("[%0t] PASS: random write 0x%0h verified", $time, rnd);
                pass_count++;
            end
        end

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
    // Watchdog
    //-------------------------------------------------------------------
    initial begin
        #5_000_000;
        $display("[%0t] ERROR: Global watchdog timeout - simulation did not finish", $time);
        $finish;
    end

endmodule

