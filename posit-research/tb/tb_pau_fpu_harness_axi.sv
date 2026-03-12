module tb_pau_fpu_harness_axi import ariane_pkg::*; ();
    logic        clk;
    logic        rst_n;

    logic [31:0] awaddr;
    logic [2:0]  awprot;
    logic        awvalid;
    logic        awready;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;
    logic [31:0] araddr;
    logic [2:0]  arprot;
    logic        arvalid;
    logic        arready;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;

    pau_fpu_harness_axi dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    task static axi_write(input [31:0] addr, input [31:0] data);
        awaddr = addr;
        awvalid = 1;
        wdata = data;
        wstrb = 4'hf;
        wvalid = 1;
        bready = 1;
        @(posedge clk);
        while (!awready || !wready) @(posedge clk);
        awvalid = 0;
        wvalid = 0;
        while (!bvalid) @(posedge clk);
        @(posedge clk);
    endtask

    task static axi_read(input [31:0] addr, output [31:0] data);
        araddr = addr;
        arvalid = 1;
        rready = 1;
        @(posedge clk);
        while (!arready) @(posedge clk);
        arvalid = 0;
        while (!rvalid) @(posedge clk);
        data = rdata;
        @(posedge clk);
    endtask

    logic [31:0] read_val;

    initial begin
        rst_n = 0;
        awvalid = 0; wvalid = 0; arvalid = 0; bready = 0; rready = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        $display("AXI Test: Writing Operands...");
        // Write OP_A = 0x7F939D17
        axi_write(32'h00, 32'h7F939D17);
        // Write OP_B = 0x7F6EC2BF
        axi_write(32'h08, 32'h7F6EC2BF);
        // Write CONTROL (PADD=26 (approx based on enum), PAU=10, VALID=1)
        // PADD is 26th in enum (0-indexed) -> 0x1A
        // PAU is 10th in enum -> 0xA
        // Control word: {valid[12], fu[11:8], op[7:0]}
        // 1_1010_1010_1010 -> but wait, let's use the actual values
        axi_write(32'h10, (1 << 12) | (10 << 8) | 8'h1A); 

        $display("AXI Test: Waiting for result...");
        do begin
            axi_read(32'h1C, read_val); // Read STATUS
        end while (read_val[0] == 0);

        axi_read(32'h14, read_val); // Read RES_LO
        $display("AXI Result: %h", read_val);

        repeat(20) @(posedge clk);
        $finish;
    end
endmodule
