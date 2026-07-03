//=============================================================================
// Module      : priority_encoder_8to3
// Description : 8-to-3 Priority Encoder
// Author      : B. Purusoth Visaal
// Language    : SystemVerilog
//=============================================================================

module priority_encoder_8to3 (

    input  logic [7:0] in,
    output logic [2:0] out,
    output logic       valid

);

    always_comb begin

        // Default outputs
        out   = 3'b000;
        valid = 1'b0;

        // Highest priority = in[7]
        if      (in[7]) begin
            out   = 3'b111;
            valid = 1'b1;
        end
        else if (in[6]) begin
            out   = 3'b110;
            valid = 1'b1;
        end
        else if (in[5]) begin
            out   = 3'b101;
            valid = 1'b1;
        end
        else if (in[4]) begin
            out   = 3'b100;
            valid = 1'b1;
        end
        else if (in[3]) begin
            out   = 3'b011;
            valid = 1'b1;
        end
        else if (in[2]) begin
            out   = 3'b010;
            valid = 1'b1;
        end
        else if (in[1]) begin
            out   = 3'b001;
            valid = 1'b1;
        end
        else if (in[0]) begin
            out   = 3'b000;
            valid = 1'b1;
        end

    end

endmodule