module tb_cross_correlator;
    reg clk;
    reg rst_n;
    reg [127:0] left_in;
    reg [127:0] right_in;
    reg data_valid;
    wire [6:0] max_lag_index;
    wire done;

    cross_correlator dut (
        .clk(clk),
        .rst_n(rst_n),
        .left_in(left_in),
        .right_in(right_in),
        .data_valid(data_valid),
        .max_lag_index(max_lag_index),
        .done(done)
    );

    reg [15:0] left_mem  [0:63];
    reg [15:0] right_mem [0:63];
    integer i, j;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $readmemh("left.txt", left_mem);
        $readmemh("right.txt", right_mem);

        rst_n = 0;
        data_valid = 0;
        left_in = 0;
        right_in = 0;

        #20 rst_n = 1;
        #10;

        // Push data changes strictly on the negative clock edge
        @(negedge clk);
        data_valid = 1;

        // Deterministic wait: It takes exactly 1 cycle to enter LOAD state
        @(negedge clk);

        // Feed 8 samples per clock
        for (i = 0; i < 8; i = i + 1) begin
            for (j = 0; j < 8; j = j + 1) begin
                left_in[j*16 +: 16] = left_mem[i*8 + j];
                right_in[j*16 +: 16] = right_mem[i*8 + j];
            end
            @(negedge clk);
        end
        data_valid = 0;

        wait(done);
        $display("LAG_OUTPUT:%d", max_lag_index);
        #20 $finish;
    end
endmodule
