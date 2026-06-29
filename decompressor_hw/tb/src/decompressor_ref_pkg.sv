// decompressor_ref_pkg.sv
// Golden reference model for decompressor.sv — inverse of compressor per-packet pipeline.

package decompressor_ref_pkg;

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

    function automatic void ref_bit_transpose_to_planes(
        input  logic [WORD_SIZE-1:0] encoded_packet     [PACKET_SIZE-1:0],
        output logic [PACKET_SIZE-1:0] transposed_planes [WORD_SIZE-1:0]
    );
        for (int bit_idx = 0; bit_idx < WORD_SIZE; bit_idx++)
            for (int word = 0; word < PACKET_SIZE; word++)
                transposed_planes[bit_idx][word] = encoded_packet[word][bit_idx];
    endfunction

    function automatic void ref_bit_transpose_to_words(
        input  logic [PACKET_SIZE-1:0] transposed_planes [WORD_SIZE-1:0],
        output logic [WORD_SIZE-1:0] encoded_packet     [PACKET_SIZE-1:0]
    );
        for (int word = 0; word < PACKET_SIZE; word++)
            for (int bit_idx = 0; bit_idx < WORD_SIZE; bit_idx++)
                encoded_packet[word][bit_idx] = transposed_planes[bit_idx][word];
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

    function automatic void ref_unpack_group(
        input  logic [GROUP_SIZE-1:0] key_slice,
        input  logic [PACKET_SIZE-1:0] in_slice [GROUP_SIZE-1:0],
        output logic [PACKET_SIZE-1:0] out_slice [GROUP_SIZE-1:0]
    );
        int ptr = 0;
        for (int i = 0; i < GROUP_SIZE; i++)
            out_slice[i] = '0;
        for (int i = 0; i < GROUP_SIZE; i++)
            if (key_slice[i]) begin
                out_slice[i] = in_slice[ptr];
                ptr++;
            end
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

    function automatic void ref_urze(
        input  logic [PACKET_SIZE-1:0] packed_planes [WORD_SIZE-1:0],
        input  logic [WORD_SIZE-1:0] key_in,
        output logic [PACKET_SIZE-1:0] transposed_planes [WORD_SIZE-1:0]
    );
        logic [PACKET_SIZE-1:0] packed_group [GROUPS-1:0][GROUP_SIZE-1:0];
        int group_count [GROUPS-1:0];
        int ptr = 0;

        for (int g = 0; g < GROUPS; g++) begin
            logic [GROUP_SIZE-1:0] key_slice;
            for (int j = 0; j < GROUP_SIZE; j++)
                key_slice[j] = key_in[g * GROUP_SIZE + j];
            group_count[g] = $countones(key_slice);
        end

        for (int g = 0; g < GROUPS; g++) begin
            for (int j = 0; j < group_count[g]; j++) begin
                packed_group[g][j] = packed_planes[ptr];
                ptr++;
            end
        end

        for (int g = 0; g < GROUPS; g++) begin
            logic [GROUP_SIZE-1:0] key_slice;
            logic [PACKET_SIZE-1:0] out_slice [GROUP_SIZE-1:0];
            for (int j = 0; j < GROUP_SIZE; j++)
                key_slice[j] = key_in[g * GROUP_SIZE + j];
            ref_unpack_group(key_slice, packed_group[g], out_slice);
            for (int j = 0; j < GROUP_SIZE; j++)
                transposed_planes[g * GROUP_SIZE + j] = out_slice[j];
        end
    endfunction

    function automatic void ref_undiffnb(
        input  logic [WORD_SIZE-1:0] encoded_packet [PACKET_SIZE-1:0],
        output logic [WORD_SIZE-1:0] decoded_packet [PACKET_SIZE-1:0]
    );
        logic [WORD_SIZE-1:0] delta;
        logic [WORD_SIZE-1:0] prev;
        delta = ((encoded_packet[0] ^ NB_MASK) - NB_MASK);
        prev = delta;
        decoded_packet[0] = prev;
        for (int i = 1; i < PACKET_SIZE; i++) begin
            delta = ((encoded_packet[i] ^ NB_MASK) - NB_MASK);
            decoded_packet[i] = prev + delta;
            prev = decoded_packet[i];
        end
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
        ref_bit_transpose_to_planes(encoded, transposed);
        ref_rze(transposed, packed_planes, key_out, out_count);
    endfunction

    function automatic void ref_decompress_packet(
        input  logic [PACKET_SIZE-1:0] packed_planes [WORD_SIZE-1:0],
        input  logic [WORD_SIZE-1:0] key_in,
        output logic [WORD_SIZE-1:0] data_packet [PACKET_SIZE-1:0]
    );
        logic [PACKET_SIZE-1:0] transposed [WORD_SIZE-1:0];
        logic [WORD_SIZE-1:0] encoded [PACKET_SIZE-1:0];

        ref_urze(packed_planes, key_in, transposed);
        ref_bit_transpose_to_words(transposed, encoded);
        ref_undiffnb(encoded, data_packet);
    endfunction

endpackage