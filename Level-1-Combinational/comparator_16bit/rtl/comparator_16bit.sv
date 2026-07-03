//=============================================================================
// Module      : comparator_16bit
// Description : 16-bit Magnitude Comparator
// Author      : B. Purusoth Visaal
// Language    : SystemVerilog
//=============================================================================

module comparator_16bit (

    input  logic [15:0] a,
    input  logic [15:0] b,

    output logic equal,
    output logic greater,
    output logic less

);

    always_comb begin

        // Default outputs
        equal   = 1'b0;
        greater = 1'b0;
        less    = 1'b0;

        if (a == b)
            equal = 1'b1;
        else if (a > b)
            greater = 1'b1;
        else
            less = 1'b1;

    end

endmodule