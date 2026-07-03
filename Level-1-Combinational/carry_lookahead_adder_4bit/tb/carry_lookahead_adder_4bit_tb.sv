//=============================================================================
// Module      : carry_lookahead_adder_4bit_tb
// Description : Self-checking Testbench for 4-bit Carry Lookahead Adder
// Author      : B. Purusoth Visaal
// Language    : SystemVerilog
//=============================================================================

module carry_lookahead_adder_4bit_tb;

    logic [3:0] a;
    logic [3:0] b;
    logic       cin;

    logic [3:0] sum;
    logic       cout;

    logic [4:0] expected;

    integer pass_count;
    integer fail_count;

    // DUT
    carry_lookahead_adder_4bit dut (
        .a(a),
        .b(b),
        .cin(cin),
        .sum(sum),
        .cout(cout)
    );

    initial begin

        pass_count = 0;
        fail_count = 0;

        $display("==============================================");
        $display(" 4-bit Carry Lookahead Adder Test Started");
        $display("==============================================");

        // Test every possible input combination
        for (int i = 0; i < 16; i++) begin
            for (int j = 0; j < 16; j++) begin
                for (int k = 0; k < 2; k++) begin

                    a   = i;
                    b   = j;
                    cin = k;

                    #10;

                    expected = a + b + cin;

                    if ({cout, sum} == expected) begin
                        pass_count++;
                    end
                    else begin
                        fail_count++;

                        $display("----------------------------------------------");
                        $display("FAIL");
                        $display("A        = %d", a);
                        $display("B        = %d", b);
                        $display("Cin      = %b", cin);
                        $display("Expected = %b", expected);
                        $display("Got      = %b", {cout, sum});
                        $display("----------------------------------------------");
                    end

                end
            end
        end

        $display("==============================================");
        $display("Simulation Completed");
        $display("PASS = %0d", pass_count);
        $display("FAIL = %0d", fail_count);
        $display("==============================================");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;

    end

endmodule