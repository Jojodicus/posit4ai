module tb_pau_top import ariane_pkg::*; ();
    logic        clk;
    logic        rst_n;
    fu_data_t    fu_data;
    logic        valid_i;
    logic        ready_o;
    logic [TRANS_ID_BITS-1:0] trans_id_o;
    logic        valid_o;
    riscv::xlen_t result;

    pau_top dut (
        .clk_i          ( clk      ),
        .rst_ni         ( rst_n    ),
        .fu_data_i      ( fu_data  ),
        .pau_valid_i    ( valid_i  ),
        .pau_ready_o    ( ready_o  ),
        .pau_trans_id_o ( trans_id_o ),
        .pau_valid_o    ( valid_o  ),
        .result_o       ( result   )
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst_n = 0;
        valid_i = 0;
        fu_data = '0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // Test PADD
        @(posedge clk);
        fu_data.operand_a = 64'h0000_0000_7F93_9D17;
        fu_data.operand_b = 64'h0000_0000_7F6EC2BF;
        fu_data.operator  = PADD;
        valid_i = 1;
        @(posedge clk);
        valid_i = 0;

        wait(valid_o);
        $display("PAU_TOP PADD Result: %h", result[31:0]);

        // Test QUIRE
        $display("Starting QUIRE Test...");
        @(posedge clk);
        fu_data.operator = QCLR;
        valid_i = 1;
        @(posedge clk);
        valid_i = 0;
        repeat(5) @(posedge clk);

        // qmadd 1*1 = 1
        @(posedge clk);
        fu_data.operand_a = 64'h4000_0000;
        fu_data.operand_b = 64'h4000_0000;
        fu_data.operator  = QMADD;
        valid_i = 1;
        @(posedge clk);
        valid_i = 0;
        repeat(10) @(posedge clk);

        // qmadd 3*3 = 9
        @(posedge clk);
        fu_data.operand_a = 64'h4C00_0000;
        fu_data.operand_b = 64'h4C00_0000;
        fu_data.operator  = QMADD;
        valid_i = 1;
        @(posedge clk);
        valid_i = 0;
        repeat(10) @(posedge clk);

        // qmsub 1*3 = 3 -> quire = 1 + 9 - 3 = 7
        @(posedge clk);
        fu_data.operand_a = 64'h4000_0000;
        fu_data.operand_b = 64'h4C00_0000;
        fu_data.operator  = QMSUB;
        valid_i = 1;
        @(posedge clk);
        valid_i = 0;
        repeat(10) @(posedge clk);

        // qround
        @(posedge clk);
        fu_data.operator = QROUND;
        valid_i = 1;
        @(posedge clk);
        valid_i = 0;
        wait(valid_o);
        $display("PAU_TOP QROUND Result: %h (Expected: 56000000)", result[31:0]);

        repeat(20) @(posedge clk);
        $finish;
    end
endmodule
