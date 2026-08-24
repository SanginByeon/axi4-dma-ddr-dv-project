// ============================================================================
// dma_s1_seq.sv - DMA Scenario 1 Sequence
//
// - 4-byte 정렬 주소에서 256-byte 기본 복사를 수행.
// - 정상 전송 흐름과 완료 신호를 확인하기 위한 transaction을 생성.
// ============================================================================

import utility_pkg::*;

class dma_s1_seq extends dma_base_seq;
    `uvm_object_utils(dma_s1_seq)

    function new(input string name = "dma_s1_seq");
        super.new(name);
    endfunction

    // [body] : 256-byte 기본 복사 transaction 생성 및 source memory 초기화
    virtual task body();
        dma_tx t;

        t = dma_tx::type_id::create("t");

        start_item(t);

        if (!t.randomize() with {
            src_addr == 32'h0000_0000; // SRC_ADDR=0x0000
            dst_addr == 32'h0000_0400; // DST_ADDR=0x0400(1KB 오프셋)
            size     == 256;           // SIZE=0x100(256B)

            // CTRL 설정
            enable == 1'b1;
            start  == 1'b1;
            irq    == 1'b1;
        }) begin
            `uvm_fatal("S1_SEQ", "Failed to randomize dma_tx in dma_s1_seq")
        end

        // Scenario 이름 설정
        t.scenario_name = "256B Basic copy (S1)";

        // Source memory를 32'hCAFE_0000 기반 pattern으로 초기화
        preload_src_mem(t.src_addr, t.data_payload);

        finish_item(t);

        `uvm_info(
            "S1_SEQ",
            $sformatf("Generated S1 Transaction: %s", t.convert2string()),
            UVM_HIGH
        )
    endtask
endclass
