// ============================================================================
// mmio_if.sv - MMIO interface
//
// - Testbench와 DMA controller 사이의 MMIO 레지스터 접근 신호 및
//   완료·오류 인터럽트 신호를 하나로 묶은 SystemVerilog interface.
// ============================================================================

interface mmio_if(input logic clk);

    // [MMIO 신호] : tb가 소프트웨어처럼 DMA 레지스터 접근
    logic [7:0]  dma_reg_addr;   // 대상 레지스터 주소
    logic [31:0] dma_reg_wdata;  // 쓰기 데이터
    logic [31:0] dma_reg_rdata;  // 읽기 데이터(설계가 제공)
    logic        dma_reg_write;  // 1이면 write, 0이면 read
    logic        dma_reg_ack;    // 접근 완료 응답(ready와 유사)

    // [인터럽트] : 완료/오류 통지
    logic dma_done_int;
    logic dma_error_int;

    modport tb_mp (
        input clk, dma_reg_rdata, dma_reg_ack, dma_done_int, dma_error_int,
        output dma_reg_addr, dma_reg_wdata, dma_reg_write
    );

    modport dut_mp (
        output dma_reg_rdata, dma_reg_ack, dma_done_int, dma_error_int,
        input clk, dma_reg_addr, dma_reg_wdata, dma_reg_write
    );

endinterface
