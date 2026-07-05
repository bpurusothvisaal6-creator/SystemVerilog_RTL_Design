//=============================================================================
// Module      : carry_save_adder_4bit_tb
// Description : Self-checking Testbench for 4-bit Carry Save Adder
// Author      : B. Purusoth Visaal
//=============================================================================

module carry_save_adder_4bit_tb;

    logic [3:0] a;
    logic [3:0] b;
    logic [3:0] c;

    logic [3:0] sum;
    logic [4:0] carry;

    integer pass_count;
    integer fail_count;

    logic [5:0] expected;
    logic [5:0] actual;

    //-----------------------------------------------------------------
    // DUT
    //-----------------------------------------------------------------

    carry_save_adder_4bit dut(

        .a(a),
        .b(b),
        .c(c),

        .sum(sum),
        .carry(carry)

    );

    //-----------------------------------------------------------------
    // Test
    //-----------------------------------------------------------------

    initial begin

        pass_count = 0;
        fail_count = 0;

        $display("======================================================");
        $display("        Carry Save Adder Test Started");
        $display("======================================================");

        for(int i=0;i<16;i++) begin

            for(int j=0;j<16;j++) begin

                for(int k=0;k<16;k++) begin

                    a = i;
                    b = j;
                    c = k;

                    #10;

                    expected = a + b + c;

                    // CSA Result = Sum + (Carry << 1)
                    actual = $unsigned({2'b00, sum}) + $unsigned({1'b0, carry});

                    if(actual == expected)

                        pass_count++;

                    else begin

                        fail_count++;

                        $display("--------------------------------------");
                        $display("FAIL");
                        $display("A        = %0d",a);
                        $display("B        = %0d",b);
                        $display("C        = %0d",c);
                        $display("Expected = %0d",expected);
                        $display("Actual   = %0d",actual);
                        $display("--------------------------------------");

                    end

                end

            end

        end

        $display("======================================================");
        $display("Simulation Completed");
        $display("PASS = %0d",pass_count);
        $display("FAIL = %0d",fail_count);
        $display("======================================================");

        if(fail_count==0)

            $display("ALL TESTS PASSED");

        else

            $display("SOME TESTS FAILED");

        $finish;

    end

endmodule