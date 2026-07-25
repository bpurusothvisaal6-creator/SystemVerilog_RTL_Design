module wishbone_interconnect #(
    parameter int NUM_MASTERS = 2,
    parameter int NUM_SLAVES  = 2,
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    parameter logic [NUM_SLAVES*ADDR_WIDTH-1:0] SLAVE_BASE_FLAT =
        {32'h0000_1000, 32'h0000_0000},
    parameter logic [NUM_SLAVES*ADDR_WIDTH-1:0] SLAVE_SIZE_FLAT =
        {32'h0000_1000, 32'h0000_1000}
) (
    input  logic                                          clk,
    input  logic                                          rst_n,

    // -------------------- Master (initiator) side --------------------
    input  logic [NUM_MASTERS-1:0]                        m_cyc_i,
    input  logic [NUM_MASTERS-1:0]                        m_stb_i,
    input  logic [NUM_MASTERS-1:0]                        m_we_i,
    input  logic [NUM_MASTERS-1:0][ADDR_WIDTH-1:0]        m_adr_i,
    input  logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0]        m_dat_i,
    input  logic [NUM_MASTERS-1:0][(DATA_WIDTH/8)-1:0]    m_sel_i,
    output logic [NUM_MASTERS-1:0]                        m_ack_o,
    output logic [NUM_MASTERS-1:0]                        m_err_o,
    output logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0]        m_dat_o,

    // -------------------- Slave (target) side --------------------
    output logic [NUM_SLAVES-1:0]                         s_cyc_o,
    output logic [NUM_SLAVES-1:0]                         s_stb_o,
    output logic [NUM_SLAVES-1:0]                         s_we_o,
    output logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]         s_adr_o,
    output logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0]         s_dat_o,
    output logic [NUM_SLAVES-1:0][(DATA_WIDTH/8)-1:0]     s_sel_o,
    input  logic [NUM_SLAVES-1:0]                         s_ack_i,
    input  logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0]         s_dat_i
);

    localparam int SLV_BITS = (NUM_SLAVES > 1) ? $clog2(NUM_SLAVES) : 1;

    // unpack the flattened address map
    logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0] slave_base;
    logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0] slave_size;

    always_comb begin
        for (int s = 0; s < NUM_SLAVES; s++) begin
            slave_base[s] = SLAVE_BASE_FLAT[s*ADDR_WIDTH +: ADDR_WIDTH];
            slave_size[s] = SLAVE_SIZE_FLAT[s*ADDR_WIDTH +: ADDR_WIDTH];
        end
    end

    // -----------------------------------------------------------------
    // Fixed-priority arbitration among masters asserting CYC & STB.
    // -----------------------------------------------------------------
    logic [NUM_MASTERS-1:0] m_req;
    logic [NUM_MASTERS-1:0] m_grant;

    assign m_req = m_cyc_i & m_stb_i;

    always_comb begin
        logic found;
        found   = 1'b0;
        m_grant = '0;
        for (int m = 0; m < NUM_MASTERS; m++) begin
            if (m_req[m] && !found) begin
                m_grant[m] = 1'b1;
                found      = 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------
    // Address decode of the granted master's address
    // -----------------------------------------------------------------
    logic                   decode_hit;
    logic [SLV_BITS-1:0]    decode_sel;
    logic [ADDR_WIDTH-1:0]  gnt_adr;
    logic                   gnt_we;
    logic [DATA_WIDTH-1:0]  gnt_dat;
    logic [(DATA_WIDTH/8)-1:0] gnt_sel;

    always_comb begin
        gnt_adr = '0;
        gnt_we  = 1'b0;
        gnt_dat = '0;
        gnt_sel = '0;
        for (int m = 0; m < NUM_MASTERS; m++) begin
            if (m_grant[m]) begin
                gnt_adr = m_adr_i[m];
                gnt_we  = m_we_i[m];
                gnt_dat = m_dat_i[m];
                gnt_sel = m_sel_i[m];
            end
        end
    end

    always_comb begin
        logic found;
        found      = 1'b0;
        decode_hit = 1'b0;
        decode_sel = '0;
        for (int s = 0; s < NUM_SLAVES; s++) begin
            if (!found &&
                (gnt_adr >= slave_base[s]) &&
                (gnt_adr <  slave_base[s] + slave_size[s])) begin
                decode_hit = 1'b1;
                decode_sel = SLV_BITS'(s);
                found      = 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------
    // Drive slave-side bus: only the decoded slave sees CYC/STB asserted
    // -----------------------------------------------------------------
    always_comb begin
        for (int s = 0; s < NUM_SLAVES; s++) begin
            logic sel_this;
            sel_this   = (|m_grant) && decode_hit && (int'(decode_sel) == s);
            s_cyc_o[s] = sel_this;
            s_stb_o[s] = sel_this;
            s_we_o[s]  = sel_this ? gnt_we  : 1'b0;
            s_adr_o[s] = sel_this ? gnt_adr : '0;
            s_dat_o[s] = sel_this ? gnt_dat : '0;
            s_sel_o[s] = sel_this ? gnt_sel : '0;
        end
    end

    // -----------------------------------------------------------------
    // Route ACK / read-data back to the granted master. Non-granted
    // masters see no ACK (they remain stalled until granted). A CYC
    // asserted with a decode miss returns ERR with an ACK-less handshake.
    // -----------------------------------------------------------------
    always_comb begin
        for (int m = 0; m < NUM_MASTERS; m++) begin
            m_ack_o[m] = 1'b0;
            m_err_o[m] = 1'b0;
            m_dat_o[m] = '0;
            if (m_grant[m]) begin
                if (!decode_hit) begin
                    m_err_o[m] = 1'b1;
                    m_ack_o[m] = 1'b1; // terminate the cycle with an error ack
                end else begin
                    m_ack_o[m] = s_ack_i[decode_sel];
                    m_dat_o[m] = s_dat_i[decode_sel];
                end
            end
        end
    end

endmodule

