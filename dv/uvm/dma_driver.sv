// ============================================================================
// dma_driver.sv - DMA UVM Driver
//
// - Sequence로부터 DMA transaction을 받아 MMIO register에 설정값을 기록.
// - Transaction별 backpressure와 BRESP 오류 주입 설정을 DDR memory model에 전달.
// - DMA 완료 또는 오류를 기다린 후 status와 전송 바이트 수를 확인.
// - MMIO task는 utility_pkg를 통해 호출.
// ============================================================================

import utility_pkg::*;

class dma_driver extends uvm_driver #(dma_tx);
    `uvm_component_utils(dma_driver)

    // [DMA register map]
    localparam logic [7:0] DMA_CTRL_REG       = 8'h00;
    localparam logic [7:0] DMA_STAT_REG       = 8'h04;
    localparam logic [7:0] DMA_SRC_ADDR_REG   = 8'h08;
    localparam logic [7:0] DMA_DST_ADDR_REG   = 8'h0C;
    localparam logic [7:0] DMA_SIZE_REG       = 8'h10;
    localparam logic [7:0] DMA_BYTES_DONE_REG = 8'h14;

    dma_tx req;
    virtual mmio_if.tb_mp mif;
    virtual axi4_if aif;
    virtual ddr_model_if dif;

    function new(input string name = "dma_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // [reset_phase] : Reset 구간 동안 MMIO 출력 초기화
    virtual task reset_phase(uvm_phase phase);
        phase.raise_objection(this);

        wait (aif.aresetn == 1'b0); // 리셋 활성화 대기

        mif.dma_reg_write <= 1'b0;
        mif.dma_reg_addr  <= '0;
        mif.dma_reg_wdata <= '0;
        dif.backpressure_prob <= '0;
        dif.error_inject <= 1'b0;

        wait (aif.aresetn == 1'b1); // 리셋 비활성화 대기

        repeat (2) @(posedge mif.clk); // 리셋 비활성화 직후 안정화

        `uvm_info("DRV", "Reset phase done", UVM_MEDIUM)
        phase.drop_objection(this);
    endtask

    // [build_phase] : Transaction과 virtual interface 준비
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        req = dma_tx::type_id::create("req");

        if (!uvm_config_db #(virtual mmio_if.tb_mp)::get(this, "", "mif", mif))
            `uvm_fatal("DRV", "Unable to get mif from uvm_config_db");

        utility_pkg::mif = this.mif;

        if (!uvm_config_db #(virtual axi4_if)::get(this, "", "aif", aif))
            `uvm_fatal("DRV", "Unable to get aif from uvm_config_db");

        if (!uvm_config_db #(virtual ddr_model_if)::get(this, "", "dif", dif))
            `uvm_fatal("DRV", "Unable to get dif from uvm_config_db");
    endfunction

    // [run_phase] : Sequence item을 MMIO stimulus로 변환하여 DUT 구동
    virtual task run_phase(uvm_phase phase);
        bit [31:0] ctrl_reg_value;
        bit [31:0] status;
        int timeout_cycles;
        int word_count;
        int stall_wait_budget;

        super.run_phase(phase);

        forever begin
            // 다음 transaction을 받기 전에 CTRL 조합값 초기화
            ctrl_reg_value = 0;

            // Sequencer에서 transaction을 받아 MMIO stimulus 시작
            seq_item_port.get_next_item(req);
            `uvm_info("DRV", $sformatf("Start %s", req.convert2string()), UVM_MEDIUM)

            // DMA 설정 전에 DDR memory model의 backpressure와 BRESP 오류 설정 적용
            dif.backpressure_prob <= req.backpressure_prob;
            dif.error_inject <= req.error_inject;

            // DMA 시작 전에 source/destination 주소와 전송 크기 설정
            write_dma_reg(DMA_SRC_ADDR_REG, req.src_addr); // SRC_ADDR
            write_dma_reg(DMA_DST_ADDR_REG, req.dst_addr); // DST_ADDR
            write_dma_reg(DMA_SIZE_REG, req.size);         // SIZE

            // Transaction의 enable/start/irq 값을 CTRL 하위 비트로 조합
            if (req.enable)
                ctrl_reg_value |= (1 << 0); // 비트 0: enable
            if (req.start)
                ctrl_reg_value |= (1 << 1); // 비트 1: start
            if (req.irq)
                ctrl_reg_value |= (1 << 2); // 비트 2: irq_en

            // CTRL을 마지막에 기록하여 설정된 주소와 크기로 DMA 전송 시작
            write_dma_reg(DMA_CTRL_REG, ctrl_reg_value); // CTRL: enable/start/irq

            // Interrupt를 우선 기다리고 STATUS polling으로 완료 상태를 보조 확인
            // 전송 크기와 backpressure 확률을 반영해 정상적인 stall 지연을 허용
            word_count = (req.size + 3) / 4;
            // 평균 W handshake 대기값 100/(100-p)에 4배 여유 적용
            stall_wait_budget = 400 / (100 - req.backpressure_prob);
            timeout_cycles = 500 + (word_count * (8 + stall_wait_budget));
            wait_dma_completion(timeout_cycles); // 인터럽트/오류/타임아웃 중 하나 포착
            wait_done_via_status();               // 보조 확인(STATUS 폴링)

            // STATUS의 error/done 비트를 기준으로 개별 transaction 결과 판정
            read_dma_reg(DMA_STAT_REG, status); // STATUS 읽기

            if (status[2])
                `uvm_error("DRV", $sformatf("%s FAILED. DUT reported an error.", req.scenario_name))
            else if (status[1])
                `uvm_info("DRV", $sformatf("%s PASSED", req.scenario_name), UVM_MEDIUM)
            else
                `uvm_error("DRV", $sformatf("%s FAILED. Timeout occurred.", req.scenario_name))

            // DUT가 기록한 실제 전송 바이트 수 확인
            read_dma_reg(DMA_BYTES_DONE_REG, status); // BYTES_TRANSFERRED
            `uvm_info("DRV", $sformatf("Bytes transferred: %0d", status), UVM_HIGH)

            // 다음 transaction에 backpressure 및 error injection 설정이 누출되지 않도록 복구
            dif.backpressure_prob <= '0;
            dif.error_inject <= 1'b0;

            // 현재 transaction 처리를 완료하고 다음 item 요청 허용
            seq_item_port.item_done();
        end
    endtask
endclass
