//=============================================================================
// Module      : priority_arbiter_8request
// Description : 8-Request Fixed Priority Arbiter
// Author      : B. Purusoth Visaal
//=============================================================================

module priority_arbiter_8request(

    input  logic [7:0] req,

    output logic [7:0] grant,
    output logic       valid

);

always_comb begin

    grant = 8'b00000000;
    valid = 1'b0;

    if      (req[7]) begin grant = 8'b10000000; valid = 1'b1; end
    else if (req[6]) begin grant = 8'b01000000; valid = 1'b1; end
    else if (req[5]) begin grant = 8'b00100000; valid = 1'b1; end
    else if (req[4]) begin grant = 8'b00010000; valid = 1'b1; end
    else if (req[3]) begin grant = 8'b00001000; valid = 1'b1; end
    else if (req[2]) begin grant = 8'b00000100; valid = 1'b1; end
    else if (req[1]) begin grant = 8'b00000010; valid = 1'b1; end
    else if (req[0]) begin grant = 8'b00000001; valid = 1'b1; end

end

endmodule