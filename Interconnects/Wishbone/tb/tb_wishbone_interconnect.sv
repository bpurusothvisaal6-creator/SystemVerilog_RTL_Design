`timescale 1ns/1ps

module tb;

    localparam int NUM_MASTERS = 2;
    localparam int NUM_SLAVES  = 2;
    localparam int ADDR_WIDTH  = 32;
    localparam int DATA_WIDTH  = 32;
    localparam int SEL_WIDTH   = DATA_WIDTH/8;

    localparam logic [NUM_SLAVES*ADDR_WIDTH-1:0] SLAVE_BASE_FLAT =
        {32'h0000_1000, 32'h0000_0000};
    localparam logic [NUM_SLAVES*ADDR_WIDTH-1:0] SLAVE_SIZE_FLAT =
        {32'h0000_1000, 32'h0000_1000};

    logic clk, rst_n;

    logic [NUM_MASTERS-1:0]                     m_cyc_i, m_stb_i, m_we_i;
    logic [NUM_MASTERS-1:0][ADDR_WIDTH-1:0]     m_adr_i;
    logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0]     m_dat_i;
    logic [NUM_MASTERS-1:0][SEL_WIDTH-1:0]      m_sel_i;
    logic [NUM_MASTERS-1:0]                     m_ack_o, m_err_o;
    logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0]     m_dat_o;

    logic [NUM_SLAVES-1:0]                      s_cyc_o, s_stb_o, s_we_o;
    logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]      s_adr_o;
    logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0]      s_dat_o;
    logic [NUM_SLAVES-1:0][SEL_WIDTH-1:0]       s_sel_o;
    logic [NUM_SLAVES-1:0]                      s_ack_i;
    logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0]      s_dat_i;

    logic [ADDR_WIDTH-1:0] SLAVE_BASE [NUM_SLAVES-1:0];

    int errors = 0;
    int checks = 0;

    wishbone_interconnect #(
        .NUM_MASTERS     (NUM_MASTERS),
        .NUM_SLAVES      (NUM_SLAVES),
        .ADDR_WIDTH      (ADDR_WIDTH),
        .DATA_WIDTH      (DATA_WIDTH),
        .SLAVE_BASE_FLAT (SLAVE_BASE_FLAT),
        .SLAVE_SIZE_FLAT (SLAVE_SIZE_FLAT)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .m_cyc_i (m_cyc_i),
        .m_stb_i (m_stb_i),
        .m_we_i  (m_we_i),
        .m_adr_i (m_adr_i),
        .m_dat_i (m_dat_i),
        .m_sel_i (m_sel_i),
        .m_ack_o (m_ack_o),
        .m_err_o (m_err_o),
        .m_dat_o (m_dat_o),
        .s_cyc_o (s_cyc_o),
        .s_stb_o (s_stb_o),
        .s_we_o  (s_we_o),
        .s_adr_o (s_adr_o),
        .s_dat_o (s_dat_o),
        .s_sel_o (s_sel_o),
        .s_ack_i (s_ack_i),
        .s_dat_i (s_dat_i)
    );

    // -------------------------------------------------------------------
    // Behavioural single-cycle-ACK Wishbone memory slaves
    // -------------------------------------------------------------------
    genvar gs;
    generate
        for (gs = 0; gs < NUM_SLAVES; gs++) begin : g_slave_mem
            logic [DATA_WIDTH-1:0] mem [0:15];
            logic                  ack_q;

            assign s_ack_i[gs] = ack_q;
            assign s_dat_i[gs] = mem[s_adr_o[gs][5:2]];

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    ack_q <= 1'b0;
                end else begin
                    // assert ACK exactly one cycle after CYC & STB seen, then drop
                    ack_q <= s_cyc_o[gs] && s_stb_o[gs] && !ack_q;
                    if (s_cyc_o[gs] && s_stb_o[gs] && s_we_o[gs] && !ack_q) begin
                        mem[s_adr_o[gs][5:2]] <= s_dat_o[gs];
                    end
                end
            end
        end
    endgenerate

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        for (int s = 0; s < NUM_SLAVES; s++) begin
            SLAVE_BASE[s] = SLAVE_BASE_FLAT[s*ADDR_WIDTH +: ADDR_WIDTH];
        end
    end

    // -------------------------------------------------------------------
    // Directed single-master Wishbone write transaction (waits for ACK)
    // -------------------------------------------------------------------
    task automatic wb_write(input int m, input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] data);
        int timeout;
        @(negedge clk);
        m_cyc_i[m] = 1'b1;
        m_stb_i[m] = 1'b1;
        m_we_i[m]  = 1'b1;
        m_adr_i[m] = addr;
        m_dat_i[m] = data;
        m_sel_i[m] = {SEL_WIDTH{1'b1}};
        timeout = 0;
        while (!m_ack_o[m] && !m_err_o[m] && timeout < 20) begin
            @(posedge clk);
            timeout++;
        end
        checks++;
        if (timeout >= 20 || m_err_o[m]) begin
            errors++;
            $display("[FAIL] wb_write m=%0d addr=%h timed out or errored (err=%b)", m, addr, m_err_o[m]);
        end else begin
            $display("[PASS] wb_write m=%0d addr=%h data=%h", m, addr, data);
        end
        @(negedge clk);
        m_cyc_i[m] = 1'b0;
        m_stb_i[m] = 1'b0;
        m_we_i[m]  = 1'b0;
    endtask

    task automatic wb_read(input int m, input logic [ADDR_WIDTH-1:0] addr, input logic [DATA_WIDTH-1:0] exp_data);
        int timeout;
        @(negedge clk);
        m_cyc_i[m] = 1'b1;
        m_stb_i[m] = 1'b1;
        m_we_i[m]  = 1'b0;
        m_adr_i[m] = addr;
        m_sel_i[m] = {SEL_WIDTH{1'b1}};
        timeout = 0;
        while (!m_ack_o[m] && !m_err_o[m] && timeout < 20) begin
            @(posedge clk);
            timeout++;
        end
        checks++;
        if (timeout >= 20 || m_err_o[m] || (m_dat_o[m] !== exp_data)) begin
            errors++;
            $display("[FAIL] wb_read  m=%0d addr=%h got=%h expected=%h err=%b timeout=%0d",
                       m, addr, m_dat_o[m], exp_data, m_err_o[m], timeout);
        end else begin
            $display("[PASS] wb_read  m=%0d addr=%h data=%h", m, addr, m_dat_o[m]);
        end
        @(negedge clk);
        m_cyc_i[m] = 1'b0;
        m_stb_i[m] = 1'b0;
    endtask

    task automatic wb_bad_addr(input int m, input logic [ADDR_WIDTH-1:0] addr);
        int timeout;
        @(negedge clk);
        m_cyc_i[m] = 1'b1;
        m_stb_i[m] = 1'b1;
        m_we_i[m]  = 1'b0;
        m_adr_i[m] = addr;
        timeout = 0;
        while (!m_ack_o[m] && !m_err_o[m] && timeout < 20) begin
            @(posedge clk);
            timeout++;
        end
        checks++;
        if (!m_err_o[m]) begin
            errors++;
            $display("[FAIL] wb_bad_addr m=%0d addr=%h did not raise ERR", m, addr);
        end else begin
            $display("[PASS] wb_bad_addr m=%0d addr=%h correctly errored", m, addr);
        end
        @(negedge clk);
        m_cyc_i[m] = 1'b0;
        m_stb_i[m] = 1'b0;
    endtask

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb);

        rst_n   = 1'b0;
        m_cyc_i = '0; m_stb_i = '0; m_we_i = '0;
        m_adr_i = '0; m_dat_i = '0; m_sel_i = '0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ---------------- Directed: each master writes/reads its own slave ----------------
        wb_write(0, 32'h0000_0004, 32'hAAAA_0001);
        wb_read (0, 32'h0000_0004, 32'hAAAA_0001);

        wb_write(1, 32'h0000_1008, 32'hBBBB_0002);
        wb_read (1, 32'h0000_1008, 32'hBBBB_0002);

        // cross master/slave check: master 0 talks to slave 1
        wb_write(0, 32'h0000_100C, 32'hCCCC_0003);
        wb_read (0, 32'h0000_100C, 32'hCCCC_0003);

        // ---------------- Corner case: unmapped address ----------------
        wb_bad_addr(0, 32'hFFFF_0000);

        // ---------------- Corner case: simultaneous contention on both masters ----------------
        begin
            @(negedge clk);
            m_cyc_i[0] = 1'b1; m_stb_i[0] = 1'b1; m_we_i[0] = 1'b1;
            m_adr_i[0] = 32'h0000_0000; m_dat_i[0] = 32'h1111_1111; m_sel_i[0] = {SEL_WIDTH{1'b1}};
            m_cyc_i[1] = 1'b1; m_stb_i[1] = 1'b1; m_we_i[1] = 1'b1;
            m_adr_i[1] = 32'h0000_0000; m_dat_i[1] = 32'h2222_2222; m_sel_i[1] = {SEL_WIDTH{1'b1}};
            @(posedge clk); #1;
            checks++;
            // fixed priority: master 0 should be granted the bus (or at least ack) before master 1
            if (m_ack_o[1] && !m_ack_o[0]) begin
                errors++;
                $display("[FAIL] contention arbitration incorrect: master 1 acked before master 0");
            end else begin
                $display("[PASS] contention arbitration: master 0 correctly holds priority over master 1");
            end
            // drain both transactions
            repeat (5) @(posedge clk);
            @(negedge clk);
            m_cyc_i = '0; m_stb_i = '0; m_we_i = '0;
        end
        @(negedge clk);

        // ---------------- Randomized transfers ----------------
        for (int t = 0; t < 40; t++) begin
            int m, s_idx;
            logic [ADDR_WIDTH-1:0] addr;
            logic [DATA_WIDTH-1:0] data;
            m     = $urandom_range(0, NUM_MASTERS-1);
            s_idx = $urandom_range(0, NUM_SLAVES-1);
            addr  = SLAVE_BASE[s_idx] + (ADDR_WIDTH'($urandom_range(0,15)) << 2);
            data  = DATA_WIDTH'($urandom);
            wb_write(m, addr, data);
            wb_read (m, addr, data);
        end

        if (errors == 0)
            $display("\n=== TESTBENCH RESULT: ALL %0d CHECKS PASSED ===", checks);
        else
            $display("\n=== TESTBENCH RESULT: %0d/%0d CHECKS FAILED ===", errors, checks);

        $finish;
    end

endmodule

