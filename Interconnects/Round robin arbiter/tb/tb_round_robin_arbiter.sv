`timescale 1ns/1ps

module tb;

    localparam int NUM_REQ = 4;
    localparam time CLK_PERIOD = 10ns;

    logic                 clk;
    logic                 rst_n;
    logic [NUM_REQ-1:0]   req;
    logic [NUM_REQ-1:0]   grant;

    int errors = 0;
    int checks = 0;

    // reference model state
    int ref_ptr;

    // DUT
    round_robin_arbiter #(
        .NUM_REQ(NUM_REQ)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .req   (req),
        .grant (grant)
    );

    // clock generation
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------
    // Reference model function: given request vector and current pointer,
    // return the expected one-hot grant.
    // -------------------------------------------------------------------
    function automatic logic [NUM_REQ-1:0] ref_grant(input logic [NUM_REQ-1:0] r, input int p);
        logic [NUM_REQ-1:0] g;
        logic found;
        g = '0;
        found = 1'b0;
        for (int i = 0; i < NUM_REQ; i++) begin
            int idx;
            idx = (p + i) % NUM_REQ;
            if (r[idx] && !found) begin
                g[idx] = 1'b1;
                found  = 1'b1;
            end
        end
        return g;
    endfunction

    // -------------------------------------------------------------------
    // Drive one cycle and check
    // -------------------------------------------------------------------
    task automatic run_cycle(input logic [NUM_REQ-1:0] r);
        logic [NUM_REQ-1:0] exp_g;
        req = r;
        @(negedge clk); // sample after combinational settle, before clock edge processed
        exp_g = ref_grant(r, ref_ptr);
        checks++;
        if (grant !== exp_g) begin
            errors++;
            $display("[FAIL] t=%0t ptr=%0d req=%b grant=%b expected=%b", $time, ref_ptr, r, grant, exp_g);
        end else begin
            $display("[PASS] t=%0t ptr=%0d req=%b grant=%b", $time, ref_ptr, r, grant);
        end
        if ($countones(grant) > 1) begin
            errors++;
            $display("[FAIL] Grant not one-hot! req=%b grant=%b", r, grant);
        end
        // advance reference pointer model in lockstep with DUT (grant is one-hot or zero)
        for (int i = 0; i < NUM_REQ; i++) begin
            if (exp_g[i]) ref_ptr = (i + 1) % NUM_REQ;
        end
        @(posedge clk); // let DUT register update
    endtask

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb);

        // reset sequence
        rst_n = 1'b0;
        req   = '0;
        ref_ptr = 0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // ----------------- Corner cases -----------------
        run_cycle(4'b0000); // no requests
        run_cycle(4'b1111); // all requesters active - starts at ptr 0
        run_cycle(4'b1111);
        run_cycle(4'b1111);
        run_cycle(4'b1111); // full cycle, pointer should have wrapped back

        run_cycle(4'b0001); // only requester 0 continually requesting
        run_cycle(4'b0001);
        run_cycle(4'b0001);

        // ----------------- Starvation-freedom check -----------------
        // requester 3 requests continuously while others request intermittently
        begin
            logic [NUM_REQ-1:0] seen_grant;
            seen_grant = '0;
            for (int i = 0; i < NUM_REQ*3; i++) begin
                logic [NUM_REQ-1:0] pattern;
                pattern = 4'b1000 | (4'($urandom_range(0,7)));
                run_cycle(pattern);
                seen_grant |= grant;
            end
            if (seen_grant != {NUM_REQ{1'b1}} ) begin
                $display("[INFO] Not all requesters were granted in this random window (may need more cycles): seen=%b", seen_grant);
            end
        end

        // ----------------- Deterministic single-requester sweep -----------------
        for (int i = 0; i < NUM_REQ; i++) begin
            run_cycle(4'(1'b1) << i);
        end

        // ----------------- Randomized vectors -----------------
        for (int i = 0; i < 100; i++) begin
            run_cycle(4'($urandom_range(0,15)));
        end

        // ----------------- Summary -----------------
        if (errors == 0)
            $display("\n=== TESTBENCH RESULT: ALL %0d CHECKS PASSED ===", checks);
        else
            $display("\n=== TESTBENCH RESULT: %0d/%0d CHECKS FAILED ===", errors, checks);

        $finish;
    end

endmodule

