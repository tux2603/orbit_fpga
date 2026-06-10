module lcd #(
        parameter C_S_AXI_DATA_WIDTH = 32,
        parameter C_S_AXI_ADDR_WIDTH = 5,
        parameter LCD_WIDTH = 16,
        parameter LCD_HEIGHT = 2
    ) (
        // AXI4-Lite Slave Interface
        input wire s_axi_aclk,
        input wire s_axi_aresetn,
        input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
        input wire [2:0] s_axi_awprot,
        input wire s_axi_awvalid,
        output reg s_axi_awready = 1'b1,
        input wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
        input wire [C_S_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
        input wire s_axi_wvalid,
        output reg s_axi_wready = 1'b1,
        output wire [1:0] s_axi_bresp,
        output reg s_axi_bvalid = 1'b0,
        input wire s_axi_bready,
        input wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
        input wire [2:0] s_axi_arprot,
        input wire s_axi_arvalid,
        output reg s_axi_arready = 1'b1,
        output reg [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
        output wire [1:0] s_axi_rresp,
        output reg s_axi_rvalid = 1'b0,
        input wire s_axi_rready,

        // LCD Interface
        output reg lcd_rs = 1'b0, // Arduino pin D8
        output reg lcd_en = 1'b0, // Arduino pin D9
        output reg [3:0] lcd_data = 4'b0000 // Arduino pins D4-D7
    );

    localparam NUM_REGS = (2**C_S_AXI_ADDR_WIDTH) / 4; // Number of 32-bit registers
    localparam ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1; // Works for 32-bit and 64-bit data widths
    localparam MEM_ADDR_BITS = C_S_AXI_ADDR_WIDTH - ADDR_LSB;

    // Internal AXI status registers
    reg axi_awaddr_latched = 1'b0;
    reg axi_wdata_latched = 1'b0;
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_awaddr_reg = 'b0;
    reg [C_S_AXI_DATA_WIDTH-1 : 0] axi_wdata_reg = 'b0;
    reg [C_S_AXI_DATA_WIDTH/8-1 : 0] axi_wstrb_reg = 'b0;

    // AXI4-Lite registers
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_data_array[0:NUM_REGS-1];    
    
    initial begin : AXI_REG_INIT
        // Initialize registers to zero
        integer i;
        for (i = 0; i < NUM_REGS; i = i + 1) begin
            axi_data_array[i] = 32'b0;
        end
    end

    // LCD clock enable
    localparam AXI_CLK_PERIOD = 9524; // Clock period in ps
    localparam LCD_CLK_PERIOD = 10000000; // LCD clock period in ns
    localparam LCD_CLK_DIV_MAX_COUNT = LCD_CLK_PERIOD / AXI_CLK_PERIOD + 1; // Clock divider for LCD clock

    reg lcd_clk_en = 1'b0;
    reg [$clog2(LCD_CLK_DIV_MAX_COUNT)-1:0] lcd_clk_div_counter = 'b0;

    // LCD state machine states
    reg [7:0] lcd_state = 8'b0;

    localparam LCD_STATE_INIT = 8'b0000_0000; // Wait for power-up
    localparam LCD_STATE_FS_1 = 8'b0000_0001; // Function set 1 (4-bit mode)
    localparam LCD_STATE_FS_2 = 8'b0000_0010; // Function set 2 (2 line, 5x8 dots)
    localparam LCD_STATE_FS_3 = 8'b0000_0100; // Function set 3 (2 line, 5x8 dots)
    localparam LCD_STATE_DOOC = 8'b0000_1000; // Display on/off control
    localparam LCD_STATE_DCLR = 8'b0001_0000; // Display clear
    localparam LCD_STATE_DEMS = 8'b0010_0000; // Display entry mode set
    localparam LCD_STATE_CHAR = 8'b0100_0000; // Write character to LCD
    localparam LCD_STATE_LINE = 8'b1000_0000; // Move cursor to next line

    localparam LCD_INIT_DELAY_MAX_COUNT = 40_000_000 / LCD_CLK_PERIOD; // 40 ms delay for LCD initialization
    localparam LCD_CLR_DELAY_MAX_COUNT = 1_530_000 / LCD_CLK_PERIOD; // 1.53 ms delay for LCD clear command
    localparam LCD_CMD_DELAY_MAX_COUNT = 40_000 / LCD_CLK_PERIOD; // 40 us delay for LCD command execution

    reg [$clog2(LCD_INIT_DELAY_MAX_COUNT)-1:0] lcd_state_counter = 'b0;

    reg [3:0] lcd_col = 4'b0;
    reg lcd_row = 1'b0;
    reg [4:0] char_byte_addr;
    reg [7:0] current_char;



    // ##### AXI4-Lite Write Logic #####

    always @(posedge s_axi_aclk) begin : AXI_WRITE_FSM
        integer i, reg_addr, byte_index;
        
        // Reset logic
        if (!s_axi_aresetn) begin
            for (i = 0; i < C_S_AXI_ADDR_WIDTH; i = i + 1) begin
                axi_data_array[i] <= 32'b0;
            end

            axi_awaddr_latched <= 1'b0;
            axi_wdata_latched <= 1'b0;
            axi_awaddr_reg <= 'b0;
            axi_wdata_reg <= 'b0;

            // By default, we are ready to accept write addresses and data
            // But there is no valid write response until we process a write
            s_axi_awready <= 1'b1;
            s_axi_wready <= 1'b1;
            s_axi_bvalid <= 1'b0; // No write response available until we process
        end 
        
        // Update logic
        else begin
            // Write logic: update the data array based on the write address and data
            if (s_axi_awvalid && s_axi_awready) begin
                axi_awaddr_latched = 1'b1;
                axi_awaddr_reg = s_axi_awaddr;

                s_axi_awready <= 1'b0; // De-assert ready until the write is processed
            end

            if (s_axi_wvalid && s_axi_wready) begin
                axi_wdata_latched = 1'b1;
                axi_wdata_reg = s_axi_wdata;
                axi_wstrb_reg = s_axi_wstrb;

                s_axi_wready <= 1'b0; // De-assert ready until the write is processed
            end

            // Process the write when both address and data are latched
            if (axi_awaddr_latched && axi_wdata_latched) begin
                // Write the data to the appropriate location in the data array
                reg_addr = axi_awaddr_reg[ADDR_LSB +: MEM_ADDR_BITS];

                // Apply the write strobe to determine which bytes to update
                for (byte_index = 0; byte_index < (C_S_AXI_DATA_WIDTH/8); byte_index = byte_index + 1) begin
                    if (axi_wstrb_reg[byte_index]) begin
                        axi_data_array[reg_addr][(byte_index*8) +: 8] <= axi_wdata_reg[(byte_index*8) +: 8];
                    end
                end

                // Clear the latched signals and assert the write response
                axi_awaddr_latched <= 1'b0;
                axi_wdata_latched <= 1'b0;
                s_axi_bvalid <= 1'b1; // Indicate that the write response is available
            end

            // Clear the write response when the master acknowledges it
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0; // Clear the write response
                s_axi_awready <= 1'b1; // Reassert ready for the next write
                s_axi_wready <= 1'b1; // Reassert ready for the next write
            end
        end
    end

    // The write response is always OKAY for this simple implementation
    assign s_axi_bresp = 2'b00; // OKAY response



    // ##### AXI4-Lite Read Logic #####

    always @(posedge s_axi_aclk) begin : AXI_READ_FSM
        integer reg_addr;
        
        // Reset logic
        if (!s_axi_aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata <= 'b0;

            // By default, we are ready to accept read addresses with no data to return
            s_axi_arready <= 1'b1;
            s_axi_rvalid <= 1'b0; 
        end 
        
        // Update logic
        else begin
            if (s_axi_arvalid && s_axi_arready) begin
                reg_addr = s_axi_araddr[ADDR_LSB +: MEM_ADDR_BITS];
                s_axi_rdata <= axi_data_array[reg_addr]; // Read the data from the appropriate location in the data array
                s_axi_rvalid <= 1'b1; // Indicate that the read data is available
                s_axi_arready <= 1'b0; // Deassert ready until the read is acknowledged
            end

            // Clear the read valid signal when the master acknowledges the read data
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0; // Clear the read valid signal
                s_axi_arready <= 1'b1; // Reassert ready for the next read
            end
        end
    end

    // The read response is always OKAY for this simple implementation
    assign s_axi_rresp = 2'b00; // OKAY response



    // ##### LCD Control Logic #####

    // Generate the LCD clock enable signal based on the AXI clock and the desired LCD clock period
    always @(posedge s_axi_aclk) begin : LCD_CLK_GEN
        if (!s_axi_aresetn) begin
            lcd_clk_en <= 1'b0;
            lcd_clk_div_counter <= 'b0;
        end else begin
            if (lcd_clk_div_counter == LCD_CLK_DIV_MAX_COUNT - 1) begin
                lcd_clk_en <= 1'b1; // Enable the LCD clock for one AXI clock cycle
                lcd_clk_div_counter <= 'b0; // Reset the counter
            end else begin
                lcd_clk_en <= 1'b0; // Disable the LCD clock
                lcd_clk_div_counter <= lcd_clk_div_counter + 1; // Increment the counter
            end
        end
    end

    // Update the LCD FSM on the rising edge of the AXI clock when the LCD clock enable signal is high
    always @(posedge s_axi_aclk) begin : LCD_FSM
        if (!s_axi_aresetn) begin
            lcd_state <= LCD_STATE_INIT;
            lcd_state_counter <= 'b0;
            lcd_col <= 4'b0;
            lcd_row <= 1'b0;
        end else if (lcd_clk_en) begin
            lcd_state_counter = lcd_state_counter + 1;

            case (lcd_state)
                LCD_STATE_INIT: begin
                    if (lcd_state_counter >= LCD_INIT_DELAY_MAX_COUNT) begin
                        lcd_state <= LCD_STATE_FS_1;
                        lcd_state_counter <= 'b0;
                    end
                end

                LCD_STATE_FS_1: begin
                    if (lcd_state_counter >= LCD_CMD_DELAY_MAX_COUNT) begin
                        lcd_state <= LCD_STATE_FS_2;
                        lcd_state_counter <= 'b0;
                    end
                end 

                LCD_STATE_FS_2: begin
                    if (lcd_state_counter >= LCD_CMD_DELAY_MAX_COUNT) begin
                        lcd_state <= LCD_STATE_FS_3;
                        lcd_state_counter <= 'b0;
                    end
                end

                LCD_STATE_FS_3: begin
                    if (lcd_state_counter >= LCD_CMD_DELAY_MAX_COUNT) begin
                        lcd_state <= LCD_STATE_DOOC;
                        lcd_state_counter <= 'b0;
                    end
                end

                LCD_STATE_DOOC: begin
                    if (lcd_state_counter >= LCD_CMD_DELAY_MAX_COUNT) begin
                        lcd_state <= LCD_STATE_DCLR;
                        lcd_state_counter <= 'b0;
                    end
                end

                LCD_STATE_DCLR: begin
                    if (lcd_state_counter >= LCD_CLR_DELAY_MAX_COUNT) begin
                        lcd_state <= LCD_STATE_DEMS;
                        lcd_state_counter <= 'b0;
                    end
                end

                LCD_STATE_DEMS: begin
                    if (lcd_state_counter >= LCD_CMD_DELAY_MAX_COUNT) begin
                        lcd_state <= LCD_STATE_CHAR;
                        lcd_state_counter <= 'b0;
                    end
                end

                LCD_STATE_CHAR: begin
                    // If we are at the last character of the line, go to the next line state.
                    // Otherwise, stay in the character state to write the next character.
                    if (lcd_state_counter >= LCD_CMD_DELAY_MAX_COUNT) begin
                        if (lcd_col == LCD_WIDTH - 1) begin
                            lcd_state <= LCD_STATE_LINE;
                            lcd_col <= 4'b0; // Reset column to 0 for the next line
                        end else begin
                            lcd_state <= LCD_STATE_CHAR;
                            lcd_col <= lcd_col + 1; // Move to the next column
                        end
                        lcd_state_counter <= 'b0;
                    end
                end

                LCD_STATE_LINE: begin
                    if (lcd_state_counter >= LCD_CMD_DELAY_MAX_COUNT) begin
                        lcd_state <= LCD_STATE_CHAR;
                        lcd_state_counter <= 'b0;
                        lcd_row <= ~lcd_row; // Toggle between line 0 and line 1
                    end
                end
            endcase
        end
    end

    // Combinational outputs
    always @(*) begin : LCD_COMB_OUT
        // Default values for control signals and data
        lcd_rs = 1'b0; // Command mode by default
        lcd_en = 1'b0; // Disable LCD by default
        lcd_data = 4'b0000; // Default data

        // Get the current character to display based on the current row and column
        char_byte_addr = lcd_row * LCD_WIDTH + lcd_col;
        current_char = axi_data_array[char_byte_addr[4:2]][char_byte_addr[1:0]*8 +: 8];

        case (lcd_state)
            LCD_STATE_INIT: begin
                // Nothing to do here since we are just waiting for the initialization delay
            end

            LCD_STATE_FS_1: begin
                case (lcd_state_counter)
                    0: begin // Function set, 8-bit mode
                        lcd_rs = 1'b0;
                        lcd_en = 1'b1;
                        lcd_data = 4'b0011;
                    end

                    1: begin // De-assert enable to write the command
                        lcd_rs = 1'b0;
                        lcd_en = 1'b0;
                        lcd_data = 4'b0011;                        
                    end
                endcase
            end

            LCD_STATE_FS_2, LCD_STATE_FS_3: begin
                case (lcd_state_counter)
                    0: begin // Function set 4-bit mode, 2 lines, 5x8 dots
                        lcd_rs = 1'b0;
                        lcd_en = 1'b1;
                        lcd_data = 4'b0010; // Upper nibble of the command
                    end

                    1: begin // De-assert enable to write the command
                        lcd_rs = 1'b0;
                        lcd_en = 1'b0;
                        lcd_data = 4'b0010;                        
                    end

                    2: begin // Function set 4-bit mode, 2 lines, 5x8 dots
                        lcd_rs = 1'b0;
                        lcd_en = 1'b1;
                        lcd_data = 4'b10xx; // Lower nibble of the command
                    end

                    3: begin // De-assert enable to write the command
                        lcd_rs = 1'b0;
                        lcd_en = 1'b0;
                        lcd_data = 4'b10xx;
                    end
                endcase
            end

            LCD_STATE_DOOC: begin
                case (lcd_state_counter)
                    0: begin // Display on/off control, display on, cursor off, blink off
                        lcd_rs = 1'b0;
                        lcd_en = 1'b1;
                        lcd_data = 4'b0000; // Upper nibble of the command
                    end

                    1: begin // De-assert enable to write the command
                        lcd_rs = 1'b0;
                        lcd_en = 1'b0;
                        lcd_data = 4'b0000;                        
                    end

                    2: begin // Display on/off control, display on, cursor off, blink off
                        lcd_rs = 1'b0;
                        lcd_en = 1'b1;
                        lcd_data = 4'b1100; // Lower nibble of the command
                    end

                    3: begin // De-assert enable to write the command
                        lcd_rs = 1'b0;
                        lcd_en = 1'b0;
                        lcd_data = 4'b1100;                        
                    end
                endcase
            end

            LCD_STATE_DCLR: begin
                case (lcd_state_counter)
                    0: begin // Display clear command
                        lcd_rs = 1'b0;
                        lcd_en = 1'b1;
                        lcd_data = 4'b0000; // Upper nibble of the command
                    end

                    1: begin // De-assert enable to write the command
                        lcd_rs = 1'b0;
                        lcd_en = 1'b0;
                        lcd_data = 4'b0000;                        
                    end

                    2: begin // Display clear command
                        lcd_rs = 1'b0;
                        lcd_en = 1'b1;
                        lcd_data = 4'b0001; // Lower nibble of the command
                    end

                    3: begin // De-assert enable to write the command
                        lcd_rs = 1'b0;
                        lcd_en = 1'b0;
                        lcd_data = 4'b0001;                        
                    end
                endcase
            end

            LCD_STATE_DEMS: begin
                case (lcd_state_counter)
                    0: begin // Entry mode set, increment cursor, no display shift
                        lcd_rs = 1'b0;
                        lcd_en = 1'b1;
                        lcd_data = 4'b0000; // Upper nibble of the command
                    end

                    1: begin // De-assert enable to write the command
                        lcd_rs = 1'b0;
                        lcd_en = 1'b0;
                        lcd_data = 4'b0000;                        
                    end

                    2: begin // Entry mode set, increment cursor, no display shift
                        lcd_rs = 1'b0;
                        lcd_en = 1'b1;
                        lcd_data = 4'b0110; // Lower nibble of the command
                    end

                    3: begin // De-assert enable to write the command
                        lcd_rs = 1'b0;
                        lcd_en = 1'b0;
                        lcd_data = 4'b0110;                        
                    end
                endcase
            end

            LCD_STATE_CHAR: begin
                case (lcd_state_counter)
                    0: begin // Write the upper nibble of the character
                        lcd_rs = 1'b1; // Data mode
                        lcd_en = 1'b1;
                        lcd_data = current_char[7:4]; // Upper nibble of the character
                    end

                    1: begin // De-assert enable to write the upper nibble
                        lcd_rs = 1'b1; // Data mode
                        lcd_en = 1'b0;
                        lcd_data = current_char[7:4];                        
                    end

                    2: begin // Write the lower nibble of the character
                        lcd_rs = 1'b1; // Data mode
                        lcd_en = 1'b1;
                        lcd_data = current_char[3:0]; // Lower nibble of the character
                    end

                    3: begin // De-assert enable to write the lower nibble
                        lcd_rs = 1'b1; // Data mode
                        lcd_en = 1'b0;
                        lcd_data = current_char[3:0];                        
                    end
                endcase
            end

            LCD_STATE_LINE: begin
                case (lcd_state_counter)
                    0: begin // Move cursor to the next line
                        lcd_rs = 1'b0; // Command mode
                        lcd_en = 1'b1;
                        lcd_data = lcd_row ? 4'b1000 : 4'b1100;
                    end

                    1: begin // De-assert enable to write the command
                        lcd_rs = 1'b0; // Command mode
                        lcd_en = 1'b0;
                        lcd_data = lcd_row ? 4'b1000 : 4'b1100;                        
                    end

                    2: begin // Move cursor to the next line
                        lcd_rs = 1'b0; // Command mode
                        lcd_en = 1'b1;
                        lcd_data = 4'b0000; // Lower nibble of the command
                    end

                    3: begin // De-assert enable to write the command
                        lcd_rs = 1'b0; // Command mode
                        lcd_en = 1'b0;
                        lcd_data = 4'b0000;                        
                    end
                endcase
            end
        endcase
    end
endmodule