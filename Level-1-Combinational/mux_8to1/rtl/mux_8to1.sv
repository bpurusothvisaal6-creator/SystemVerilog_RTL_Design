//=============================================================================
// Module      : mux_8to1
// Description : 8-to-1 Multiplexer
// Author      : B. Purusoth Visaal
// Language    : SystemVerilog
//=============================================================================

module mux_8to1 (

    input  logic [7:0] d,
    input  logic [2:0] sel,
    output logic       y

);

    // Combinational Logic
    always_comb begin
        case (sel)
            3'b000: y = d[0];
            3'b001: y = d[1];
            3'b010: y = d[2];
            3'b011: y = d[3];
            3'b100: y = d[4];
            3'b101: y = d[5];
            3'b110: y = d[6];
            3'b111: y = d[7];
            default: y = 1'b0;
        endcase
    end

endmodule