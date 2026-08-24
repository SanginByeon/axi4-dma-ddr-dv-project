// ============================================================================
// dma_env.sv - DMA UVM Environment
//
// - DMA agent와 scoreboard를 생성하는 최상위 UVM environment.
// - Monitor의 analysis port를 scoreboard의 analysis export에 연결.
// ============================================================================

class dma_env extends uvm_env;
    `uvm_component_utils(dma_env)

    dma_scoreboard scb;
    dma_agent a;

    function new(input string name = "dma_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // [build_phase] : Agent와 Scoreboard 생성
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        scb = dma_scoreboard::type_id::create("scb", this);
        a = dma_agent::type_id::create("a", this);
    endfunction

    // [connect_phase] : Monitor의 analysis port를 Scoreboard에 연결
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        a.mon.send.connect(scb.recv);
    endfunction
endclass
