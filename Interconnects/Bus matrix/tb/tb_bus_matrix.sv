`timescale 1ns/1ps

module tb;

    localparam int NUM_MASTERS = 4;
    localparam int NUM_SLAVES  = 4;
    localparam int ADDR_WIDTH  = 32;
    localparam int DATA_WIDTH  = 32;

    // per-slave base addresses / sizes kept as plain arrays for testbench
    // readability; flattened versions below are what get passed to the DUT
    logic [ADDR_WIDTH-1:0] SLAVE_BASE [NUM_SLAVES-1:0];
    logic [ADDR_WIDTH-1:0] SLAVE_SIZE [NUM_SLAVES-1:0];

    localparam logic [NUM_SLAVES*ADDR_WIDTH-1:0] SLAVE_BASE_FLAT =
        {32'h0000_3000, 32'h0000_2000, 32'h0000_1000, 32'h0000_0000};
    localparam logic [NUM_SLAVES*ADDR_WIDTH-1:0] SLAVE_SIZE_FLAT =
        {32'h0000_1000, 32'h0000_1000, 32'h0000_1000, 32'h0000_1000};

    logic clk, rst_n;

    logic [NUM_MASTERS-1:0]                  m_valid, m_write, m_ready, m_error;
    logic [NUM_MASTERS-1:0][ADDR_WIDTH-1:0]  m_addr;
    logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0]  m_wdata, m_rdata;

    logic [NUM_SLAVES-1:0]                   s_valid, s_write, s_ready;
    logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]   s_addr;
    logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0]   s_wdata, s_rdata;

    int errors = 0;
    int checks = 0;

    bus_matrix #(
        .NUM_MASTERS (NUM_MASTERS),
        .NUM_SLAVES  (NUM_SLAVES),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .SLAVE_BASE_FLAT (SLAVE_BASE_FLAT),
        .SLAVE_SIZE_FLAT (SLAVE_SIZE_FLAT)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .m_valid (m_valid),
        .m_write (m_write),
        .m_addr  (m_addr),
        .m_wdata (m_wdata),
        .m_ready (m_ready),
        .m_error (m_error),
        .m_rdata (m_rdata),
        .s_valid (s_valid),
        .s_write (s_write),
        .s_addr  (s_addr),
        .s_wdata (s_wdata),
        .s_ready (s_ready),
        .s_rdata (s_rdata)
    );

    // -------------------------------------------------------------------
    // Behavioural memory slaves: always ready, single-cycle combinational
    // read/write against a small local array.
    // -------------------------------------------------------------------
    genvar gs;
    generate
        for (gs = 0; gs < NUM_SLAVES; gs++) begin : g_slave_mem
            logic [DATA_WIDTH-1:0] mem [0:15];
            assign s_ready[gs] = 1'b1;
            assign s_rdata[gs] = mem[s_addr[gs][5:2]];
            always_ff @(posedge clk) begin
                if (s_valid[gs] && s_write[gs]) begin
                    mem[s_addr[gs][5:2]] <= s_wdata[gs];
                end
            end
        end
    endgenerate

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // unpack flattened parameters into plain arrays for easy use in stimulus
    initial begin
        for (int s = 0; s < NUM_SLAVES; s++) begin
            SLAVE_BASE[s] = SLAVE_BASE_FLAT[s*ADDR_WIDTH +: ADDR_WIDTH];
            SLAVE_SIZE[s] = SLAVE_SIZE_FLAT[s*ADDR_WIDTH +: ADDR_WIDTH];
        end
    end

    // -------------------------------------------------------------------
    // Single-master directed write-then-read transaction with checking
    // -------------------------------------------------------------------
    task automatic do_write(input int m, input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] data);
        m_valid[m] = 1'b1;
        m_write[m] = 1'b1;
        m_addr[m]  = addr;
        m_wdata[m] = data;
        @(posedge clk);
        #1;
        checks++;
        if (!m_ready[m] || m_error[m]) begin
            errors++;
            $display("[FAIL] write m=%0d addr=%h did not complete cleanly (ready=%b error=%b)", m, addr, m_ready[m], m_error[m]);
        end else begin
            $display("[PASS] write m=%0d addr=%h data=%h", m, addr, data);
        end
        m_valid[m] = 1'b0;
        m_write[m] = 1'b0;
        @(posedge clk);
    endtask

    task automatic do_read(input int m, input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] exp_data);
        m_valid[m] = 1'b1;
        m_write[m] = 1'b0;
        m_addr[m]  = addr;
        @(posedge clk);
        #1;
        checks++;
        if (!m_ready[m] || m_error[m] || (m_rdata[m] !== exp_data)) begin
            errors++;
            $display("[FAIL] read  m=%0d addr=%h got=%h expected=%h ready=%b error=%b",
                       m, addr, m_rdata[m], exp_data, m_ready[m], m_error[m]);
        end else begin
            $display("[PASS] read  m=%0d addr=%h data=%h", m, addr, m_rdata[m]);
        end
        m_valid[m] = 1'b0;
        @(posedge clk);
    endtask

    task automatic do_bad_addr(input int m, input logic [ADDR_WIDTH-1:0] addr);
        m_valid[m] = 1'b1;
        m_write[m] = 1'b0;
        m_addr[m]  = addr;
        @(posedge clk);
        #1;
        checks++;
        if (!m_error[m] || !m_ready[m]) begin
            errors++;
            $display("[FAIL] unmapped addr m=%0d addr=%h did not raise error (error=%b ready=%b)", m, addr, m_error[m], m_ready[m]);
        end else begin
            $display("[PASS] unmapped addr m=%0d addr=%h correctly errored", m, addr);
        end
        m_valid[m] = 1'b0;
        @(posedge clk);
    endtask

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb);

        rst_n   = 1'b0;
        m_valid = '0; m_write = '0; m_addr = '0; m_wdata = '0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ---------------- Directed: each master writes/reads its own slave ----------------
        do_write(0, 32'h0000_0004, 32'hAAAA_0001);
        do_read (0, 32'h0000_0004, 32'hAAAA_0001);

        do_write(1, 32'h0000_1008, 32'hBBBB_0002);
        do_read (1, 32'h0000_1008, 32'hBBBB_0002);

        do_write(2, 32'h0000_200C, 32'hCCCC_0003);
        do_read (2, 32'h0000_200C, 32'hCCCC_0003);

        do_write(3, 32'h0000_3000, 32'hDDDD_0004);
        do_read (3, 32'h0000_3000, 32'hDDDD_0004);

        // ---------------- Corner case: unmapped address ----------------
        do_bad_addr(0, 32'hFFFF_0000);

        // ---------------- Corner case: simultaneous independent transfers ----------------
        // all 4 masters write to their respective (distinct) slaves at once
        m_valid = '0; m_write = '0;
        for (int m = 0; m < NUM_MASTERS; m++) begin
            m_valid[m] = 1'b1;
            m_write[m] = 1'b1;
            m_addr[m]  = SLAVE_BASE[m] + 32'h10;
            m_wdata[m] = 32'hE000_0000 + m;
        end
        @(posedge clk);
        #1;
        checks++;
        if (!(&m_ready) || (|m_error)) begin
            errors++;
            $display("[FAIL] simultaneous independent transfers did not all complete: ready=%b error=%b", m_ready, m_error);
        end else begin
            $display("[PASS] simultaneous independent transfers to distinct slaves completed together");
        end
        m_valid = '0; m_write = '0;
        @(posedge clk);

        // verify data landed correctly
        for (int m = 0; m < NUM_MASTERS; m++) begin
            do_read(m, SLAVE_BASE[m] + 32'h10, 32'hE000_0000 + m);
        end

        // ---------------- Corner case: contention - two masters target same slave ----------------
        m_valid = '0; m_write = '0;
        m_valid[0] = 1'b1; m_write[0] = 1'b1; m_addr[0] = 32'h0000_0000; m_wdata[0] = 32'h1111_1111;
        m_valid[1] = 1'b1; m_write[1] = 1'b1; m_addr[1] = 32'h0000_0000; m_wdata[1] = 32'h2222_2222;
        @(posedge clk);
        #1;
        checks++;
        // fixed priority: master 0 should win, master 1 must not be granted (m_ready deasserted)
        if (!m_ready[0] || m_ready[1]) begin
            errors++;
            $display("[FAIL] contention arbitration incorrect: m_ready=%b (expected m0=1,m1=0)", m_ready);
        end else begin
            $display("[PASS] contention arbitration: master 0 correctly won priority over master 1");
        end
        m_valid = '0; m_write = '0;
        @(posedge clk);

        // ---------------- Randomized transfers ----------------
        for (int t = 0; t < 60; t++) begin
            int m;
            int s_idx;
            logic [ADDR_WIDTH-1:0] addr;
            logic [DATA_WIDTH-1:0] data;
            m     = $urandom_range(0, NUM_MASTERS-1);
            s_idx = $urandom_range(0, NUM_SLAVES-1);
            addr  = SLAVE_BASE[s_idx] + (ADDR_WIDTH'($urandom_range(0,15)) << 2);
            data  = DATA_WIDTH'($urandom);
            do_write(m, addr, data);
            do_read (m, addr, data);
        end

        if (errors == 0)
            $display("\n=== TESTBENCH RESULT: ALL %0d CHECKS PASSED ===", checks);
        else
            $display("\n=== TESTBENCH RESULT: %0d/%0d CHECKS FAILED ===", errors, checks);

        $finish;
    end

endmodule
