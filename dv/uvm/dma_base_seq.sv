// ============================================================================
// dma_base_seq.sv - DMA Base Sequence
//
// - DMA transaction 생성과 randomization을 수행하는 기본 sequence.
// - 개별 시나리오 sequence가 상속할 공통 실행 구조를 제공.
// ============================================================================

class dma_base_seq extends uvm_sequence #(dma_tx);
    `uvm_object_utils(dma_base_seq)

    function new(input string name = "dma_base_seq");
        super.new(name);
    endfunction

    // [body] : 기본 DMA transaction 한 건 생성
    virtual task body();
        dma_tx t;

        t = dma_tx::type_id::create("t");

        start_item(t);

        if (!t.randomize()) begin
            `uvm_fatal("BASE_SEQ", "Failed to randomize dma_tx in dma_base_seq")
        end

        finish_item(t);

        `uvm_info(
            "BASE_SEQ",
            $sformatf("Generated Transaction: %s", t.convert2string()),
            UVM_HIGH
        )
    endtask
endclass
