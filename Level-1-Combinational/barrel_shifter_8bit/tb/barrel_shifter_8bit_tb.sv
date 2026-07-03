//=============================================================================
// Module      : barrel_shifter_8bit_tb
// Description : Self-checking Testbench for 8-bit Barrel Shifter
// Author      : B. Purusoth Visaal
// Language    : SystemVerilog
//=============================================================================

module barrel_shifter_8bit_tb;

    logic [7:0] data_in;
    logic [2:0] shift_amt;
    logic       dir;

    logic [7:0] data_out;
    logic [7:0] expected;

    integer pass_count;
    integer fail_count;

    // DUT
    barrel_shifter_8bit dut (

        .data_in(data_in),
        .shift_amt(shift_amt),
        .dir(dir),
        .data_out(data_out)

    );

    initial begin

        pass_count = 0;
        fail_count = 0;

        $display("==============================================");
        $display("      8-bit Barrel Shifter Test Started");
        $display("==============================================");

        // Test every possible input
        for (int i = 0; i < 256; i++) begin

            for (int s = 0; s < 8; s++) begin

                // LEFT SHIFT
                data_in   = i;
                shift_amt = s;
                dir       = 1'b0;

                #10;

                expected = data_in << shift_amt;

                if (data_out == expected)
                    pass_count++;
                else begin
                    fail_count++;

                    $display("--------------------------------------");
                    $display("FAIL (LEFT SHIFT)");
                    $display("Input      = %b", data_in);
                    $display("Shift Amt  = %0d", shift_amt);
                    $display("Expected   = %b", expected);
                    $display("Got        = %b", data_out);
                    $display("--------------------------------------");
                end

                // RIGHT SHIFT
                dir = 1'b1;

                #10;

                expected = data_in >> shift_amt;

                if (data_out == expected)
                    pass_count++;
                else begin
                    fail_count++;

                    $display("--------------------------------------");
                    $display("FAIL (RIGHT SHIFT)");
                    $display("Input      = %b", data_in);
                    $display("Shift Amt  = %0d", shift_amt);
                    $display("Expected   = %b", expected);
                    $display("Got        = %b", data_out);
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