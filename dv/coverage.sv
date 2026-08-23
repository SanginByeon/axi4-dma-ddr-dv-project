// ============================================================================
// coverage.sv - Functional Coverage Model
//
// - Baseline testbench 내부 covergroup의 별도 파일 분리.
// - 기존 coverpoint, bin, cross 및 sampling 조건을 동일하게 유지함.
// - Testbench 구조 분리 전후의 coverage 결과 일치 여부 확인 완료.
// ============================================================================

covergroup cg_dma_coverage @(posedge tb.clk); // 샘플 시점: tb.clk 상승엣지
    option.per_instance = 1;                  // 인스턴스 단위로 독립 집계
    option.name = "DMA_System_Coverage";      // 리포트 식별용 이름

    // [전송 크기 분포] : 의미 있는 구간으로 나눠 corner 포함
    cp_size: coverpoint tb.dma_ctrl.size_reg
        iff (tb.resetn && tb.dma_ctrl.size_reg != 0) {
        bins sz_tiny   = {[1:16]};       // 매우 작은 전송(경계 확인)
        bins sz_small  = {[17:256]};     // 소형
        bins sz_medium = {[257:4096]};   // 중형
        bins sz_large  = {[4097:65536]}; // 대형(멀티버스트/정렬 영향 큼)
    }

    // [상태 분포] : 설계 dbg_state를 정수로 캐스팅하여 구간화
    cp_dma_state: coverpoint int'(tb.dma_ctrl.dbg_state) {
        bins idle = {0};
        bins setup = {1};
        bins read_phases = {[2:3]};  // READ_ADDR/READ_DATA 단계
        bins write_phases = {[4:6]}; // WRITE_ADDR/WRITE_DATA/WRITE_RESP 단계
        bins next_burst = {7};
        bins complete = {8};
        bins error = {9};
    }

    // [정렬 여부] : 주소 하위2비트로 4B 정렬 판정
    cp_src_alignment: coverpoint tb.dma_ctrl.src_reg[1:0] iff (tb.resetn) {
        bins aligned = {2'b00};             // 4B 정렬
        bins unaligned = {[2'b01:2'b11]};  // 비정렬(정렬기/마스크 로직 검증)
    }

    cp_dst_alignment: coverpoint tb.dma_ctrl.dst_reg[1:0] iff (tb.resetn) {
        bins aligned = {2'b00};
        bins unaligned = {[2'b01:2'b11]};
    }

    // [버스트 길이 분포] : 관측 신호 dbg_burst_len 활용(AXI len=0 → 1 beat)
    cp_burst_len: coverpoint tb.dma_ctrl.dbg_burst_len iff (tb.resetn) {
        bins single = {0};   // 1 beat
        bins short = {[1:3]}; // 2~4 beats
        bins med = {[4:15]};  // 5~16 beats(예)
    }

    // [상태 전이 시퀀스] : 정상 플로우 & 멀티버스트 재진입 루프
    cp_state_transitions: coverpoint int'(tb.dma_ctrl.dbg_state) iff (tb.resetn) {
        bins normal_flow = (0 => 1 => 2 => 3 => 4 => 5 => 6 => 8); // IDLE→...→COMPLETE
        bins multi_burst = (6 => 7 => 1);                          // RESP→NEXT_BURST→SETUP
    }

    // [교차] : 대형 & 비정렬은 불법 상태로 지정(설계 제약 위반/테스트 금지)
    cx_size_alignment: cross cp_size, cp_src_alignment {
        illegal_bins large_unaligned = binsof(cp_size.sz_large) && binsof(cp_src_alignment.unaligned);
    }
endgroup
