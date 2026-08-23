/*******************************************************************************
 * 파일명      : testbench.sv
 * 출처        : 패스트캠퍼스 교육과정
 * 교육과정명    : 삼코치의 반도체 실무 로드맵: 설계 · 검증 · Layout · AI반도체
 * URL    : https://fastcampus.co.kr/data_online_samcoach2
 ******************************************************************************/



`timescale 1ns/1ps
/*======================================================================================================================
[최상위 시스템 그림]
	+-------------------------------- tb --------------------------------+
	| 1) 클록/리셋 생성
	| 2) MMIO 태스크로 DMA 레지스터 제어(write/read)
	| 3) 3개 시나리오 실행 → 완료 확인(인터럽트/폴링) 							  |
	| 4) 무결성 확인 / 성능 / 커버리지 리포트									    |
	| 5) 실시간 모니터링(상태/레지스터/AXI) 									   	|
	|
    |
	| 		+----------------+ 		  AXI4		  +-----------------+
  	| 		| dma_controller | (master) <-------> | ddr_controller 	|
	| 		+----------------+ 					  +-----------------+
	| 				^ 	MMIO(reg_addr/wdata/write/rdata/ack)
	| 				|
	| 			 (tasks)
	+---------------------------------------------------------------------
	+
    
[핵심 데이터/제어 흐름 요약]
	tb →(MMIO)→ dma_controller(SRC/DST/SIZE/CTRL 설정)
	dma_controller →(AXI 읽기/쓰기 버스트)→ ddr_controller
	dma_controller →(인터럽트)→ tb (또는 tb가 STATUS 폴링)
	tb →(무결성/성능/커버리지/로그 출력)
    
[MMIO 쓰기/읽기 타이밍(개념)]
	쓰기: (posedge clk) addr,wdata,write=1 → (다음 posedge) write=0 → ack=1 대기 → 완료
	읽기: (posedge clk) addr,write=0 → (추가 2클록 안정화) → rdata 샘플
    
[AXI 주소 채널 핸드셰이크(개념)]
	Write: awvalid & awready 순간에 주소/len 확정 → 이후 wvalid/wready 비트 전송 → bvalid/bready 응답
	Read : arvalid & arready 순간에 주소/len 확정 → 이후 rvalid/rready 데이터 수신
    
[상태 전이(의도)]
	IDLE(0)→SETUP(1)→READ_ADDR(2)→READ_DATA(3)→WRITE_ADDR(4)→WRITE_DATA(5)→WRITE_RESP(6)→
    (멀티버스트면 NEXT_BURST(7)→SETUP(1) 반복)→COMPLETE(8) 또는 ERROR(9)
    
[커버리지 설계 의도]
	- 전송 크기(cp_size): tiny/small/medium/large를 골고루 때려 보기
	- 정렬(cp_src/dst_alignment): 하위2비트로 4B 정렬/비정렬을 판별
	- 버스트 길이(cp_burst_len): 단일~중간 길이까지 관찰
	- 상태/전이(cp_dma_state, cp_state_transitions): 정상 플로우+멀티버스트 루프 확인
	- 교차(cx_size_alignment): "대형 & 비정렬"은 설계 제약 위반(illegal)로 방지
    
[시나리오 실행 순서(타임라인)]
	t=0ns : clk 토글 시작, resetn=0
	t=20ns : resetn=1 → 5클록 안정화
	S1(256B) → S2(1024B) → S3(16B,64B) → 무결성 → 성능 → 커버리지 → 종료
    
[학습 관찰 포인트]
	□ 인터럽트/폴링 모두 제공(둘 중 하나 실패해도 다른 경로로 복구)
	□ 실시간 로그로 상태/레지스터 변화와 AXI 버스트 정보를 눈으로 검증
	□ 커버리지 수치로 테스트 공백(미히트 영역)을 식별 → 시나리오 추가 근거 확보
======================================================================================================================*/

// ============================================================
// Coverage Model : 클록 상승엣지마다 샘플링하며 분포/전이/교차를 포착
// ============================================================
covergroup cg_dma_coverage @(posedge tb.clk); 	// 샘플 시점: tb.clk 상승엣지
	option.per_instance = 1; 					// 인스턴스 단위로 독립 집계
	option.name = "DMA_System_Coverage"; 		// 리포트 식별용 이름
  
	// [전송 크기 분포] : 의미 있는 구간으로 나눠 corner 포함
	cp_size: coverpoint tb.dma_ctrl.size_reg iff (tb.resetn && tb.dma_ctrl.size_reg != 0) { // 리셋 해제 & SIZE≠0일 때만 유효 샘플
    	bins sz_tiny = {[1:16]}; 		// 매우 작은 전송(경계 확인)
    	bins sz_small = {[17:256]}; 	// 소형
    	bins sz_medium = {[257:4096]}; 	// 중형
    	bins sz_large = {[4097:65536]}; // 대형(멀티버스트/정렬 영향 큼)
	}
  
	// [상태 분포] : 설계 dbg_state를 정수로 캐스팅하여 구간화
	cp_dma_state: coverpoint int'(tb.dma_ctrl.dbg_state) {
		bins idle = {0};
		bins setup = {1};
      	bins read_phases = {[2:3]}; // READ_ADDR/READ_DATA 단계
      	bins write_phases= {[4:6]}; // WRITE_ADDR/WRITE_DATA/WRITE_RESP 단계
		bins next_burst = {7};
		bins complete = {8};
		bins error = {9};
	}
  
	// [정렬 여부] : 주소 하위2비트로 4B 정렬 판정
  	cp_src_alignment: coverpoint tb.dma_ctrl.src_reg[1:0] iff(tb.resetn) {
      	bins aligned = {2'b00}; 		  // 4B 정렬
        bins unaligned = {[2'b01:2'b11]}; // 비정렬(정렬기/마스크 로직 검증)
	}
  	cp_dst_alignment: coverpoint tb.dma_ctrl.dst_reg[1:0] iff(tb.resetn) {
		bins aligned = {2'b00};
		bins unaligned = {[2'b01:2'b11]};
	}

  	// [버스트 길이 분포] : 관측 신호 dbg_burst_len 활용(AXI len=0 → 1 beat)
	cp_burst_len: coverpoint tb.dma_ctrl.dbg_burst_len iff(tb.resetn) {
      	bins single = {0}; 	  // 1 beat
      	bins short = {[1:3]}; // 2~4 beats
      	bins med = {[4:15]};  // 5~16 beats(예)
	}
  
	// [상태 전이 시퀀스] : 정상 플로우 & 멀티버스트 재진입 루프
  	cp_state_transitions: coverpoint int'(tb.dma_ctrl.dbg_state) iff(tb.resetn) {
      	bins normal_flow = (0 => 1 => 2 => 3 => 4 => 5 => 6 => 8); // IDLE→...→COMPLETE
      	bins multi_burst = (6 => 7 => 1); 						   // RESP→NEXT_BURST→SETUP
	}

  	// [교차] : 대형 & 비정렬은 불법 상태로 지정(설계 제약 위반/테스트 금지)
	cx_size_alignment: cross cp_size, cp_src_alignment {
		illegal_bins large_unaligned = binsof(cp_size.sz_large) && binsof(cp_src_alignment.unaligned);
	}
endgroup

// ============================================================
// Testbench Top Module : 환경 구성, 시나리오 구동, 리포트/모니터링
// ============================================================
module tb;
  
	logic clk, resetn; // 클록/리셋(활성-로우)

  	// [클록 생성] : 100MHz(주기 10ns) → #5마다 토글
	initial begin
		clk = 0;
		forever #5 clk = ~clk;
	end
  
	// [리셋 시퀀스] : 20ns 동안 resetn=0, 이후 1로 해제(동기화 호환)
	initial begin
		resetn = 0;
		#20 resetn = 1;
	end

  	// [MMIO 신호] : tb가 소프트웨어처럼 DMA 레지스터 접근
	logic [7:0] dma_reg_addr; 	// 대상 레지스터 주소
	logic [31:0] dma_reg_wdata; // 쓰기 데이터
	logic [31:0] dma_reg_rdata; // 읽기 데이터(설계가 제공)
	logic dma_reg_write; 		// 1이면 write, 0이면 read
	logic dma_reg_ack; 			// 접근 완료 응답(ready와 유사)

  	// [인터럽트] : 완료/오류 통지
	logic dma_done_int;
	logic dma_error_int;

  	// [디버그] : 내부 관측용(상태/버스트/버퍼)
	logic [3:0] dbg_state;
	logic [7:0] dbg_burst_len;
	logic [4:0] dbg_buf_count;

  	// [AXI 배선] : 공용 버스 인터페이스 인스턴스(클록/리셋 연결)
	axi4_if memory_axi(.aclk(clk), .aresetn(resetn));

  	// [DDR 컨트롤러] : AXI Slave로 동작(메모리 모델 대체)
	ddr_controller ddr_ctrl (
		.axi(memory_axi.slave)
	);

  	// [DMA 컨트롤러] : AXI Master로 메모리에 접근
	dma_controller dma_ctrl (
		.clk (clk),
		.resetn (resetn),
      
		.reg_addr (dma_reg_addr),
		.reg_wdata (dma_reg_wdata),
		.reg_write (dma_reg_write),
		.reg_rdata (dma_reg_rdata),
		.reg_ack (dma_reg_ack),
      
		.m (memory_axi.master),
      
		.dma_done_int (dma_done_int),
		.dma_error_int (dma_error_int),
      
		.dbg_state (dbg_state),
		.dbg_burst_len (dbg_burst_len),
		.dbg_buf_count (dbg_buf_count)
	);
  
	// [커버리지 인스턴스] : 생성 즉시 클록마다 샘플링 시작
	cg_dma_coverage cov_inst = new();
  
	// [메인 시퀀스] : 파형 덤프 → 안정화 → 3시나리오 → 검증/리포트 → 종료
	initial begin
      	$dumpfile("dma_ddr_system.vcd"); // 파형 파일명
      	$dumpvars(0, tb); 				 // tb 하위 전체 덤프
		dma_reg_write <= 0;				 // 기본값 초기화
      	wait(resetn);					 // 리셋 해제 기다림
		repeat(5) @(posedge clk);		 // 안정화용 5클록
      
		$display("\n============================================================");
		$display(" DMA-DDR Memory System Comprehensive Test Started");
		$display("============================================================");
		$display("Start time: %0t ns", $time);
      
		// [시나리오] : 크기/정렬/버스트/전이를 다양하게 자극
      	test_scenario_1_basic_copy();		  // 256B 기본 복사(정렬/정상 플로우)
      	test_scenario_2_large_transfer();	  // 1024B 대용량(멀티버스트 가능)
		test_scenario_3_burst_optimization(); // 16B/64B(짧은 전송 거동)

		// [검증/리포트] : 데이터 무결성 → 성능 → 커버리지
		verify_data_integrity();
		analyze_performance();
		generate_coverage_report();
      
		$display("\n============================================================");
		$display(" Test Completed Successfully");
		$display("============================================================");
		#100 $finish; // 로그 마무리 여유 후 종료
	end
  
	// -------------------------
	// 유틸리티 태스크 : 재사용 가능한 MMIO/대기/폴링 도우미
	// -------------------------
	// [MMIO 쓰기] : posedge 정렬 → 한 클록 유지 → ack 대기 → 로그
	task write_dma_reg(input [7:0] addr, input [31:0] data);
		@(posedge clk);
		dma_reg_addr <= addr;  // 주소 제시
      	dma_reg_wdata <= data; // 데이터 제시
      
      	dma_reg_write <= 1;    // write 활성
      	@(posedge clk); 	   // 한 클록 유지(슬레이브 래칭 여유)
      	dma_reg_write <= 0;	   // write 비활성
      	wait(dma_reg_ack);	   // 설계로부터 완료 응답 대기
        $display("[%6.1f ns] REG[0x%02X] <- 0x%08X", real'($time)/1000.0, addr, data); // 추적 로그
	endtask

	// [MMIO 읽기] : 주소 제시 → 2클록 안정화 → rdata 샘플 → 로그
	task read_dma_reg(input [7:0] addr, output [31:0] data);
		@(posedge clk);
		dma_reg_addr <= addr; // 주소 제시
      	dma_reg_write <= 0;	  // read 모드
      	@(posedge clk);		  // 1클록 여유(파이프라인/복합 경로)
      	@(posedge clk);		  // 추가 1클록(메타/지연 흡수)
		data = dma_reg_rdata; // 읽은 데이터 채취
      	$display("[%6.1f ns] REG[0x%02X] -> 0x%08X", real'($time)/1000.0, addr, data); // 추적 로그
	endtask
  
	// [DMA 완료 대기] : 완료/오류/타임아웃 중 첫 사건을 에지 기반으로 포착
	task wait_dma_completion(input int timeout_cycles = 1000);
      	$display("[%6.1f ns] Waiting for DMA completion...", real'($time)/1000.0);
		fork
			begin
				@(posedge dma_done_int); // 완료 인터럽트 상승엣지
          		$display("[%6.1f ns] DMA completion interrupt received!", real'($time)/1000.0);
			end
			begin
				@(posedge dma_error_int); // 오류 인터럽트 상승엣지
          		$display("[%6.1f ns] DMA error interrupt occurred!", real'($time)/1000.0);
			end
			begin
          		repeat(timeout_cycles) @(posedge clk); // 타임아웃 카운터
          		$display("[%6.1f ns] DMA timeout after %0d cycles", real'($time)/1000.0, timeout_cycles);
			end
		join_any 	  // 첫 완료 후 합류

		disable fork; // 나머지 스레드 종료(리소스 누수 방지)
	endtask
          
	// [STATUS 폴링] : 인터럽트가 없거나 놓쳤을 때 보조 경로로 완료 확인
	task wait_done_via_status(input int max_tries = 20);
		int i;
		logic [31:0] s;
		for (i = 0; i < max_tries; i++) begin
          	read_dma_reg(8'h04, s); // STATUS(가정 주소 0x04)
          	if (s[1]) return;	    // done 비트=1이면 즉시 복귀
          	@(posedge clk);		    // 다음 폴링까지 1클록 대기
		end
		$display("STATUS polling timeout (done=0)"); // 폴링 타임아웃 알림
	endtask
          
	// -------------------------
	// 테스트 시나리오 : 설정→시작→완료확인 의 표준 패턴
	// -------------------------
          
	// [S1: 256B 기본 복사] : 정렬 주소, 정상 플로우/완료 신호 확인
	task test_scenario_1_basic_copy();
		logic [31:0] status;
		$display("\n--- Scenario 1: Basic Memory Copy (256 bytes) ---");
      	write_dma_reg(8'h08, 32'h00000000); // SRC_ADDR=0x0000
		write_dma_reg(8'h0C, 32'h00000400); // DST_ADDR=0x0400(1KB 오프셋)
      	write_dma_reg(8'h10, 32'h00000100); // SIZE=0x100(256B)
      	write_dma_reg(8'h00, 32'h00000007); // CTRL: enable/start/irq(가정)
      	wait_dma_completion(500);		    // 인터럽트/오류/타임아웃 중 하나 포착
      
      	wait_done_via_status();							   // 보조 확인(STATUS 폴링)
      	read_dma_reg(8'h04, status); 					   // STATUS 읽기
      	if (status[1]) $display("Basic copy test passed"); // done=1이면 성공
      	else $display("Basic copy test failed");		   // 아니면 실패

      	read_dma_reg(8'h14, status); 				 // BYTES_TRANSFERRED(가정: 0x14)
		$display(" Bytes transferred: %0d", status); // 실제 전송량 로깅
	endtask
          
	// [S2: 1024B 대용량] : 버스트/멀티버스트 경로 및 응답 시퀀스 관찰
	task test_scenario_2_large_transfer();
		$display("\n--- Scenario 2: Large Transfer (1024 bytes) ---");
      	write_dma_reg(8'h08, 32'h00000100);   // SRC_ADDR=0x0100
      	write_dma_reg(8'h0C, 32'h00000800);   // DST_ADDR=0x0800
      	write_dma_reg(8'h10, 32'h00000400);   // SIZE=0x400(1024B)
      	write_dma_reg(8'h00, 32'h00000007);   // CTRL 시작
      	wait_dma_completion(800);		      // 여유 타임아웃
		$display("Large transfer completed"); // 완료 로그
	endtask
          
	// [S3: 16B/64B] : 작은 전송에서 len/handshake, 오버헤드/최적화 관찰
	task test_scenario_3_burst_optimization();
		$display("\n--- Scenario 3: Burst Optimization for Various Sizes---");
		$display(" 3-1. Small transfer (16 bytes)");
      	write_dma_reg(8'h08, 32'h00000200); // SRC_ADDR=0x0200
      	write_dma_reg(8'h0C, 32'h00000300); // DST_ADDR=0x0300
		write_dma_reg(8'h10, 32'h00000010); // SIZE=16B
		write_dma_reg(8'h00, 32'h00000007); // 시작
		wait_dma_completion(200);
      
		$display(" 3-2. Medium transfer (64 bytes)");
      	write_dma_reg(8'h08, 32'h00000210); // SRC_ADDR=0x0210
      	write_dma_reg(8'h0C, 32'h00000310); // DST_ADDR=0x0310
		write_dma_reg(8'h10, 32'h00000040); // SIZE=64B
		write_dma_reg(8'h00, 32'h00000007); // 시작
		wait_dma_completion(300);
      
		$display("Burst optimization tests completed");
	endtask
          
	// -------------------------
	// 데이터 무결성 검증 : 간단 샘플 비교(확장 가능)
	// -------------------------
	task automatic verify_data_integrity();
		automatic int error_count = 0; // 에러 누계
      	logic [31:0] src_data, dst_data;
      
		$display("\n--- Data Integrity Verification ---");
		for (int i = 0; i < 8; i++) begin 		// 예: 8워드만 샘플 검증
          	src_data = ddr_ctrl.mem[i]; 		// 소스 워드 i
          	dst_data = ddr_ctrl.mem[256 + i]; 	// 목적지 워드(0x400=1024B → 워드 오프셋 256)
          	if (src_data == dst_data)
				$display(" [%2d] Match: 0x%08X", i, src_data);
			else begin
              	$display(" [%2d] Mismatch: src=0x%08X, dst=0x%08X", i, src_data, dst_data);
				error_count++;
			end
		end
      
      	if (error_count == 0)
          	$display("All data transferred correctly!");
		else
          	$display("Found %0d data mismatches", error_count);
	endtask
          
	// -------------------------
	// 성능 분석 : 총 전송량/총 시뮬레이션 시간으로 대략적 Mbps 산출
	// -------------------------
	task analyze_performance();
		real total_time_ns, throughput_mbps;
		int total_cycles;

		$display("\n--- Performance Analysis ---");
      	total_time_ns = real'($time); 						// 현재까지 경과 시간(ns)
      	total_cycles = int'(total_time_ns / 10.0); 			// 100MHz → 10ns/사이클
		throughput_mbps =
      		(256.0 + 1024.0 + 16.0 + 64.0) * 8.0 / 			// 총 비트 수
      		total_time_ns * 1000.0; 						// ns→us 보정(대략적)

      	$display(" Total execution time: %0.1f ns (%0d cycles)", total_time_ns, total_cycles);
		$display(" Estimated throughput: %0.2f Mbps", throughput_mbps);

      	if (throughput_mbps > 100.0)
          	$display(" Excellent performance");
		else if (throughput_mbps > 50.0)
          	$display(" Good performance");
      	else
          	$display(" Performance improvement needed");
	endtask
          
	// -------------------------
	// 커버리지 리포트 : 항목별/전체 요약 출력
	// -------------------------
	task generate_coverage_report();
		real total_coverage;
		real size_cov, state_cov, align_cov, cross_cov;
      
		$display("\n--- Coverage Analysis Report ---");
      	total_coverage = cov_inst.get_coverage(); 				// 전체 %
      	size_cov = cov_inst.cp_size.get_coverage(); 			// 크기 분포 %
      	state_cov = cov_inst.cp_dma_state.get_coverage(); 		// 상태 분포 %
      	align_cov = (cov_inst.cp_src_alignment.get_coverage() + cov_inst.cp_dst_alignment.get_coverage()) / 2.0; // 정렬 평균 %
      	cross_cov = cov_inst.cx_size_alignment.get_coverage(); 	// 교차 %

      	$display(" Overall Coverage: %6.2f%%", total_coverage);
		$display(" Transfer Size Pattern: %6.2f%%", size_cov);
		$display(" DMA State Transition: %6.2f%%", state_cov);
		$display(" Address Alignment: %6.2f%%", align_cov);
		$display(" Cross Scenario: %6.2f%%", cross_cov);
      
      	if (total_coverage >= 90.0)
          	$display(" Excellent Coverage - Very good test quality");
      	else if (total_coverage >= 75.0)
          	$display(" Good Coverage - Additional tests recommended");
      	else
          	$display(" Insufficient Coverage - More test scenarios needed");
	endtask
          
	// -------------------------
	// 실시간 모니터링 : 상태/레지스터/AXI 활동 로그
	// -------------------------
	logic [3:0] prev_state = 4'hF; // 직전 상태 기록(초기 미정)
          
	// [상태 변화] : dbg_state가 바뀔 때마다 사람이 읽기 쉬운 문자열로 로그
	always @(posedge clk) begin
		if (dbg_state != prev_state && resetn) begin
          	$display("[%6.1f ns] DMA State: %s", real'($time)/1000.0, get_dma_state_name(dbg_state));
			prev_state <= dbg_state;
		end
	end
          
	// [start_active 변화] : 시작 조건 토글 모니터링(플로우 디버깅에 유용)
	logic prev_start_active = 1'b0;
	always @(posedge clk) begin
		if (dma_ctrl.start_active != prev_start_active && resetn) begin
          	$display("[%6.1f ns] start_active changed: %0b -> %0b", real'($time)/1000.0, prev_start_active, dma_ctrl.start_active);
			prev_start_active <= dma_ctrl.start_active;
		end
	end

	// [제어 레지스터 변화] : 비트 단위 비교를 위해 캐스팅, 핵심 필드만 요약 로그
	logic [31:0] prev_ctrl = 32'h0;
	always @(posedge clk) begin
		if (logic'(dma_ctrl.ctrl) != prev_ctrl && resetn) begin
          	$display("[%6.1f ns] Control register changed: enable=%0b, start=%0b", real'($time)/1000.0, dma_ctrl.ctrl.enable, dma_ctrl.ctrl.start);
			prev_ctrl <= logic'(dma_ctrl.ctrl);
		end
	end
          
	// [AXI 주소 채널] : aw/ar 핸드셰이크 성사 시 어드레스/beat 수를 기록
	always @(posedge clk) begin
		if (memory_axi.awvalid && memory_axi.awready) begin
          	$display("[%6.1f ns] AXI Write: 0x%08X, %0d beats", real'($time)/1000.0, memory_axi.awaddr, memory_axi.awlen + 1);
		end
		if (memory_axi.arvalid && memory_axi.arready) begin
          	$display("[%6.1f ns] AXI Read: 0x%08X, %0d beats", real'($time)/1000.0, memory_axi.araddr, memory_axi.arlen + 1);
		end
	end
          
	// [상태 코드 → 이름] : 로그 가독성 향상용 매핑
	function string get_dma_state_name(input [3:0] s);
		case (s)
			4'h0: return "IDLE";
			4'h1: return "SETUP";
			4'h2: return "READ_ADDR";
			4'h3: return "READ_DATA";
			4'h4: return "WRITE_ADDR";
			4'h5: return "WRITE_DATA";
			4'h6: return "WRITE_RESP";
			4'h7: return "NEXT_BURST";
			4'h8: return "COMPLETE";
			4'h9: return "ERROR";
			default: return "UNKNOWN";
		endcase
	endfunction
endmodule