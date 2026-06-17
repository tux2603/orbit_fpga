`timescale 1ns / 1ps


module buttons #(
        parameter C_S_AXI_DATA_WIDTH = 32,
        parameter C_S_AXI_ADDR_WIDTH = 4, // 10 buttons, 1 byte each
        parameter C_S_AXIS_DATA_WIDTH = 16
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

        // AXI4 Stream slave interface
        input wire s_axis_aclk,
        input wire s_axis_aresetn,
        input wire [C_S_AXIS_DATA_WIDTH-1:0] s_axis_tdata,
        input wire [4:0] s_axis_tid,
        output wire s_axis_tready,
        input wire s_axis_tvalid,

        // GPIO inputs
        input wire [3:0] buttons_in
    );

    // Values to check to see what button is being pressed
    // TODO: the rangesfor left, down, and select are current;y not large enough, leading to some noise when the button is held
    localparam RIGHT_MIN = 16'h0000;
    localparam RIGHT_MAX = 16'h01FF;
    localparam UP_MIN = 16'h2E00;
    localparam UP_MAX = 16'h30FF;
    localparam DOWN_MIN = 16'h6300;
    localparam DOWN_MAX = 16'h65FF;
    localparam LEFT_MIN = 16'h8800;
    localparam LEFT_MAX = 16'h8AFF;
    localparam SELECT_MIN = 16'hB000;
    localparam SELECT_MAX = 16'hB2FF;
    localparam NONE_MIN = 16'hDD00;
    localparam NONE_MAX = 16'hDFFF;

    localparam NUM_REGS = (2**C_S_AXI_ADDR_WIDTH) / (C_S_AXI_DATA_WIDTH / 8);
    localparam ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
    localparam MEM_ADDR_BITS = C_S_AXI_ADDR_WIDTH - ADDR_LSB;

    // AXI4-Lite registers
    reg [C_S_AXI_DATA_WIDTH-1:0] button_values[0:NUM_REGS-1];

    reg [15:0] adc_value = 16'hFF;

    // Do some basic CDC on the button inputs to avoid metastability issues
    reg [3:0] buttons_cdc0;
    reg [3:0] buttons_cdc1;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            buttons_cdc0 <= 4'b0;
            buttons_cdc1 <= 4'b0;
        end else begin
            buttons_cdc0 <= buttons_in;
            buttons_cdc1 <= buttons_cdc0;
        end
    end


    // AXI4 Stream coming into the module, just expose the value on the AXI4-Lite interface at address 0
    always @(posedge s_axis_aclk) begin
        if (!s_axis_aresetn) begin
            adc_value <= 16'hFF;
        end else if (s_axis_tvalid) begin
            if (s_axis_tid == 5'h11) begin
                adc_value <= s_axis_tdata;
            end
        end
    end

    assign s_axis_tready = 1'b1; // Always ready to accept data on the AXI4 Stream interface

    
    // Update the button values in the AXI4-Lite registers
    always @(posedge s_axi_aclk) begin : BTN_UPDATE
        integer i;
        
        // Reset all button values to 0 on reset, otherwise update the button values based on the current state of the buttons
        if (!s_axi_aresetn) begin
            for (i = 0; i < NUM_REGS; i = i + 1) begin
                button_values[i] <= 32'b0;
            end
        end 
        
        else begin
            button_values[0] <= {
                buttons_cdc1[3] ? 8'h01 : 8'h00,
                buttons_cdc1[2] ? 8'h01 : 8'h00,
                buttons_cdc1[1] ? 8'h01 : 8'h00,
                buttons_cdc1[0] ? 8'h01 : 8'h00
            };

            if (adc_value >= RIGHT_MIN && adc_value <= RIGHT_MAX) begin
                button_values[1] <= 32'h00000001; // Right button pressed
            end else if (adc_value >= UP_MIN && adc_value <= UP_MAX) begin
                button_values[1] <= 32'h00000100; // Up button pressed
            end else if (adc_value >= DOWN_MIN && adc_value <= DOWN_MAX) begin
                button_values[1] <= 32'h00010000; // Down button pressed
            end else if (adc_value >= LEFT_MIN && adc_value <= LEFT_MAX) begin
                button_values[1] <= 32'h01000000; // Left button pressed
            end else begin
                button_values[1] <= 32'h00000000; // No button in group pressed
            end

            if (adc_value >= SELECT_MIN && adc_value <= SELECT_MAX) begin
                button_values[2] <= 32'h00000001; // Select button pressed
            end else  begin
                button_values[2] <= 32'h00000000; // No button in group pressed
            end
        end
    end


    // We don't need AXI4-Lite write functionality for this module, so just return an error if the master tries to write to any address
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_bvalid <= 1'b0;
        end else if (s_axi_awvalid && s_axi_wvalid) begin
            s_axi_bvalid <= 1'b1;
        end else if (s_axi_bvalid && s_axi_bready) begin
            s_axi_bvalid <= 1'b0;
        end
    end

    assign s_axi_bresp = 2'b11; // SLVERR


    // Handle AXI4-Lite read transactions
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata <= 'b0;
            s_axi_arready <= 1'b1;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rdata <= button_values[s_axi_araddr[ADDR_LSB +: MEM_ADDR_BITS]];
                s_axi_rvalid <= 1'b1;
                s_axi_arready <= 1'b0;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
                s_axi_arready <= 1'b1;
            end
        end
    end

    // Since we only support read transactions, we can just return OKAY for all reads
    assign s_axi_rresp = 2'b00; // OKAY
endmodule