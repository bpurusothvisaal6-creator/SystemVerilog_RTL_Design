`timescale 1ns/1ps

module tb;

    localparam int NUM_REQ = 8;

    logic [NUM_REQ-1:0] req;
    logic [NUM_REQ-1:0] grant;
    logic [NUM_REQ-1:0] expected_grant;

    int errors  = 0;
    int checks  = 0;

    // DUT instantiation
    fixed_priority_arbiter #(
        .NUM_REQ(NUM_REQ)
    ) dut (
        .req   (req),
        .grant (grant)
    );

    // -------------------------------------------------------------------
    // Reference model: lowest index requester with req=1 wins
    // -------------------------------------------------------------------
    function automatic logic [NUM_REQ-1:0] ref_model(input logic [NUM_REQ-1:0] r);
        logic [NUM_REQ-1:0] g;
        logic found;
        g = '0;
        found = 1'b0;
        for (int i = 0; i < NUM_REQ; i++) begin
            if (r[i] && !found) begin
                g[i] = 1'b1;
                found = 1'b1;
            end
        end
        return g;
    endfunction

    // -------------------------------------------------------------------
    // Check task
    // -------------------------------------------------------------------
    task automatic check_vector(input logic [NUM_REQ-1:0] r);
        req = r;
        #5; // allow combinational settle
        expected_grant = ref_model(r);
        checks++;
        if (grant !== expected_grant) begin
            errors++;
            $display("[FAIL] t=%0t req=%b grant=%b expected=%b", $time, r, grant, expected_grant);
        end else begin
            $display("[PASS] t=%0t req=%b grant=%b", $time, r, grant);
        end
        // one-hot / all-zero legality check
        if ($countones(grant) > 1) begin
            errors++;
            $display("[FAIL] Grant not one-hot! req=%b grant=%b", r, grant);
        end
    endtask

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb);

        // ----------------- Corner cases -----------------
        check_vector('0);                       // no requests
        check_vector({NUM_REQ{1'b1}});           // all requests -> req[0] wins
        check_vector(8'b0000_0001);              // only lowest priority-index req
        check_vector(8'b1000_0000);              // only highest index req
        check_vector(8'b1000_0001);              // lowest and highest both req

        // ----------------- Deterministic sweep -----------------
        for (int i = 0; i < NUM_REQ; i++) begin
            check_vector(1'b1 << i);
        end

        // ----------------- Randomized vectors -----------------
        for (int i = 0; i < 200; i++) begin
            check_vector($urandom_range(0, (1<<NUM_REQ)-1));
        end

        // ----------------- Summary -----------------
        if (errors == 0)
            $display("\n=== TESTBENCH RESULT: ALL %0d CHECKS PASSED ===", checks);
        else
            $display("\n=== TESTBENCH RESULT: %0d/%0d CHECKS FAILED ===", errors, checks);

        $finish;
