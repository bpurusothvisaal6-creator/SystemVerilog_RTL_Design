//=============================================================================
// Module      : comparator_16bit_tb
// Description : Self-checking Testbench for 16-bit Comparator
// Author      : B. Purusoth Visaal
// Language    : SystemVerilog
//=============================================================================

module comparator_16bit_tb;

    logic [15:0] a;
    logic [15:0] b;

    logic equal;
    logic greater;
    logic less;

    integer pass_count;
    integer fail_count;

    // DUT
    comparator_16bit dut (
        .a(a),
        .b(b),
        .equal(equal),
        .greater(greater),
        .less(less)
    );

    initial begin

        pass_count = 0;
        fail_count = 0;

        $display("==============================================");
        $display("      16-bit Comparator Test Started");
        $display("==============================================");

        // Test all combinations from 0 to 255
        for (int i = 0; i < 256; i++) begin
            for (int j = 0; j < 256; j++) begin

                a = i;
                b = j;

                #10;

                if ((a == b && equal && !greater && !less) ||
                    (a >  b && greater && !equal && !less) ||
                    (a <  b && less && !equal && !greater))
                begin
                    pass_count++;
                end
                else begin
                    fail_count++;

                    $display("--------------------------------------");
                    $display("FAIL");
                    $display("A = %0d", a);
                    $display("B = %0d", b);
                    $display("Equal   = %b", equal);
                    $display("Greater = %b", greater);
                    $display("Less    = %b", less);
                    $display("--------------------------------------");
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