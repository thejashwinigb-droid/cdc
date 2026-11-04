
module serial_crc24 (
    input  wire        clk,
    input  wire        rst_n,

    // CRC initialization
    input  wire        preset_en,
    input  wire [23:0] preset_val,

    // Serial PDU input
    input  wire        bit_en,
    input  wire        din,
    input  wire        last_bit,

    // CRC output
    output wire [23:0] crc_out,
    output reg         crc_done,

    // RX CRC comparison
    input  wire [23:0] rx_crc_field,
    input  wire        rx_compare_en,
    output wire        crc_match
);

    // 24-bit CRC state
    reg [23:0] crc_reg;

    // Polynomial:
    // x^24 + x^10 + x^9 + x^6
    //      + x^4 + x^3 + x + 1
    localparam [23:0] POLY_MASK = 24'h00065B;

    wire feedback;
    wire [23:0] shifted_crc;
    wire [23:0] next_crc;

    // Feedback calculation
    assign feedback = crc_reg[23] ^ din;

    // Shift CRC left by one bit; insert zero at bit 0
    assign shifted_crc = {crc_reg[22:0], 1'b0};

    // Apply polynomial only when feedback is 1
    assign next_crc = shifted_crc ^
                      (feedback ? POLY_MASK : 24'h000000);

    // CRC state and completion control
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_reg  <= 24'h000000;
            crc_done <= 1'b0;
        end
        else begin
            // Default: completion pulse lasts one cycle
            crc_done <= 1'b0;

            // Priority 1: initialization
            if (preset_en) begin
                crc_reg <= preset_val;
            end

            // Priority 2: process one input bit
            else if (bit_en) begin
                crc_reg <= next_crc;

                if (last_bit)
                    crc_done <= 1'b1;
            end

            // Otherwise hold CRC state
        end
    end

    // Current CRC value
    assign crc_out = crc_reg;

    // RX comparison
    // Enable comparison only after the CRC is ready
    assign crc_match = rx_compare_en &&
                       (crc_reg == rx_crc_field);

endmodule

