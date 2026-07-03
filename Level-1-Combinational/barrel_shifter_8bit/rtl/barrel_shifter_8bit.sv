//=============================================================================
// Module      : barrel_shifter_8bit
// Description : 8-bit Barrel Shifter (Left/Right)
// Author      : B. Purusoth Visaal
// Language    : SystemVerilog
//=============================================================================

module barrel_shifter_8bit (

    input  logic [7:0] data_in,
    input  logic [2:0] shift_amt,
    input  logic       dir,

    output logic [7:0] data_out

);

    always_comb begin

        case (dir)

            // Left Shift
            1'b0:
                data_out = data_in << shift_amt;

            // Right Shift
            1'b1:
                data_out = data_in >> shift_amt;

            default:
                data_out = 8'b00000000;

        endcase

    end

endmodule