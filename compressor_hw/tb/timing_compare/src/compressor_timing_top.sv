// compressor_timing_top.sv
// Synthesis/implementation top for timing benchmark.
//
// Keeps the 64x32-bit packet array and 32x64-bit plane array inside the fabric
// (not as top-level IO). Only control/status ports are exposed so Vivado can
// place-and-route on Pynq-Z2 without exceeding device pin limits.

module compressor_timing_top #(
    parameter int WORD_SIZE   = 32,
    parameter int PACKET_SIZE = 64,
    parameter int GROUP_SIZE  = 8
) (
    input  logic clk,
    input  logic nrst,
    input  logic start,
    output logic valid,
    output logic [WORD_SIZE-1:0] key_out,
    output logic [$clog2(PACKET_SIZE+1)-1:0] out_count
);

    logic [WORD_SIZE-1:0] data_packet [PACKET_SIZE-1:0];
    logic [PACKET_SIZE-1:0] packed_planes [WORD_SIZE-1:0];

    // Hold a representative packet in fabric registers (not top-level IO).
    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            for (int i = 0; i < PACKET_SIZE; i++)
                data_packet[i] <= WORD_SIZE'(i * 17);
        end
    end

    // Prevent packed_planes from being optimized away during timing closure.
    logic [PACKET_SIZE-1:0] packed_planes_sink [WORD_SIZE-1:0];
    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            for (int i = 0; i < WORD_SIZE; i++)
                packed_planes_sink[i] <= '0;
        end else begin
            for (int i = 0; i < WORD_SIZE; i++)
                packed_planes_sink[i] <= packed_planes[i];
        end
    end

    (* keep_hierarchy = "yes" *)
    compressor #(
        .WORD_SIZE(WORD_SIZE),
        .PACKET_SIZE(PACKET_SIZE),
        .GROUP_SIZE(GROUP_SIZE)
    ) u_compressor (
        .clk(clk),
        .nrst(nrst),
        .start(start),
        .data_packet(data_packet),
        .packed_planes(packed_planes),
        .valid(valid),
        .out_count(out_count),
        .key_out(key_out)
    );

endmodule