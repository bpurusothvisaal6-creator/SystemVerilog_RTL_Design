//=============================================================================
// Module      : carry_lookahead_adder_4bit
// Description : 4-bit Carry Lookahead Adder
// Author      : B. Purusoth Visaal
// Language    : SystemVerilog
//=============================================================================

module carry_lookahead_adder_4bit (

    input  logic [3:0] a,
    input  logic [3:0] b,
    input  logic       cin,

    output logic [3:0] sum,
    output logic       cout

);

    logic [3:0] p;
    logic [3:0] g;

    logic c1, c2, c3;

    always_comb begin

        // Generate and Propagate
        p = a ^ b;
        g = a & b;

        // Carry Lookahead Logic
        c1 = g[0] | (p[0] & cin);

        c2 = g[1]
           | (p[1] & g[0])
           | (p[1] & p[0] & cin);

        c3 = g[2]
           | (p[2] & g[1])
           | (p[2] & p[1] & g[0])
           | (p[2] & p[1] & p[0] & cin);

        cout = g[3]
             | (p[3] & g[2])
             | (p[3] & p[2] & g[1])
             | (p[3] & p[2] & p[1] & g[0])
             | (p[3] & p[2] & p[1] & p[0] & cin);

        // Sum
        sum[0] = p[0] ^ cin;
        sum[1] = p[1] ^ c1;
        sum[2] = p[2] ^ c2;
        sum[3] = p[3] ^ c3;

    end

endmodule