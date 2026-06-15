// Repeated Zero Elimination (RZE) module - 1 clock cycle
module rze #( parameter WORD_SIZE = 32, parameter PACKET_SIZE = 64 , parameter GROUP_SIZE = 8 ) (
    input logic clk,
    input logic nrst,
    input logic start,
    input logic [PACKET_SIZE-1:0] in [WORD_SIZE-1:0],
    output logic valid,
    output logic [PACKET_SIZE-1:0] out [WORD_SIZE-1:0],
    output logic [$clog2(PACKET_SIZE+1)-1:0] out_count,
    output logic [WORD_SIZE-1:0] key_out
);



localparam GROUPS = WORD_SIZE / GROUP_SIZE;
localparam PACKET_PTR_WIDTH = $clog2(PACKET_SIZE+1);

logic [WORD_SIZE-1:0] key;

// FIXME can be turned into a pipeline stage if the critical path is too long, but it will increase the latency by one cycle.

// generate a bitmap indicating which words have non-zero values.
// combintional logic can be used here since it is not on the critical path, and it will save one clock cycle of latency.
always_comb begin
        key = '0;
        for (int i = 0; i < WORD_SIZE; i++) begin
            key[i] = |in[i];
        end
end


logic [PACKET_SIZE-1:0] packed_group [GROUPS-1:0][GROUP_SIZE-1:0];
logic [$clog2(GROUP_SIZE+1)-1:0] group_count [GROUPS-1:0];
logic [PACKET_SIZE-1:0] bitmap [WORD_SIZE-1:0];

// pack the input data in parallel  using pack_group module
generate
    for (genvar i = 0; i < GROUPS; i++) begin : gen_packer
        logic [PACKET_SIZE-1:0] in_slice [GROUP_SIZE-1:0];
        logic [GROUP_SIZE-1:0] key_slice;

        // slice the input and key for each group
        for (genvar j = 0; j < GROUP_SIZE; j++) begin
            assign in_slice[j] = in[i*GROUP_SIZE + j];
            assign key_slice[j] = key[i*GROUP_SIZE + j];
        end

        // pack the input data based on the key for each group
        pack_group #(.PACKET_SIZE(PACKET_SIZE), .GROUP_SIZE(GROUP_SIZE)) pack_i (
            .key(key_slice),
            .in(in_slice),
            .out(packed_group[i]),
            .count(group_count[i])
        );

    end

endgenerate

// FIXME: additional pipeline step can be added here
logic [PACKET_PTR_WIDTH-1:0] ptr;

// pack groups together in bitmap
always_comb begin 
    ptr= '0;
    bitmap = '{default: '0};

    for (int i = 0; i < GROUPS; i++) begin
        for (int j = 0; j < GROUP_SIZE; j++) begin
            if (j < group_count[i]) begin
                bitmap[ptr] = packed_group[i][j];
                ptr = ptr + 1;
            end
        end
    end
end


/**************************
last (only) pipeline stage 
***************************/

// output the bitmap
always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        out <= '{default: '0};
    end else begin
        out <= bitmap;
    end
end
// output the key
always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        key_out <= '0;
    end else begin
        key_out <= key;
    end
end

//output the count
always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        out_count <= '0;
    end else begin
        out_count <= ptr;
    end
end
// output valid signal
always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        valid <= 0;
    end else if (start) begin
        valid <= 1;
    end else begin
        valid <= 0;
    end
end

endmodule