// Bit Shuffle/Transpose module - 1 clock cycle
module bit_transpose #( parameter WORD_SIZE = 32, parameter PACKET_SIZE = 64 ) (
    input logic clk,
    input logic nrst,
    input logic [WORD_SIZE-1:0] in [PACKET_SIZE-1:0],
    input logic start,
    output logic valid,
    output logic [PACKET_SIZE-1:0] out [WORD_SIZE-1:0]
);
logic [PACKET_SIZE-1:0] tw [WORD_SIZE-1:0];

    genvar i, j;
    generate
        for (i = 0; i < WORD_SIZE; i++) begin : GEN_ROW
            for (j = 0; j < PACKET_SIZE; j++) begin : GEN_COL
                assign tw[i][j] = in[j][i];
            end
        end
    endgenerate

always_ff @(posedge clk or negedge nrst) begin
    if (!nrst) begin
        out <= '{default: '0};
        valid <= 0;
    end else if (start) begin
        for (int i = 0; i < WORD_SIZE; i++) begin
            out[i] <= tw[i];
        end
        valid <= 1;
    end else begin
        valid <= 0;
    end
end

endmodule