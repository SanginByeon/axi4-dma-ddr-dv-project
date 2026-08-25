// ============================================================================
// design.sv - Design Compile Entry
//
// - EDA Playground 시뮬레이션에서 사용하는 design compile entry.
// - AXI4/DDR model interface, DMA controller, DDR memory model을 의존 순서대로 포함.
// - 구현 로직 없이 design source의 compile 순서만 관리.
// ============================================================================

`timescale 1ns/1ps

`include "axi4_if.sv"
`include "ddr_model_if.sv"
`include "dma_controller.sv"
`include "ddr_memory_model.sv"
