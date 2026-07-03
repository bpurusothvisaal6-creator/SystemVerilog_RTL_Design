//=============================================================================
// Module      : priority_encoder_8to3_tb
// Description : Testbench for 8-to-3 Priority Encoder
// Author      : B. Purusoth Visaal
// Language    : SystemVerilog
//=============================================================================

module priority_encoder_8to3_tb;

    logic [7:0] in;
    logic [2:0] out;
    logic       valid;

    // DUT Instantiation
    priority_encoder_8to3 dut (
        .in(in),
        .out(out),
        .valid(valid)
    );

    initial begin

        $display("==============================================");
        $display("     8-to-3 Priority Encoder Test Started");
        $display("==============================================");

        // Test 1 : No active input
        in = 8'b00000000;
        #10;
        if (out == 3'b000 && valid == 1'b0)
            $display("PASS : Test 1");
        else
            $display("FAIL : Test 1");

        // Test 2
        in = 8'b00000001;
        #10;
        if (out == 3'b000 && valid)
            $display("PASS : Test 2");
        else
            $display("FAIL : Test 2");

        // Test 3
        in = 8'b00000010;
        #10;
        if (out == 3'b001 && valid)
            $display("PASS : Test 3");
        else
            $display("FAIL : Test 3");

        // Test 4
        in = 8'b00000100;
        #10;
        if (out == 3'b010 && valid)
            $display("PASS : Test 4");
        else
            $display("FAIL : Test 4");

        // Test 5
        in = 8'b00001000;
        #10;
        if (out == 3'b011 && valid)
            $display("PASS : Test 5");
        else
            $display("FAIL : Test 5");

        // Test 6
        in = 8'b00010000;
        #10;
        if (out == 3'b100 && valid)
            $display("PASS : Test 6");
        else
            $display("FAIL : Test 6");

        // Test 7
        in = 8'b00100000;
        #10;
        if (out == 3'b101 && valid)
            $display("PASS : Test 7");
        else
            $display("FAIL : Test 7");

        // Test 8
        in = 8'b01000000;
        #10;
        if (out == 3'b110 && valid)
            $display("PASS : Test 8");
        else
            $display("FAIL : Test 8");

        // Test 9
        in = 8'b10000000;
        #10;
        if (out == 3'b111 && valid)
            $display("PASS : Test 9");
        else
            $display("FAIL : Test 9");

        // Test 10 : Multiple active inputs
        in = 8'b10101010;
        #10;
        if (out == 3'b111 && valid)
            $display("PASS : Test 10 (Highest Priority)");
        else
            $display("FAIL : Test 10");

        // Test 11 : Multiple active inputs
        in = 8'b00101010;
        #10;
        if (out == 3'b101 && valid)
            $display("PASS : Test 11 (Highest Priority)");
        else
            $display("FAIL : Test 11");

        $display("==============================================");
        $display("     Simulation Completed");
        $display("==============================================");

        $finish;

    end

endmodule