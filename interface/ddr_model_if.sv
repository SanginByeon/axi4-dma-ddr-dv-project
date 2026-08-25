// ============================================================================
// ddr_model_if.sv - DDR Memory Model Control Interface
//
// - UVM Driver가 DDR memory model의 검증 조건을 설정하기 위한 interface.
// - AXI4 W channel의 random backpressure 확률과 BRESP 오류 주입 설정을 전달.
// - DUT protocol interface가 아닌 검증용 memory model 제어 신호를 제공.
// ============================================================================

interface ddr_model_if(input logic aclk, aresetn);

    // [Backpressure control] : WREADY를 비활성화할 확률(0~99%)
    logic [7:0] backpressure_prob;

    // [BRESP error injection] : 1이면 write response로 SLVERR 반환
    logic error_inject;

endinterface
