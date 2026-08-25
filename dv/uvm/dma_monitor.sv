// ============================================================================
// dma_monitor.sv - DMA UVM Monitor
//
// - MMIO register write와 DDR model의 backpressure/error 설정을 관찰하여 transaction 수집.
// - DMA 완료 또는 오류 interrupt 발생 시 수집한 transaction을 scoreboard로 전달.
// ============================================================================

class dma_monitor extends uvm_monitor;
    `uvm_component_utils(dma_monitor)

    // [DMA register map]
    localparam logic [7:0] DMA_CTRL_REG     = 8'h00;
    localparam logic [7:0] DMA_SRC_ADDR_REG = 8'h08;
    localparam logic [7:0] DMA_DST_ADDR_REG = 8'h0C;
    localparam logic [7:0] DMA_SIZE_REG     = 8'h10;

    uvm_analysis_port #(dma_tx) send;

    virtual mmio_if.tb_mp mif;
    virtual axi4_if aif;
    virtual ddr_model_if dif;

    function new(input string name = "dma_monitor", uvm_component parent = null);
        super.new(name, parent);
        send = new("send", this);
    endfunction

    // [build_phase] : MMIO/AXI/DDR model virtual interface 준비
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db #(virtual mmio_if.tb_mp)::get(this, "", "mif", mif))
            `uvm_fatal("MON", "Unable to get mif from uvm_config_db");

        if (!uvm_config_db #(virtual axi4_if)::get(this, "", "aif", aif))
            `uvm_fatal("MON", "Unable to get aif from uvm_config_db");

        if (!uvm_config_db #(virtual ddr_model_if)::get(this, "", "dif", dif))
            `uvm_fatal("MON", "Unable to get dif from uvm_config_db");
    endfunction

    // [run_phase] : MMIO write와 완료/오류 interrupt를 관찰하여 transaction 복원
    virtual task run_phase(uvm_phase phase);
        dma_tx t;

        wait (aif.aresetn == 1'b1);      // 리셋 비활성화 대기
        repeat (2) @(posedge mif.clk);   // 리셋 비활성화 직후 안정화

        t = dma_tx::type_id::create("t");

        forever begin
            @(posedge mif.clk);

            // MMIO interface의 write를 관측하여 transaction 필드 복원
            if (mif.dma_reg_write) begin
                case (mif.dma_reg_addr)
                    // DMA 설정 레지스터 값을 해당 transaction 필드에 저장
                    DMA_SRC_ADDR_REG: t.src_addr = mif.dma_reg_wdata;
                    DMA_DST_ADDR_REG: t.dst_addr = mif.dma_reg_wdata;
                    DMA_SIZE_REG: t.size = mif.dma_reg_wdata;
                    DMA_CTRL_REG: begin
                        // CTRL 하위 비트에서 enable/start/irq 설정 복원
                        t.enable = mif.dma_reg_wdata[0];
                        t.start  = mif.dma_reg_wdata[1];
                        t.irq    = mif.dma_reg_wdata[2];

                        // DMA 시작 시 DDR memory model에 적용된 검증 조건 수집
                        t.backpressure_prob = dif.backpressure_prob;
                        t.error_inject = dif.error_inject;

                        // start가 설정되면 DMA 완료/오류까지 기다린 후 transaction 전달
                        if (t.start) begin
                            @(posedge mif.dma_done_int or posedge mif.dma_error_int);
                            `uvm_info(
                                "MON",
                                $sformatf("Collected Transaction: %s", t.convert2string()),
                                UVM_MEDIUM
                            )
                            // 완성된 transaction을 analysis port로 Scoreboard에 전달
                            send.write(t);

                            // 다음 DMA 전송을 수집할 새 transaction 객체 생성
                            t = dma_tx::type_id::create("t");
                        end
                    end
                endcase
            end
        end
    endtask
endclass
