// compressor_ref_pkg.sv
// Golden reference model for compressor.sv — matches posit_compress.py per-packet pipeline.

package compressor_ref_pkg;

    localparam int WORD_SIZE   = 32;
    localparam int PACKET_SIZE = 64;
    localparam int GROUP_SIZE  = 8;
    localparam int GROUPS      = WORD_SIZE / GROUP_SIZE;
    localparam logic [WORD_SIZE-1:0] NB_MASK = {WORD_SIZE/2{2'b10}};

    function automatic void ref_diffnb(
        input  logic [WORD_SIZE-1:0] data_packet    [PACKET_SIZE-1:0],
        output logic [WORD_SIZE-1:0] encoded_packet [PACKET_SIZE-1:0]
    );
        logic [WORD_SIZE-1:0] delta;
        for (int i = 0; i < PACKET_SIZE; i++) begin
            delta = (i == 0) ? data_packet[0] : data_packet[i] - data_packet[i - 1];
            encoded_packet[i] = (delta + NB_MASK) ^ NB_MASK;
        end
    endfunction

    function automatic void ref_bit_transpose(
        input  logic [WORD_SIZE-1:0] encoded_packet     [PACKET_SIZE-1:0],
        output logic [PACKET_SIZE-1:0] transposed_planes [WORD_SIZE-1:0]
    );
        for (int bit_idx = 0; bit_idx < WORD_SIZE; bit_idx++)
            for (int word = 0; word < PACKET_SIZE; word++)
                transposed_planes[bit_idx][word] = encoded_packet[word][bit_idx];
    endfunction

    function automatic void ref_pack_group(
        input  logic [GROUP_SIZE-1:0] key_slice,
        input  logic [PACKET_SIZE-1:0] in_slice [GROUP_SIZE-1:0],
        output logic [PACKET_SIZE-1:0] out_slice [GROUP_SIZE-1:0],
        output int count
    );
        int ptr = 0;
        for (int i = 0; i < GROUP_SIZE; i++)
            out_slice[i] = '0;
        for (int i = 0; i < GROUP_SIZE; i++)
            if (key_slice[i]) begin
                out_slice[ptr] = in_slice[i];
                ptr++;
            end
        count = ptr;
    endfunction

    function automatic void ref_rze(
        input  logic [PACKET_SIZE-1:0] transposed_planes [WORD_SIZE-1:0],
        output logic [PACKET_SIZE-1:0] packed_planes     [WORD_SIZE-1:0],
        output logic [WORD_SIZE-1:0] key_out,
        output int out_count
    );
        logic [PACKET_SIZE-1:0] packed_group [GROUPS-1:0][GROUP_SIZE-1:0];
        int group_count [GROUPS-1:0];
        int ptr = 0;

        for (int i = 0; i < WORD_SIZE; i++) begin
            packed_planes[i] = '0;
            key_out[i] = |transposed_planes[i];
        end

        for (int g = 0; g < GROUPS; g++) begin
            logic [GROUP_SIZE-1:0] key_slice;
            logic [PACKET_SIZE-1:0] in_slice [GROUP_SIZE-1:0];
            for (int j = 0; j < GROUP_SIZE; j++) begin
                int idx = g * GROUP_SIZE + j;
                key_slice[j] = key_out[idx];
                in_slice[j]  = transposed_planes[idx];
            end
            ref_pack_group(key_slice, in_slice, packed_group[g], group_count[g]);
        end

        for (int g = 0; g < GROUPS; g++)
            for (int j = 0; j < group_count[g]; j++) begin
                packed_planes[ptr] = packed_group[g][j];
                ptr++;
            end
        out_count = ptr;
    endfunction

    function automatic void ref_compress_packet(
        input  logic [WORD_SIZE-1:0] data_packet   [PACKET_SIZE-1:0],
        output logic [PACKET_SIZE-1:0] packed_planes [WORD_SIZE-1:0],
        output logic [WORD_SIZE-1:0] key_out,
        output int out_count
    );
        logic [WORD_SIZE-1:0] encoded     [PACKET_SIZE-1:0];
        logic [PACKET_SIZE-1:0] transposed [WORD_SIZE-1:0];

        ref_diffnb(data_packet, encoded);
        ref_bit_transpose(encoded, transposed);
        ref_rze(transposed, packed_planes, key_out, out_count);
    endfunction

endpackage