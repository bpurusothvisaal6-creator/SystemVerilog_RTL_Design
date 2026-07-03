//=============================================================================
// Module      : priority_arbiter_8request_tb
// Description : Self-checking Testbench
//=============================================================================

module priority_arbiter_8request_tb;

logic [7:0] req;

logic [7:0] grant;
logic valid;

logic [7:0] expected_grant;
logic expected_valid;

integer pass_count;
integer fail_count;

// DUT

priority_arbiter_8request dut(

    .req(req),
    .grant(grant),
    .valid(valid)

);

initial begin

pass_count=0;
fail_count=0;

$display("=================================");
$display("Priority Arbiter Test Started");
$display("=================================");

for(int i=0;i<256;i++) begin

    req=i;

    #10;

    expected_grant=8'b00000000;
    expected_valid=1'b0;

    if(req[7]) begin
        expected_grant=8'b10000000;
        expected_valid=1'b1;
    end
    else if(req[6]) begin
        expected_grant=8'b01000000;
        expected_valid=1'b1;
    end
    else if(req[5]) begin
        expected_grant=8'b00100000;
        expected_valid=1'b1;
    end
    else if(req[4]) begin
        expected_grant=8'b00010000;
        expected_valid=1'b1;
    end
    else if(req[3]) begin
        expected_grant=8'b00001000;
        expected_valid=1'b1;
    end
    else if(req[2]) begin
        expected_grant=8'b00000100;
        expected_valid=1'b1;
    end
    else if(req[1]) begin
        expected_grant=8'b00000010;
        expected_valid=1'b1;
    end
    else if(req[0]) begin
        expected_grant=8'b00000001;
        expected_valid=1'b1;
    end

    if(grant==expected_grant &&
       valid==expected_valid)

        pass_count++;

    else begin

        fail_count++;

        $display("--------------------------------");
        $display("FAIL");
        $display("REQ      = %b",req);
        $display("EXPECTED = %b",expected_grant);
        $display("GOT      = %b",grant);
        $display("--------------------------------");

    end

end

$display("===============================");
$display("PASS=%0d",pass_count);
$display("FAIL=%0d",fail_count);
$display("===============================");

if(fail_count==0)
    $display("ALL TESTS PASSED");

$finish;

end

endmodule