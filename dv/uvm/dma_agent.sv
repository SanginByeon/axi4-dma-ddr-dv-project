// ============================================================================
// dma_agent.sv - DMA UVM Agent
//
// - 상속받은 UVM active/passive 설정에 따라 Agent 구성을 결정.
// - Monitor는 항상 생성하고, Active mode에서 Driver와 Sequencer를 생성·연결.
// ============================================================================

class dma_agent extends uvm_agent;
    `uvm_component_utils(dma_agent)

    dma_driver drv;
    dma_monitor mon;
    uvm_sequencer #(dma_tx) seqr;

    function new(input string name = "dma_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // [build_phase] : Monitor는 항상 생성하고, active mode에서 Driver/Sequencer 생성
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        mon = dma_monitor::type_id::create("mon", this);

        // Active mode일 때만 Driver와 Sequencer 생성
        if (get_is_active() == UVM_ACTIVE) begin
            drv = dma_driver::type_id::create("drv", this);
            seqr = uvm_sequencer #(dma_tx)::type_id::create("seqr", this);
        end
    endfunction

    // [connect_phase] : Active mode에서 Driver와 Sequencer의 TLM port 연결
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(seqr.seq_item_export);
        end
    endfunction
endclass
