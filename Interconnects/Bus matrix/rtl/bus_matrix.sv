module bus_matrix #(
    parameter int NUM_MASTERS = 4,
    parameter int NUM_SLAVES  = 4,
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    // flattened address map: slave i occupies bits [(i+1)*ADDR_WIDTH-1 : i*ADDR_WIDTH]
    parameter logic [NUM_SLAVES*ADDR_WIDTH-1:0] SLAVE_BASE_FLAT =
        {32'h0000_3000, 32'h0000_2000, 32'h0000_1000, 32'h0000_0000},
    parameter logic [NUM_SLAVES*ADDR_WIDTH-1:0] SLAVE_SIZE_FLAT =
        {32'h0000_1000, 32'h0000_1000, 32'h0000_1000, 32'h0000_1000}
) (
    input  logic                                    clk,
    input  logic                                    rst_n,

    // ------------------------- Master side -------------------------
    input  logic [NUM_MASTERS-1:0]                  m_valid,   // transfer request
    input  logic [NUM_MASTERS-1:0]                  m_write,   // 1 = write, 0 = read
    input  logic [NUM_MASTERS-1:0][ADDR_WIDTH-1:0]  m_addr,
    input  logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0]  m_wdata,
    output logic [NUM_MASTERS-1:0]                  m_ready,   // transfer accepted this cycle
    output logic [NUM_MASTERS-1:0]                  m_error,   // address decode miss
    output logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0]  m_rdata,

    // ------------------------- Slave side -------------------------
    output logic [NUM_SLAVES-1:0]                   s_valid,
    output logic [NUM_SLAVES-1:0]                   s_write,
    output logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]   s_addr,
    output logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0]   s_wdata,
    input  logic [NUM_SLAVES-1:0]                   s_ready,
    input  logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0]   s_rdata
);

    localparam int MST_BITS = (NUM_MASTERS > 1) ? $clog2(NUM_MASTERS) : 1;
    localparam int SLV_BITS = (NUM_SLAVES  > 1) ? $clog2(NUM_SLAVES)  : 1;

    // unpack the flattened address map into per-slave arrays for readability
    logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0] slave_base;
    logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0] slave_size;

    always_comb begin
        for (int s = 0; s < NUM_SLAVES; s++) begin
            slave_base[s] = SLAVE_BASE_FLAT[s*ADDR_WIDTH +: ADDR_WIDTH];
            slave_size[s] = SLAVE_SIZE_FLAT[s*ADDR_WIDTH +: ADDR_WIDTH];
        end
    end

    // -----------------------------------------------------------------
    // Address decode: for every master, determine which slave (if any)
    // its address falls within, and whether the decode hit.
    // -----------------------------------------------------------------
    logic [NUM_MASTERS-1:0]                m_decode_hit;
    logic [NUM_MASTERS-1:0][SLV_BITS-1:0]  m_decode_sel;

    always_comb begin
        for (int m = 0; m < NUM_MASTERS; m++) begin
            logic found;
            found           = 1'b0;
            m_decode_hit[m] = 1'b0;
            m_decode_sel[m] = '0;
            for (int s = 0; s < NUM_SLAVES; s++) begin
                if (!found &&
                    (m_addr[m] >= slave_base[s]) &&
                    (m_addr[m] <  slave_base[s] + slave_size[s])) begin
                    m_decode_hit[m] = 1'b1;
                    m_decode_sel[m] = SLV_BITS'(s);
                    found           = 1'b1;
                end
            end
        end
    end

    // request matrix: req_matrix[s][m] = master m wants slave s and decode hit
    logic [NUM_MASTERS-1:0] req_matrix [NUM_SLAVES-1:0];

    always_comb begin
        for (int s = 0; s < NUM_SLAVES; s++) begin
            for (int m = 0; m < NUM_MASTERS; m++) begin
                req_matrix[s][m] = m_valid[m] && m_decode_hit[m] &&
                                    (int'(m_decode_sel[m]) == s);
            end
        end
    end

    // per-slave winner (fixed priority: lowest master index)
    logic [NUM_MASTERS-1:0] grant_matrix [NUM_SLAVES-1:0];

    always_comb begin
        for (int s = 0; s < NUM_SLAVES; s++) begin
            logic found;
            found = 1'b0;
            grant_matrix[s] = '0;
            for (int m = 0; m < NUM_MASTERS; m++) begin
                if (req_matrix[s][m] && !found) begin
                    grant_matrix[s][m] = 1'b1;
                    found               = 1'b1;
                end
            end
        end
    end

    // -----------------------------------------------------------------
    // Drive slave outputs based on the winning master for each slave
    // -----------------------------------------------------------------
    always_comb begin
        for (int s = 0; s < NUM_SLAVES; s++) begin
            s_valid[s] = |grant_matrix[s];
            s_write[s] = 1'b0;
            s_addr[s]  = '0;
            s_wdata[s] = '0;
            for (int m = 0; m < NUM_MASTERS; m++) begin
                if (grant_matrix[s][m]) begin
                    s_write[s] = m_write[m];
                    s_addr[s]  = m_addr[m];
                    s_wdata[s] = m_wdata[m];
                end
            end
        end
    end

    // -----------------------------------------------------------------
    // Route slave responses back to the winning master; masters whose
    // decode missed get an immediate error response (no wait).
    // -----------------------------------------------------------------
    always_comb begin
        for (int m = 0; m < NUM_MASTERS; m++) begin
            int sel_s;
            m_ready[m] = 1'b0;
            m_error[m] = 1'b0;
            m_rdata[m] = '0;
            sel_s      = int'(m_decode_sel[m]);
            if (m_valid[m] && !m_decode_hit[m]) begin
                // unmapped address -> immediate error, no slave contacted
                m_error[m] = 1'b1;
                m_ready[m] = 1'b1;
            end else if (m_valid[m] && m_decode_hit[m]) begin
                if (grant_matrix[sel_s][m]) begin
                    m_ready[m] = s_ready[sel_s];
                    m_rdata[m] = s_rdata[sel_s];
                end
            end
        end
    end

endmodule

