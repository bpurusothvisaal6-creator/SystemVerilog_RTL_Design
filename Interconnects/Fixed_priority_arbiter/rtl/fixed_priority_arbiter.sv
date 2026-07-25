module fixed_priority_arbiter #(
    parameter int NUM_REQ = 8   // number of requesters
) (
    input  logic [NUM_REQ-1:0] req,    // request vector, active high
    output logic [NUM_REQ-1:0] grant   // one-hot grant vector
);

    always_comb begin
        logic found;
        grant = '0;
        found = 1'b0;
        for (int i = 0; i < NUM_REQ; i++) begin
            if (req[i] && !found) begin
                grant[i] = 1'b1;
                found    = 1'b1;
            end
        end
    end

endmodule

