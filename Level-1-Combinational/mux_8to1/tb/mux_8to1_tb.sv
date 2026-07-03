//=============================================================================
// Module      : mux_8to1_tb
// Description : Testbench for 8-to-1 Multiplexer
// Author      : B. Purusoth Visaal
// Language    : SystemVerilog
//=============================================================================

module mux_8to1_tb;

    // Testbench signals
    logic [7:0] d;
    logic [2:0] sel;
    logic y;

    // Instantiate the DUT (Device Under Test)
    mux_8to1 dut (
        .d(d),
        .sel(sel),
        .y(y)
    );

    initial begin

        // Apply input pattern
        d = 8'b10101010;

        // Test all select values
        for (int i = 0; i < 8; i++) begin
            sel = i;
            #10;

            if (y == d[i])
                $display("PASS: sel=%0d d=%b y=%b", i, d, y);
            else
                $display("FAIL: sel=%0d Expected=%b Got=%b", i, d[i], y);
        end

        $display("------------------------------------");
        $display("8:1 MUX Test Completed");
        $display("------------------------------------");

        $finish;

    end

endmodule