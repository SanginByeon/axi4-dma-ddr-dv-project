// ============================================================================
// dma_s2_seq.sv - DMA Scenario 2 Sequence
//
// - 4-byte 정렬 주소에서 1,024-byte 대용량 복사를 수행.
// - Multi-burst 전송 경로와 AXI4 응답 sequence를 확인할 transaction을 생성.
// ============================================================================

import utility_pkg::*;

class dma_s2_seq extends dma_base_seq;
    `uvm_object_utils(dma_s2_seq)

    function new(input string name = "dma_s2_seq");
        super.new(name);
    endfunction

    // [body] : 1,024-byte multi-burst transaction 생성 및 source memory 초기화
    virtual task body();
        dma_tx t;

        t = dma_tx::type_id::create("t");

        start_item(t);

        if (!t.randomize() with {
            src_addr == 32'h0000_0100; // SRC_ADDR=0x0100
            dst_addr == 32'h0000_0800; // DST_ADDR=0x0800
            size     == 1024;          // SIZE=0x400(1024B)

            // CTRL 설정
            enable == 1'b1;
            start  == 1'b1;
            irq    == 1'b1;
        }) begin
            `uvm_fatal("S2_SEQ", "Failed to randomize dma_tx in dma_s2_seq")
        end

        // Scenario 이름 설정
        t.scenario_name = "1024B Large Transfer (S2)";

        // Source memory를 32'hCAFE_0000 기반 pattern으로 초기화
        preload_src_mem(t.src_addr, t.data_payload);

        finish_item(t);

        `uvm_info(
            "S2_SEQ",
            $sformatf("Generated S2 Transaction: %s", t.convert2string()),
            UVM_HIGH
        )
    endtask
endclass
