// ============================================================================
// dma_s4_slverr_seq.sv - DMA Scenario 4 SLVERR Sequence
//
// - Backpressure 없이 64-byte write burst에 BRESP SLVERR를 단독 주입.
// - S_WR_RESP에서 error_code=0x3과 error interrupt가 발생하는지 확인.
// - Backpressure 결합 시나리오와 분리해 BRESP 오류 경로의 기준점을 제공.
// ============================================================================

import utility_pkg::*;

class dma_s4_slverr_seq extends dma_base_seq;
    `uvm_object_utils(dma_s4_slverr_seq)

    function new(input string name = "dma_s4_slverr_seq");
        super.new(name);
    endfunction

    // [body] : Backpressure 없는 BRESP SLVERR transaction 생성
    virtual task body();
        dma_tx t;

        t = dma_tx::type_id::create("t_s4_id1");

        start_item(t);

        if (!t.randomize() with {
            src_addr == 32'h0000_0200;
            dst_addr == 32'h0000_0A00;
            size     == 64;

            enable == 1'b1;
            start  == 1'b1;
            irq    == 1'b1;

            backpressure_prob == 0;
            error_inject      == 1'b1;
        }) begin
            `uvm_fatal("S4_SEQ", "Failed to randomize S4 transaction ID 1")
        end

        t.scenario_name = "[S4-1] 64B BRESP SLVERR Injection";

        // Source memory를 32'hCAFE_0000 기반 pattern으로 초기화
        preload_src_mem(t.src_addr, t.data_payload);

        finish_item(t);

        `uvm_info(
            "S4_SEQ",
            $sformatf("Generated S4 Transaction: %s", t.convert2string()),
            UVM_HIGH
        )
    endtask
endclass
