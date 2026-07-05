//=============================================================================
// Module      : carry_select_adder_4bit
// Description : 4-bit Carry Select Adder
// Author      : B. Purusoth Visaal
//=============================================================================

module carry_select_adder_4bit(

    input  logic [3:0] a,
    input  logic [3:0] b,
    input  logic       cin,

    output logic [3:0] sum,
    output logic       cout

);

logic [3:0] sum0;
logic [3:0] sum1;

logic cout0;
logic cout1;

// Ripple Adder assuming Cin = 0
ripple_carry_adder_4bit RCA0(

    .a(a),
    .b(b),
    .cin(1'b0),

    .sum(sum0),
    .cout(cout0)

);

// Ripple Adder assuming Cin = 1
ripple_carry_adder_4bit RCA1(

    .a(a),
    .b(b),
    .cin(1'b1),

    .sum(sum1),
    .cout(cout1)

);

// Select correct outputs
assign sum  = (cin) ? sum1  : sum0;
assign cout = (cin) ? cout1 : cout0;

endmodule