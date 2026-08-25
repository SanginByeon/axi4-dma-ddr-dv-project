// ============================================================================
// dma_s3_seq.sv - DMA Scenario 3 Sequences
//
// - 16-byte 전송에는 90% backpressure를 적용해 강한 W channel stall을 생성.
// - 64-byte 전송에는 BRESP SLVERR를 단독 주입해 오류 응답 경로를 확인.
// ============================================================================

import utility_pkg::*;

class dma_s3_1_seq extends dma_base_seq;
    `uvm_object_utils(dma_s3_1_seq)

    function new(input string name = "dma_s3_1_seq");
        super.new(name);
    endfunction

    // [body] : 90% backpressure가 적용된 16-byte 소형 복사 transaction 생성
    virtual task body();
        dma_tx t;

        t = dma_tx::type_id::create("t");

        start_item(t);

        if (!t.randomize() with {
            src_addr == 32'h0000_0200; // SRC_ADDR=0x0200
            dst_addr == 32'h0000_0300; // DST_ADDR=0x0300
            size     == 16;            // SIZE=0x10(16B)

            // CTRL 설정
            enable == 1'b1;
            start  == 1'b1;
            irq    == 1'b1;

            // DDR memory model 검증 조건
            backpressure_prob == 90;
            error_inject      == 1'b0;
        }) begin
            `uvm_fatal("S3_1_SEQ", "Failed to randomize dma_tx in dma_s3_1_seq")
        end

        // Scenario 이름 설정
        t.scenario_name = "16B Transfer with 90% Backpressure (S3_1)";

        // Source memory를 32'hCAFE_0000 기반 pattern으로 초기화
        preload_src_mem(t.src_addr, t.data_payload);

        finish_item(t);

        `uvm_info(
            "S3_1_SEQ",
            $sformatf("Generated S3_1 Transaction: %s", t.convert2string()),
            UVM_HIGH
        )
    endtask
endclass

class dma_s3_2_seq extends dma_base_seq;
    `uvm_object_utils(dma_s3_2_seq)

    function new(input string name = "dma_s3_2_seq");
        super.new(name);
    endfunction

    // [body] : BRESP SLVERR가 주입되는 64-byte 복사 transaction 생성
    virtual task body();
        dma_tx t;

        t = dma_tx::type_id::create("t");

        start_item(t);

        if (!t.randomize() with {
            src_addr == 32'h0000_0210; // SRC_ADDR=0x0210
            dst_addr == 32'h0000_0310; // DST_ADDR=0x0310
            size     == 64;            // SIZE=0x40(64B)

            // CTRL 설정
            enable == 1'b1;
            start  == 1'b1;
            irq    == 1'b1;

            // DDR memory model 검증 조건
            backpressure_prob == 0;
            error_inject      == 1'b1;
        }) begin
            `uvm_fatal("S3_2_SEQ", "Failed to randomize dma_tx in dma_s3_2_seq")
        end

        // Scenario 이름 설정
        t.scenario_name = "64B Transfer with BRESP SLVERR (S3_2)";

        // Source memory를 32'hCAFE_0000 기반 pattern으로 초기화
        preload_src_mem(t.src_addr, t.data_payload);

        finish_item(t);

        `uvm_info(
            "S3_2_SEQ",
            $sformatf("Generated S3_2 Transaction: %s", t.convert2string()),
            UVM_HIGH
        )
    endtask
endclass
