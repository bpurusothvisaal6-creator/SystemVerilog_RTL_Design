//=============================================================================
// Module      : carry_select_adder_4bit_tb
// Description : Self-checking Testbench for 4-bit Carry Select Adder
// Author      : B. Purusoth Visaal
//=============================================================================

module carry_select_adder_4bit_tb;

    // Testbench Signals
    logic [3:0] a;
    logic [3:0] b;
    logic       cin;

    logic [3:0] sum;
    logic       cout;

    logic [4:0] expected;

    integer pass_count;
    integer fail_count;

    //=========================================================================
    // DUT
    //=========================================================================

    carry_select_adder_4bit dut (
        .a(a),
        .b(b),
        .cin(cin),
        .sum(sum),
        .cout(cout)
    );

    //=========================================================================
    // Test
    //=========================================================================

    initial begin

        pass_count = 0;
        fail_count = 0;

        $display("======================================================");
        $display("     Carry Select Adder (4-bit) Test Started");
        $display("======================================================");

        // Test all possible combinations
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
                        $display("A        = %0d", a);
                        $display("B        = %0d", b);
                        $display("Cin      = %0d", cin);
                        $display("Expected = %05b", expected);
                        $display("Got      = %05b", {cout, sum});
                        $display("----------------------------------------------");

                    end

                end
            end
        end

        $display("======================================================");
        $display("Simulation Completed");
        $display("PASS = %0d", pass_count);
        $display("FAIL = %0d", fail_count);
        $display("======================================================");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;

    end

endmodule