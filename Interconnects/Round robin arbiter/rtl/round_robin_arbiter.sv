module round_robin_arbiter #(
    parameter int NUM_REQ = 8   // number of requesters
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic [NUM_REQ-1:0]   req,     // request vector, active high
    output logic [NUM_REQ-1:0]   grant    // one-hot grant vector
);

    // One-hot pointer register: indicates the requester with the highest
    // current priority.
    logic [NUM_REQ-1:0] ptr_q;

    // Double-width copies used to linearise the circular priority scan.
    logic [2*NUM_REQ-1:0] req_dbl;
    logic [2*NUM_REQ-1:0] grant_dbl;

    assign req_dbl = {req, req};

    // ---------------------------------------------------------------------
    // Combinational grant generation: starting at the pointer position,
    // scan forward (with wraparound) and grant the first active requester.
    // ---------------------------------------------------------------------
    always_comb begin
        int ptr_idx;
        logic found;

        // decode one-hot pointer to a binary index
        ptr_idx = 0;
        for (int i = 0; i < NUM_REQ; i++) begin
            if (ptr_q[i]) ptr_idx = i;
        end

        grant_dbl = '0;
        found     = 1'b0;
        for (int i = 0; i < NUM_REQ; i++) begin
            if (req_dbl[ptr_idx + i] && !found) begin
                grant_dbl[ptr_idx + i] = 1'b1;
                found                  = 1'b1;
            end
        end
    end

    // fold the double-width grant back down to NUM_REQ bits
    assign grant = grant_dbl[NUM_REQ-1:0] | grant_dbl[2*NUM_REQ-1:NUM_REQ];

    // ---------------------------------------------------------------------
    // Pointer update: on a grant, move the pointer to the requester right
    // after the one just granted, so it gets lowest priority next round.
    // ---------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptr_q <= {{(NUM_REQ-1){1'b0}}, 1'b1}; // point at requester 0 after reset
        end else if (|grant) begin
            int gidx;
            gidx = 0;
            for (int i = 0; i < NUM_REQ; i++) begin
                if (grant[i]) gidx = i;
            end
            ptr_q <= (NUM_REQ)'(1'b1) << ((gidx + 1) % NUM_REQ);
        end
    end 
endmodule
