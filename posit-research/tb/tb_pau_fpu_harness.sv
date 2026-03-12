module tb_pau_fpu_harness import ariane_pkg::*; ();
    logic        clk;
    logic        rst_n;
    logic [63:0] op_a;
    logic [63:0] op_b;
    logic [7:0]  op_sel;
    logic [3:0]  fu_sel;
    logic        valid_i;
    logic [63:0] result;
    logic        valid_o;
    logic        ready_o;

    pau_fpu_harness dut (
        .clk_i    ( clk     ),
        .rst_ni   ( rst_n   ),
        .op_a_i   ( op_a    ),
        .op_b_i   ( op_b    ),
        .op_sel_i ( op_sel  ),
        .fu_sel_i ( fu_sel  ),
        .valid_i  ( valid_i ),
        .result_o ( result  ),
        .valid_o  ( valid_o ),
        .ready_o  ( ready_o )
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    task static reset();
        rst_n = 0;
        op_a = 0;
        op_b = 0;
        op_sel = 0;
        fu_sel = 0;
        valid_i = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
    endtask

    initial begin
        reset();

        // PADD Test (from reference)
        // a = 0x7F939D17, b = 0x7F6EC2BF -> expected d = 0x7F99756F
        $display("Starting PADD Test...");
        @(posedge clk);
        op_a = 64'h0000_0000_7F93_9D17;
        op_b = 64'h0000_0000_7F6EC2BF;
        op_sel = PADD;
        fu_sel = PAU;
        valid_i = 1;
        @(posedge clk);
        valid_i = 0;

        wait(valid_o);
        $display("PADD Result: %h (Expected: 7f99756f)", result[31:0]);
        if (result[31:0] == 32'h7F99756F) $display("PADD SUCCESS");
        else $display("PADD FAIL");

        repeat(10) @(posedge clk);

        // PMUL Test
        // a = 0x6F10A532, b = 0x7B9B7665
        $display("Starting PMUL Test...");
        @(posedge clk);
        op_a = 64'h0000_0000_6F10_A532;
        op_b = 64'h0000_0000_7B9B_7665;
        op_sel = PMUL;
        fu_sel = PAU;
        valid_i = 1;
        @(posedge clk);
        valid_i = 0;

        wait(valid_o);
        $display("PMUL Result: %h", result[31:0]);

        // Test QUIRE in Harness
        $display("Starting QUIRE Test in Harness...");
        @(posedge clk);
        op_sel = QCLR;
        fu_sel = PAU;
        valid_i = 1;
        @(posedge clk);
        valid_i = 0;
        repeat(5) @(posedge clk);

        // qmadd 1*1 = 1
        @(posedge clk);
        op_a = 64'h4000_0000;
        op_b = 64'h4000_0000;
        op_sel = QMADD;
        fu_sel = PAU;
        valid_i = 1;
        @(posedge clk);
        valid_i = 0;
        repeat(10) @(posedge clk);

        // qround
        @(posedge clk);
        op_sel = QROUND;
        fu_sel = PAU;
        valid_i = 1;
        @(posedge clk);
        valid_i = 0;
        wait(valid_o);
        $display("Harness QROUND Result: %h (Expected: 40000000)", result[31:0]);

        repeat(20) @(posedge clk);
        $finish;
    end
endmodule
