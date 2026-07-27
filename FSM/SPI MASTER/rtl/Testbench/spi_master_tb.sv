`timescale 1ns/1ps

module spi_master_tb;

    localparam int CLK_FREQ_HZ = 20_000_000;
    localparam int SPI_CLK_HZ  = 2_000_000;
    localparam int DATA_WIDTH  = 8;
    localparam real CLK_PERIOD = 1_000_000_000.0 / CLK_FREQ_HZ;

    //-------------------------------------------------------------------
    // DUT signals
    //-------------------------------------------------------------------
    logic                  clk;
    logic                  rst_n;
    logic                  cpol, cpha;
    logic                  start;
    logic [DATA_WIDTH-1:0] tx_data;
    logic [DATA_WIDTH-1:0] rx_data;
    logic                  busy, done;
    logic                  sclk;
    logic                  mosi;
    logic                  miso;
    logic                  cs_n;

    // Slave BFM driven / observed data
    logic [DATA_WIDTH-1:0] slave_tx_pattern;   // data slave will send back
    logic [DATA_WIDTH-1:0] slave_rx_captured;  // data slave captured from MOSI
    logic                  miso_drv;
    assign miso = cs_n ? 1'bz : miso_drv;

    //-------------------------------------------------------------------
    // DUT instantiation
    //-------------------------------------------------------------------
    spi_master #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .SPI_CLK_HZ  (SPI_CLK_HZ),
        .DATA_WIDTH  (DATA_WIDTH)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .cpol     (cpol),
        .cpha     (cpha),
        .start    (start),
        .tx_data  (tx_data),
        .rx_data  (rx_data),
        .busy     (busy),
        .done     (done),
        .sclk     (sclk),
        .mosi     (mosi),
        .miso     (miso),
        .cs_n     (cs_n)
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
    // Behavioral SPI slave BFM (non-synthesizable, testbench only)
    // Responds to each CS-active transaction using the currently
    // selected cpol/cpha to know when to sample / drive data.
    //-------------------------------------------------------------------
    task automatic wait_leading_edge();
        if (cpol == 1'b0) @(posedge sclk);
        else              @(negedge sclk);
    endtask

    task automatic wait_trailing_edge();
        if (cpol == 1'b0) @(negedge sclk);
        else              @(posedge sclk);
    endtask

    initial begin
        miso_drv = 1'b0;
        forever begin
            automatic logic [DATA_WIDTH-1:0] rx_shift_bfm = '0;
            @(negedge cs_n);
            if (cpha == 1'b0) miso_drv = slave_tx_pattern[DATA_WIDTH-1];
            for (int i = 0; i < DATA_WIDTH; i++) begin
                wait_leading_edge();
                if (cpha == 1'b0) begin
                    rx_shift_bfm = {rx_shift_bfm[DATA_WIDTH-2:0], mosi};
                end else begin
                    miso_drv = slave_tx_pattern[DATA_WIDTH-1-i];
                end
                wait_trailing_edge();
                if (cpha == 1'b1) begin
                    rx_shift_bfm = {rx_shift_bfm[DATA_WIDTH-2:0], mosi};
                end else if (i < DATA_WIDTH-1) begin
                    miso_drv = slave_tx_pattern[DATA_WIDTH-2-i];
                end
            end
            slave_rx_captured = rx_shift_bfm;
            @(posedge cs_n);
        end
    end

    //-------------------------------------------------------------------
    // Scoreboard
    //-------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    //-------------------------------------------------------------------
    // Task: run one transfer and self-check both directions of data
    //-------------------------------------------------------------------
    task automatic run_transfer(input logic [DATA_WIDTH-1:0] m_tx,
                                 input logic [DATA_WIDTH-1:0] s_tx);
        bit got_done;
        begin
            slave_tx_pattern = s_tx;
            @(posedge clk);
            tx_data <= m_tx;
            start   <= 1'b1;
            @(posedge clk);
            start   <= 1'b0;

            got_done = 1'b0;
            fork
                begin
                    @(posedge done);
                    got_done = 1'b1;
                end
                begin
                    repeat (2000) @(posedge clk);
                end
            join_any
            disable fork;

            if (!got_done) begin
                $display("[%0t] FAIL: timeout waiting for 'done' (cpol=%0b cpha=%0b)", $time, cpol, cpha);
                fail_count++;
            end else begin
                if (rx_data !== s_tx) begin
                    $display("[%0t] FAIL: master rx_data=0x%0h expected=0x%0h (cpol=%0b cpha=%0b)",
                              $time, rx_data, s_tx, cpol, cpha);
                    fail_count++;
                end else begin
                    $display("[%0t] PASS: master captured 0x%0h correctly (cpol=%0b cpha=%0b)",
                              $time, rx_data, cpol, cpha);
                    pass_count++;
                end

                if (slave_rx_captured !== m_tx) begin
                    $display("[%0t] FAIL: slave captured 0x%0h expected=0x%0h (cpol=%0b cpha=%0b)",
                              $time, slave_rx_captured, m_tx, cpol, cpha);
                    fail_count++;
                end else begin
                    $display("[%0t] PASS: slave captured 0x%0h correctly (cpol=%0b cpha=%0b)",
                              $time, slave_rx_captured, cpol, cpha);
                    pass_count++;
                end
            end

            @(posedge clk);
        end
    endtask

    //-------------------------------------------------------------------
    // Task: check busy / cs_n behavior (corner case)
    //-------------------------------------------------------------------
    task automatic check_cs_and_busy();
        begin
            if (cs_n !== 1'b1 || busy !== 1'b0) begin
                $display("[%0t] FAIL: cs_n/busy not idle before start (cs_n=%0b busy=%0b)", $time, cs_n, busy);
                fail_count++;
            end else begin
                $display("[%0t] PASS: cs_n and busy correctly idle before start", $time);
                pass_count++;
            end

            slave_tx_pattern = 8'h3C;
            @(posedge clk);
            tx_data <= 8'h96;
            start   <= 1'b1;
            @(posedge clk);
            start   <= 1'b0;
            @(posedge clk);

            if (cs_n !== 1'b0 || busy !== 1'b1) begin
                $display("[%0t] FAIL: cs_n/busy did not assert correctly after start", $time);
                fail_count++;
            end else begin
                $display("[%0t] PASS: cs_n asserted low and busy high after start", $time);
                pass_count++;
            end

            wait (busy == 1'b0);
            @(posedge clk);
        end
    endtask

    //-------------------------------------------------------------------
    // Main stimulus: sweep all four SPI modes with directed + random data
    //-------------------------------------------------------------------
    initial begin
        $dumpfile("spi_master_tb.vcd");
        $dumpvars(0, spi_master_tb);

        start            = 1'b0;
        tx_data          = '0;
        cpol             = 1'b0;
        cpha             = 1'b0;
        slave_tx_pattern = '0;

        wait (rst_n == 1'b1);
        repeat (3) @(posedge clk);

        $display("=========================================================");
        $display(" SPI MASTER CONTROLLER SELF-CHECKING TESTBENCH");
        $display("=========================================================");

        check_cs_and_busy();

        // ---- Sweep all 4 SPI modes with directed corner values ----
        for (int m = 0; m < 4; m++) begin
            cpol = m[1];
            cpha = m[0];
            @(posedge clk);
            run_transfer(8'h00, 8'hFF);
            run_transfer(8'hFF, 8'h00);
            run_transfer(8'hA5, 8'h5A);
            run_transfer(8'h01, 8'h80);
        end

        // ---- Randomized transfers across random modes ----
        for (int i = 0; i < 20; i++) begin
            cpol = $urandom_range(0, 1);
            cpha = $urandom_range(0, 1);
            @(posedge clk);
            run_transfer($urandom_range(0, 255), $urandom_range(0, 255));
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
