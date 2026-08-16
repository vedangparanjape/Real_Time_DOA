module cross_correlator (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [127:0] left_in,
    input  wire [127:0] right_in,
    input  wire         data_valid,
    output reg  [6:0]   max_lag_index,
    output reg          done
);

    reg signed [15:0] sipo_left  [0:63];
    reg signed [15:0] sipo_right [0:63];

    reg [3:0] load_counter;
    reg [8:0] compute_counter;

    localparam IDLE    = 3'd0;
    localparam LOAD    = 3'd1;
    localparam COMPUTE = 3'd2;
    localparam DONE_ST = 3'd3;

    reg [2:0] state, next_state;
    integer i, j, m, r, r2;

    reg signed [63:0] max_val_so_far;

    reg signed [31:0] prod     [0:31];
    reg signed [32:0] sum_stg1 [0:15];
    reg signed [33:0] sum_stg2 [0:7];
    reg signed [34:0] sum_stg3 [0:3];
    reg signed [35:0] sum_stg4 [0:1];
    reg signed [36:0] sum_stg5;

    reg [6:0] lag_pipe   [0:5];
    reg [5:0] valid_pipe;

    // Control FSM Sequential
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            load_counter <= 0;
            compute_counter <= 0;
        end else begin
            state <= next_state;
            if (state == LOAD) load_counter <= load_counter + 1;
            else load_counter <= 0;

            if (state == COMPUTE) compute_counter <= compute_counter + 1;
            else compute_counter <= 0;
        end
    end

    // Control FSM Combinational
    always @* begin
        next_state = state;
        done = 1'b0;
        case (state)
            IDLE:    if (data_valid) next_state = LOAD;
            LOAD:    if (load_counter == 7) next_state = COMPUTE;
            COMPUTE: if (compute_counter == 37) next_state = DONE_ST;
            DONE_ST: begin
                done = 1'b1;
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // Shift Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (r = 0; r < 64; r = r + 1) begin
                sipo_left[r]  <= 16'sd0;
                sipo_right[r] <= 16'sd0;
            end
        end else if (state == LOAD) begin
            for (i=0; i<56; i=i+1) begin
                sipo_left[i]  <= sipo_left[i+8];
                sipo_right[i] <= sipo_right[i+8];
            end
            for (j=0; j<8; j=j+1) begin
                sipo_left[56+j]  <= left_in[j*16 +: 16];
                sipo_right[56+j] <= right_in[j*16 +: 16];
            end
        end
    end

    // Pipelined Math Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            max_val_so_far <= 0;
            max_lag_index  <= 0;
            valid_pipe     <= 0;
            for (r2 = 0; r2 < 6; r2 = r2 + 1) lag_pipe[r2] <= 7'd0;
        end else if (state == COMPUTE) begin

            // Generate Validity and Tracking Signals (Explicit mapping)
            valid_pipe[0] <= (compute_counter < 32);
            valid_pipe[1] <= valid_pipe[0];
            valid_pipe[2] <= valid_pipe[1];
            valid_pipe[3] <= valid_pipe[2];
            valid_pipe[4] <= valid_pipe[3];
            valid_pipe[5] <= valid_pipe[4];

            lag_pipe[0] <= compute_counter[6:0];
            lag_pipe[1] <= lag_pipe[0];
            lag_pipe[2] <= lag_pipe[1];
            lag_pipe[3] <= lag_pipe[2];
            lag_pipe[4] <= lag_pipe[3];
            lag_pipe[5] <= lag_pipe[4];

            // Stage 0: 32 Parallel Multiplications
            if (compute_counter < 32) begin
                for (m = 0; m < 32; m = m + 1) begin
                    prod[m] <= $signed(sipo_left[m + 16]) * $signed(sipo_right[m + compute_counter]);
                end
            end

            // Stage 1: 16 Additions
            for (m = 0; m < 16; m = m + 1) begin
                sum_stg1[m] <= prod[2*m] + prod[2*m+1];
            end

            // Stage 2: 8 Additions
            for (m = 0; m < 8; m  = m + 1) begin
                sum_stg2[m] <= sum_stg1[2*m] + sum_stg1[2*m+1];
            end

            // Stage 3: 4 Additions
            for (m = 0; m < 4; m  = m + 1) begin
                sum_stg3[m] <= sum_stg2[2*m] + sum_stg2[2*m+1];
            end

            // Stage 4: 2 Additions
            for (m = 0; m < 2; m  = m + 1) begin
                sum_stg4[m] <= sum_stg3[2*m] + sum_stg3[2*m+1];
            end

            // Stage 5: 1 Final Addition
            sum_stg5 <= sum_stg4[0] + sum_stg4[1];

            // Stage 6: Compare against Max
            if (valid_pipe[5]) begin
                if (lag_pipe[5] == 0) begin
                    max_val_so_far <= sum_stg5;
                    max_lag_index  <= 0;
                end else if (sum_stg5 > max_val_so_far) begin
                    max_val_so_far <= sum_stg5;
                    max_lag_index  <= lag_pipe[5];
                end
            end
        end
    end
endmodule
