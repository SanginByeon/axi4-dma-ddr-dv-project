/*******************************************************************************
 * 파일명      : design.sv
 * 출처        : 패스트캠퍼스 교육과정
 * 교육과정명    : 삼코치의 반도체 실무 로드맵: 설계 · 검증 · Layout · AI반도체
 * URL    : https://fastcampus.co.kr/data_online_samcoach2
 ******************************************************************************/



// ===============================================================
// design.sv — AMBA AXI4 기반 DMA 컨트롤러 + DDR 메모리 모델 + AXI4 인터페이스
//================================================================
//
// ==============================
// [큰 그림: 블록 & 데이터 흐름]
// ==============================
//
// CPU/Host (레지스터 쓰기)
// 		| reg_write/reg_addr/reg_wdata
// 		v
// +-------------------+      AXI4 Master 	   +---------------------+
// | DMA Controller    | ====================> | DDR Controller      |
// | (this module)     | <==================== | (AXI4 Slave + mem)  |
// +-------------------+                       +---------------------+
//          | 											  |
// 			| 				내부 4KB 단순 메모리 			   |
// 			| 				mem[0:1023] 				  |
// 			| 											  |
// 			+--[FIFO 16x32]--(읽기 데이터 임시 보관)--> Write로 배출
//
// - DMA: “읽기 버스트 → FIFO 적재 → 쓰기 버스트”를 반복해 SIZE만큼 복사.
// - DDR: 간단 AXI 슬레이브. R/W 채널 핸드셰이크 + mem[] 접근으로 응답.
//
// =====================================
// [버스트 단위 시퀀스: 절차 요약]
// =====================================
// 1) SETUP: bytes_left 기반으로 burst_len_m1 결정(1/4/16 beats).
// 2) RD_ADDR: cur_src에서 (burst_len_m1+1) beats 읽기 주소 발행(AR).
// 3) RD_DATA: beat마다 r_fire 시 FIFO 적재, cur_src+=4,bytes_left/bytes_done 업데이트.
// 4) WR_ADDR: cur_dst로 (burst_len_m1+1) beats 쓰기 주소 발행(AW).
// 5) WR_DATA: FIFO에서 데이터 꺼내 전송, cur_dst+=4, 마지막 beat 후 RESP 대기.
// 6) WR_RESP: BRESP 확인. 남으면 NEXT→SETUP, 없으면 DONE.
//
// =====================================
// [FSM 개요(상태/전이)]
// =====================================
// IDLE→SETUP→RD_ADDR→RD_DATA→WR_ADDR→WR_DATA→WR_RESP→(NEXT|DONE)
// NEXT→SETUP 반복, 에러 시 ERROR. DONE 후 IDLE.
//
// =====================================
// [레지스터 요약 & 사용법]
// =====================================
// 0x00 CTRL: [2]=irq_en, [1]=start(펄스), [0]=enable, [15:8]=channel_id
// 0x04 STAT: [0]=busy, [1]=done(sticky), [2]=error, [11:8]=error_code
// 0x08 SRC : 소스 시작 주소
// 0x0C DST : 목적지 시작 주소
// 0x10 SIZE: 총 전송 바이트 수(4의 배수 가정)
// 0x14 BYTES: 누적 전송 바이트(bytes_done)
//
// 사용 절차: SRC/DST/SIZE 설정 → CTRL.enable=1, CTRL.start=1 → STAT.done/error 확인.
//
// ---------------------------------------------------------------
`timescale 1ns/1ps // 시뮬레이션 시간 단위/정밀도
// ---------------------------------------------------------------
// AXI4 인터페이스 (필수 신호만)
// ---------------------------------------------------------------
interface axi4_if #(
	parameter ADDR_WIDTH = 32, 	// 주소 폭
	parameter DATA_WIDTH = 32, 	// 데이터 폭
	parameter ID_WIDTH = 4 		// ID 폭
)(input logic aclk, aresetn); 	// 공통 클록/리셋
  
	// Write Address
	logic [ID_WIDTH-1:0] 	awid; 		// 쓰기 트랜잭션 ID
	logic [ADDR_WIDTH-1:0] 	awaddr; 	// 쓰기 시작 주소
	logic [7:0] 			awlen; 		// 버스트 길이-1
	logic [2:0] 			awsize;		// beat 바이트 수의 log2
	logic [1:0] 			awburst; 	// 버스트 타입(INCR/…)
	logic 					awvalid; 	// 주소 유효
	logic 					awready; 	// 주소 수락
  
	// Write Data
  	logic [DATA_WIDTH-1:0] 	 wdata; 	// 쓰기 데이터
	logic [DATA_WIDTH/8-1:0] wstrb; 	// 바이트 유효 마스크
	logic 					 wlast; 	// 마지막 beat 표시
	logic 					 wvalid; 	// 데이터 유효
	logic 					 wready; 	// 데이터 수락
  
  	// Write Resp
  	logic [ID_WIDTH-1:0] bid; 	 // 응답 ID
 	logic [1:0] 		 bresp;  // 응답 코드
  	logic 				 bvalid; // 응답 유효
	logic 				 bready; // 응답 수락
  
	// Read Address
  	logic [ID_WIDTH-1:0] 	arid; 	 // 읽기 트랜잭션 ID
  	logic [ADDR_WIDTH-1:0] 	araddr;  // 읽기 시작 주소
  	logic [7:0] 			arlen; 	 // 버스트 길이-1
  	logic [2:0] 			arsize;  // beat 바이트 수의 log2
	logic [1:0] 			arburst; // 버스트 타입
	logic 					arvalid; // 주소 유효
	logic 					arready; // 주소 수락

  	// Read Data
	logic [ID_WIDTH-1:0] 	rid; 	// 데이터 ID
	logic [DATA_WIDTH-1:0] 	rdata; 	// 읽기 데이터
	logic [1:0] 			rresp; 	// 읽기 응답
	logic 					rlast; 	// 마지막 beat 표시
	logic 					rvalid; // 데이터 유효
	logic 					rready; // 데이터 수락
  
	// Master
	modport master (
		// write address
		output awid, awaddr, awlen, awsize, awburst, awvalid, // 마스터가 구동
		input awready, 										  // 슬레이브 수락
		// write data
		output wdata, wstrb, wlast, wvalid, 				  // 마스터 데이터 구동
		input wready, 										  // 슬레이브 수락
		// write resp
		input bid, bresp, bvalid, 							  // 슬레이브 응답 수신
		output bready, 										  // 응답 수락 의사
		// read address
		output arid, araddr, arlen, arsize, arburst, arvalid, // 마스터 주소 구동
		input arready, 										  // 슬레이브 수락
		// read data
		input rid, rdata, rresp, rlast, rvalid, 			  // 데이터 수신
		output rready, 										  // 수락 의사
		// common
		input aclk, aresetn 								  // 공통 클록/리셋
	);
  
	// Slave
	modport slave (
	// write address
	input awid, awaddr, awlen, awsize, awburst, awvalid, // 주소/속성 수신
	output awready, 									 // 수락
	// write data
	input wdata, wstrb, wlast, wvalid, 					 // 데이터 수신
	output wready, 										 // 수락
	// write resp
	output bid, bresp, bvalid,							 // 응답 제공
	input bready, 										 // 수락 수신
	// read address
	input arid, araddr, arlen, arsize, arburst, arvalid, // 주소/속성 수신
	output arready, 									 // 수락
	// read data
	output rid, rdata, rresp, rlast, rvalid,			 // 데이터/응답 제공
	input rready,										 // 수락 수신
	// common
	input aclk, aresetn 								 // 공통 클록/리셋
	);
endinterface

// ---------------------------------------------------------------
// DMA 컨트롤러 (AXI4 마스터)
// ---------------------------------------------------------------
module dma_controller (
  	input logic clk,	// 내부 클록
  	input logic resetn, // 내부 리셋(Active-Low)
  
	// 레지스터 IF
	input logic [7:0] 	reg_addr, 		// 레지스터 주소
	input logic [31:0] 	reg_wdata, 		// 쓰기 데이터
	input logic 		reg_write, 		// 쓰기 트리거
	output logic [31:0] reg_rdata, 		// 읽기 데이터
	output logic 		reg_ack, 		// 접근 ACK
  
	// AXI4 Master
	axi4_if.master m, 					// AXI 마스터 포트
  
	// 인터럽트
	output logic dma_done_int, 			// 완료 펄스(irq_en일 때)
  	output logic dma_error_int, 		// 에러 펄스(irq_en일 때)
  
	// 디버그
	output logic [3:0] dbg_state, 		// FSM 상태 관측
	output logic [7:0] dbg_burst_len,	// 설정된 버스트 길이-1
	output logic [4:0] dbg_buf_count 	// 내부 FIFO 카운트
);
  
	typedef struct packed {		 // 제어 레지스터 비트필드
		logic [15:0] rsvd1;		 // 예약
      	logic [7:0]  channel_id; // AXI ID로 사용
      	logic [4:0]  rsvd0; 	 // 예약
		logic 		 irq_en;	 // 인터럽트 enable
		logic 		 start;		 // 시작(펄스 기대)
		logic 		 enable;	 // DMA enable
	} dma_ctrl_t;
  
	typedef struct packed {		 // 상태 레지스터 비트필드
		logic [19:0] rsvd3;		 // 예약
		logic [3:0]	 error_code; // 에러 코드
		logic [4:0]	 rsvd2;		 // 예약
		logic		 error;		 // 에러 플래그
		logic		 done;		 // 완료(sticky)
		logic		 busy;		 // 동작 중
	} dma_status_t;
  
	dma_ctrl_t	 ctrl;			 // CTRL 래치
	dma_status_t stat;			 // STAT 래치
  
	logic [31:0] src_reg, dst_reg, size_reg, bytes_done; // 설정/진행값
  
  	typedef enum logic [3:0] {	 // FSM 상태 인코딩
      	S_IDLE = 4'h0,			 // 대기
      	S_SETUP = 4'h1,			 // 버스트 길이 결정
      	S_RD_ADDR = 4'h2,		 // 읽기 주소 발행
      	S_RD_DATA = 4'h3,		 // 읽기 데이터 수신
      	S_WR_ADDR = 4'h4,		 // 쓰기 주소 발행
      	S_WR_DATA = 4'h5,		 // 쓰기 데이터 전송
      	S_WR_RESP = 4'h6,		 // BRESP 확인
      	S_NEXT = 4'h7,			 // 다음 버스트 준비
      	S_DONE = 4'h8,			 // 전체 완료
      	S_ERROR = 4'h9			 // 에러 처리
    } state_t;
  
	state_t cur, nxt;			 // 현재/다음 상태
  
	logic start_active;			 // start 펄스 래치
  	logic setup_complete;		 // SETUP 1회 실행 플래그
  
  	logic [31:0] cur_src, cur_dst; 	 // 현재 버스트의 소스/목적지
  	logic [31:0] bytes_left;		 // 남은 바이트
  	logic [7:0]  burst_len_m1;		 // 버스트 길이-1
  	logic [7:0]  r_beats_rcvd;		 // 수신한 R beats 수
  	logic [7:0]  w_beats_sent;		 // 보낸 W beats 수

	// 내부 FIFO (깊이 16)
	logic [31:0] fifo[0:15];			 // 데이터 버퍼
  	logic [3:0]  wr_ptr, rd_ptr;		 // FIFO 포인터
  	logic [4:0]  count; 				 // 보유 수(0~16)
	wire 		 buf_empty = (count==0); // 비었는지
	wire 		 buf_full = (count==16); // 가득 찼는지
  
	assign dbg_burst_len = burst_len_m1; // 디버그용 출력
  	assign dbg_buf_count = count;		 // 디버그용 출력

	wire r_fire = m.rvalid && m.rready;  // 읽기 핸드셰이크 성립
  	wire w_fire = m.wvalid && m.wready;  // 쓰기 핸드셰이크 성립
  
	// 레지스터 쓰기: 간단한 MMIO 프로토콜
	always_ff @(posedge clk or negedge resetn) begin
		if(!resetn) begin
			ctrl	 <= '0;				   // CTRL 초기화
			src_reg	 <= '0; dst_reg <= '0; // SRC/DST 초기화
			size_reg <= '0; 			   // SIZE 초기화
			reg_ack	 <= 1'b0;			   // ACK Low
		end else begin
			reg_ack <= 1'b0;			   // 기본 ACK Low
          	if (reg_write) begin		   // 쓰기 접근 시
              	reg_ack <= 1'b1;		   // 즉시 ACK
              	unique case (reg_addr)	   // 주소 디코드
					8'h00: begin
						ctrl <= dma_ctrl_t'(reg_wdata); // CTRL 업데이트
                      	$display("[%0t] DMA: Control register set - enable=%0b, start=%0b", $time, reg_wdata[0], reg_wdata[1]); // 디버깅 로그
					end
					8'h08: begin
                      	src_reg <= reg_wdata;
                      	$display("[%0t] DMA: Source address set - 0x%08X", $time, reg_wdata);
                    end
                  	8'h0C: begin
                      	dst_reg <= reg_wdata; $display("[%0t] DMA: Destination address set - 0x%08X", $time, reg_wdata);
                    end
                  	8'h10: begin
                      	size_reg <= reg_wdata; $display("[%0t] DMA: Transfer size set - %0d bytes", $time, reg_wdata);
                    end
                  	default: $display("[%0t] DMA: Invalid register address access - 0x%02X", $time, reg_addr);
				endcase
			end
		end
	end
  
	// 레지스터 읽기 MUX
	always_comb begin
		unique case (reg_addr)
			8'h00: 	 reg_rdata = {ctrl}; 		// CTRL 읽기
			8'h04: 	 reg_rdata = {stat}; 		// STAT 읽기
			8'h08: 	 reg_rdata = src_reg; 		// SRC 읽기
			8'h0C: 	 reg_rdata = dst_reg; 		// DST 읽기
			8'h10: 	 reg_rdata = size_reg; 		// SIZE 읽기
			8'h14: 	 reg_rdata = bytes_done; 	// 진행 바이트
			default: reg_rdata = 32'hDEAD_BEEF; // 보호값
		endcase
	end
  
	// 쓰기 데이터 정렬용 프리패치 레지스터
	logic [31:0] wdata_hold; // 다음 beat를 한 사이클 미리 잡아둠

	// 메인 FSM
	always_ff @(posedge clk or negedge resetn) begin
		if(!resetn) begin
			cur <= S_IDLE; dbg_state <= S_IDLE; 			// 초기 상태
			start_active <= 1'b0; 							// start 래치 초기화
			setup_complete <= 1'b0; 						// SETUP 플래그 초기화
			r_beats_rcvd <= '0; w_beats_sent <= '0; 		// 카운터 초기화
			wr_ptr <= '0; rd_ptr <= '0; count <= '0;		// FIFO 초기화
			cur_src <= '0; cur_dst <= '0; bytes_left <= '0; // 주소/잔량 초기화
			burst_len_m1 <= '0; bytes_done <= '0; 			// 길이/완료 초기화
          
			// AXI 기본 설정 (4바이트 beat, INCR 버스트)
			m.awvalid <= 1'b0; m.awaddr <= '0; m.awlen <= '0; 				 // AW 초기화
			m.awsize <= 3'b010; m.awburst<=2'b01; m.awid <= 4'h0;			 // 설정
			m.wvalid <= 1'b0; m.wdata <= '0; m.wstrb <= 4'hF; m.wlast<=1'b0; // W 초기화
			m.bready <= 1'b1;												 // BRESP 즉시 수락
			m.arvalid <= 1'b0; m.araddr <= '0; m.arlen <= '0;				 // AR 초기화
			m.arsize<=3'b010; m.arburst<=2'b01; m.arid<=4'h0;				 // 설정
			m.rready <= 1'b1;												 // RDATA 즉시 수락
          
			stat <= '0;			   // 상태 클리어
          	dma_done_int <= 1'b0;  // 인터럽트 Low
          	dma_error_int <= 1'b0; // 인터럽트 Low
          	wdata_hold <= '0; 	   // 프리패치 초기화
		end else begin
			cur <= nxt; 		   // 상태 전이
			dbg_state <= nxt; 	   // 디버그 출력
			dma_done_int <= 1'b0;  // 펄스형 신호 기본 Low
          	dma_error_int <= 1'b0;
			
			m.awvalid <= 1'b0; 	   // 주소 valid는 해당 상태에서만 1
			m.arvalid <= 1'b0; 	   // 주소 valid는 해당 상태에서만 1
			// m.wvalid/m.wdata/m.wlast는 S_WR_DATA에서만 제어
			
          	if (reg_write && (reg_addr==8'h00) && reg_wdata[1]) begin // CTRL.start=1 쓰기 시
				start_active <= 1'b1;  	// 시작 래치 세팅
				setup_complete <= 1'b0; // 새 전송 준비
				$display("[%0t] DMA: start_active set to 1", $time);
			end
          
			unique case (cur)
				S_IDLE: begin
					stat.busy <= 1'b0;						  // 대기 중 표시
                  	if (start_active) begin					  // 시작 지시 감지
						cur_src <= src_reg;					  // 소스 래치
						cur_dst <= dst_reg;					  // 목적지 래치
						bytes_left <= size_reg;				  // 남은 바이트 설정
						bytes_done <= 0;					  // 진행 바이트 0
						r_beats_rcvd <= 0; w_beats_sent <= 0; // 카운터 리셋
						wr_ptr <= 0; rd_ptr <= 0; count <= 0; // FIFO 리셋
                      
						stat.busy <= 1'b1;		 // 동작 시작
                      	stat.done <= 1'b0;		 // done 클리어
                      	stat.error <= 1'b0;		 // 에러 클리어
                      	stat.error_code <= 4'h0; // 에러 코드 초기화
                      	$display("[%0t] DMA: NEW TRANSFER STARTED - 0x%08X -> 0x%08X (%0d bytes)", $time, src_reg, dst_reg, size_reg);
                    end
				end
              
				S_SETUP: begin
					start_active <= 1'b0;		// start 펄스 소진
                  if (!setup_complete) begin 	// 1회만 실행
                      	setup_complete <= 1'b1; // 다시 실행 방지
                    	$display("[%0t] DMA: SETUP EXECUTING - bytes_left=%0d, src=0x%08X, dst=0x%08X", $time, bytes_left, cur_src, cur_dst);
                    
                    	if (bytes_left == 0) begin 							// 0바이트 전송 금지
							stat.error <= 1'b1; stat.error_code <= 4'h2; 	// 크기 오류
                          	$display("[%0t] DMA: SETUP ERROR - bytes_left is ZERO", $time);
						end else if (bytes_left >= 64) begin
							burst_len_m1 <= 8'd15; 							// 16 beats (64B)
                          	$display("[%0t] DMA: SETUP SUCCESS - 16 beats (64 bytes) for %0d bytes_left", $time, bytes_left);
						end else if (bytes_left >= 16) begin
							burst_len_m1 <= 8'd3; 							// 4 beats (16B)
                          	$display("[%0t] DMA: SETUP SUCCESS - 4 beats (16 bytes) for %0d bytes_left", $time, bytes_left);
						end else if (bytes_left >= 4) begin
							burst_len_m1 <= 8'd0; 							// 1 beat (4B)
                          	$display("[%0t] DMA: SETUP SUCCESS - 1 beat (4 bytes) for %0d bytes_left", $time, bytes_left);
						end else begin 										// 4바이트 미만은 미지원
							stat.error <= 1'b1; stat.error_code <= 4'h2;
                          	$display("[%0t] DMA: SETUP ERROR - bytes_left=%0d < 4", $time, bytes_left);
						end
						r_beats_rcvd <= 0; w_beats_sent <= 0; 				// 카운터 리셋
					end
				end
              
				S_RD_ADDR: begin
					m.arvalid <= 1'b1; 				// AR 유효
					m.araddr <= cur_src; 			// 시작 주소
					m.arlen <= burst_len_m1; 		// 길이-1
					m.arid <= ctrl.channel_id[3:0]; // ID 설정
                  	$display("[%0t] DMA: READ ADDR - 0x%08X, %0d beats", $time, cur_src, burst_len_m1+1);
				end
             
				S_RD_DATA: begin
                  	if (r_fire) begin 						// R beat 수신 시
						fifo[wr_ptr] <= m.rdata; 			// FIFO 적재
						wr_ptr <= wr_ptr + 1; 				// WR 포인터++
						count <= count + 1; 				// 보유 수++
						r_beats_rcvd <= r_beats_rcvd + 1; 	// 수신 카운트
						cur_src <= cur_src + 4; 			// 소스 주소 증가
						bytes_left <= bytes_left - 4; 		// 남은 바이트 감소
						bytes_done <= bytes_done + 4; 		// 진행 바이트 증가
						$display("[%0t] DMA: READ DATA - 0x%08X (beat %0d/%0d)", $time, m.rdata, r_beats_rcvd+1, burst_len_m1+1);
					end
				end
         
				S_WR_ADDR: begin
					m.awvalid <= 1'b1; 				// AW 유효
					m.awaddr <= cur_dst; 			// 시작 주소
					m.awlen <= burst_len_m1; 		// 길이-1
					m.awid <= ctrl.channel_id[3:0]; // ID 설정
                  	$display("[%0t] DMA: WRITE ADDR - 0x%08X, %0d beats", $time, cur_dst, burst_len_m1+1);
				end
         
				// 쓰기 데이터: 첫 사이클 정렬 + 한 사이클 앞 프리패치
				S_WR_DATA: begin
                  	if (!m.wvalid && !buf_empty) begin 			   // 전송 시작(유휴 → 활성)
                    	wdata_hold <= fifo[rd_ptr + 1]; 		   // 다음 데이터 미리 보관
                    	m.wdata <= fifo[rd_ptr]; 				   // 현재 데이터 출력
						m.wvalid <= 1'b1;  						   // 유효 올림
                      	m.wlast <= (w_beats_sent == burst_len_m1); // 마지막 여부
					end
                  	else if (m.wvalid) begin 						// 전송 진행 중
                      	m.wdata <= wdata_hold; 						// 보관분을 내보냄
                    	m.wlast <= (w_beats_sent == burst_len_m1); 	// 마지막 여부
					end
					else begin
						m.wlast <= 1'b0; 							// 유휴 시 last=0
                    end
                  
                  	if (w_fire) begin 						// W beat 송신 성립
                      	rd_ptr <= rd_ptr + 1; 				// RD 포인터++
                      	count <= count - 1; 				// 보유 수--
                      	cur_dst <= cur_dst + 4; 			// 목적지 주소 증가
						w_beats_sent <= w_beats_sent + 1; 	// 송신 카운트++
                      
                      	if (w_beats_sent != burst_len_m1) 	// 마지막 전이면
                        	wdata_hold <= fifo[rd_ptr + 2]; // 다음 다음 데이터 프리패치
                      
                      	if (w_beats_sent == burst_len_m1) 	// 마지막 beat 직후
							m.wvalid <= 1'b0; 				// wvalid 내림 (RESP로 이동)
						$display("[%0t] DMA: WRITE DATA - 0x%08X -> 0x%08X (beat %0d/%0d)", $time, m.wdata, cur_dst, w_beats_sent+1, burst_len_m1+1);
					end
                end

				S_WR_RESP: begin
					m.bready <= 1'b1; 					// BRESP 즉시 수락
					if (m.bvalid && m.bready) begin 	// 응답 수신
						if (m.bresp != 2'b00) begin 	// 에러 응답
							stat.error <= 1'b1; 		// 에러 표시
							stat.error_code <= 4'h3; 	// 코드 설정
                          	$display("[%0t] DMA: WRITE ERROR - BRESP=%b", $time, m.bresp);
						end else begin 					// OKAY 응답
                          	if (bytes_left == 0) begin 	// 더 남은 바이트 없으면
								stat.done <= 1'b1; 		// 완료(sticky)
								stat.busy <= 1'b0; 		// 편의상 busy 내림
							end
							$display("[%0t] DMA: WRITE COMPLETE - bytes_left=%0d", $time, bytes_left);
						end
					end
				end
              
				S_NEXT: begin
					r_beats_rcvd <= 0; 		// 카운터 리셋
                  	w_beats_sent <= 0; 		// 카운터 리셋
                  	setup_complete <= 1'b0; // 다음 SETUP 허용
                  	$display("[%0t] DMA: NEXT BURST - %0d bytes remaining", $time, bytes_left);
				end
              
				S_DONE: begin
					stat.busy <= 1'b0; 			 // 동작 종료
                  	stat.done <= 1'b1; 			 // 완료 유지
                  	dma_done_int <= ctrl.irq_en; // IRQ enable 시 펄스
                  	$display("[%0t] DMA: TRANSFER COMPLETED - Total %0d bytes", $time, bytes_done);
				end

              	S_ERROR: begin
					stat.busy <= 1'b0; 				// 중단
					stat.error <= 1'b1; 			// 에러 유지
                  	dma_error_int <= ctrl.irq_en; 	// 에러 IRQ 펄스
                  	$display("[%0t] DMA: ERROR STATE - code=0x%0h", $time, stat.error_code);
				end
              
              	default: ; // 방어적 기본
			endcase
		end
	end
  
	// 다음 상태 조합 논리
	always_comb begin
		nxt = cur; // 기본 유지
		unique case (cur)
			S_IDLE: begin
            	$display("[%0t] DMA: IDLE check - start_active=%0b, size_reg=%0d", $time, start_active, size_reg);
              	if (start_active) begin 	// 시작 지시
					if (size_reg==0) begin 	// 사이즈 0 → 에러
                    	$display("[%0t] DMA: IDLE -> ERROR (size=0)", $time);
						nxt = S_ERROR;
					end else begin 			// 정상 → SETUP
                    	$display("[%0t] DMA: IDLE -> SETUP (size=%0d)", $time, size_reg);
						nxt = S_SETUP;
					end
				end
			end
          
			S_SETUP: if (setup_complete) begin
              	if (stat.error)
                  	nxt = S_ERROR;
              	else
                  	nxt = S_RD_ADDR;
            end 					// 설정 끝나면 RD_ADDR
          
			S_RD_ADDR: if (m.arvalid && m.arready)
              	nxt = S_RD_DATA; 	// AR 성립 → RD_DATA
          
			S_RD_DATA: if (r_fire && (r_beats_rcvd==burst_len_m1))
              	nxt = S_WR_ADDR; 	// 마지막 read beat → WR_ADDR
          
			S_WR_ADDR: if (m.awvalid && m.awready)
              	nxt = S_WR_DATA; 	// AW 성립 → WR_DATA

          	S_WR_DATA: if (w_fire && (w_beats_sent == burst_len_m1))
              	nxt = S_WR_RESP; 	// 마지막 write beat → RESP
          
			S_WR_RESP: if (m.bvalid && m.bready) begin
				if (stat.error)
                  	nxt = S_ERROR; 	// 에러이면 ERROR
				else if (bytes_left>0)
                  	nxt = S_NEXT; 	// 남으면 NEXT
				else
                  	nxt = S_DONE; 	// 없으면 DONE
			end

          	S_NEXT: nxt = S_SETUP; 	// 반복
          
			S_DONE: nxt = S_IDLE; 	// 완료 후 대기
          
          	S_ERROR: if (start_active) nxt = S_IDLE; // 재시도 허용
          
			default: nxt = S_IDLE; 	// 방어
		endcase
	end
endmodule

// ---------------------------------------------------------------
// DDR 컨트롤러 (AXI4 슬레이브)
// ---------------------------------------------------------------
module ddr_controller (axi4_if.slave axi); 	// 인터페이스를 슬레이브로 사용
	logic [31:0] mem [0:1023]; 				// 4KB 메모리 모델(워드 배열)
  
	localparam int R_LAT = 3; 				// 읽기 초기 지연 사이클 수
	logic rd_active; 						// 읽기 진행 플래그
	logic [31:0] rd_addr; 					// 현재 읽기 주소
	logic [7:0] rd_len; 					// 요청된 버스트 길이-1
	logic [7:0] rd_cnt; 					// 보낸 beat 수
	logic [2:0] rd_lat; 					// 초기 지연 카운터
	logic [3:0] rd_id_reg; 					// 읽기 ID 래치
  
	logic wr_active; 						// 쓰기 진행 플래그
	logic [31:0] wr_addr; 					// 현재 쓰기 주소
	logic [7:0] wr_len; 					// 요청된 버스트 길이-1
	logic [7:0] wr_cnt; 					// 받은 beat 수
	logic [3:0] wr_id_reg; 					// 쓰기 ID 래치
  
	logic bvalid_reg; 						// 내부 BRESP valid
	logic [1:0] bresp_reg; 					// 내부 BRESP 코드
	logic [3:0] bid_reg; 					// 내부 BRESP ID
  
	logic r_valid_now; 						// 이번 사이클 rvalid 생성 여부
	logic r_fire; 							// rvalid & rready 핸드셰이크 성립
  
	assign axi.rresp = 2'b00; 				// 읽기 응답은 항상 OKAY
	assign axi.bresp = bresp_reg; 			// 쓰기 응답 코드 연결
	assign axi.bid = bid_reg; 				// 쓰기 응답 ID 연결
  
  	assign axi.arready = (!rd_active); 					// 읽기 유휴 시 AR 수락
	assign axi.awready = (!wr_active) && !bvalid_reg; 	// 쓰기 유휴/응답없음 시 AW 수락
	assign axi.wready = wr_active; 						// WR 진행 중에만 데이터 수락
  
	always_ff @(posedge axi.aclk or negedge axi.aresetn) begin // 클록/리셋
      	if (!axi.aresetn) begin 				// 비동기 리셋
          	for (int i=0; i<64; i++) 
				mem[i] <= 32'hCAFE_0000 + i; 	// 초기 패턴
			for (int j=64; j<1024; j++)
              	mem[j] <= 32'h0; 				// 나머지 0
			rd_active <= 1'b0; rd_addr <= '0; rd_len <= '0; rd_cnt <= '0; rd_lat <= '0; rd_id_reg <= '0; // RD 초기화
			wr_active <= 1'b0; wr_addr <= '0; wr_len <= '0; wr_cnt <= '0; wr_id_reg <= '0; 				 // WR 초기화
			axi.rvalid <= 1'b0; axi.rlast <= 1'b0; axi.rid <= '0; axi.rdata <= '0; 						 // R채널 초기화
			bvalid_reg <= 1'b0; bresp_reg <= 2'b00; bid_reg <= '0; 										 // B채널 초기화
		end else begin
          	if (axi.arvalid && axi.arready) begin // AR 수락
              	rd_active <= 1'b1; 		// 읽기 시작
              	rd_addr <= axi.araddr; 	// 시작 주소 래치
              
              	rd_len <= axi.arlen; 	// 길이-1 래치
              	rd_cnt <= '0; 			// 카운터 초기화
              
              	rd_lat <= R_LAT[2:0]; 	// 초기 지연 설정
              	rd_id_reg <= axi.arid; 	// ID 래치
			end
          
          	r_valid_now = rd_active && (rd_lat==0); // 지연 후 rvalid 생성
			axi.rvalid <= r_valid_now; 				// rvalid 구동
			axi.rlast <= 1'b0; 						// 기본 last=0
			r_fire = r_valid_now && axi.rready; 	// 핸드셰이크 성립 여부
          
          	if (rd_active) begin 					 // 읽기 진행 중
              	if (rd_lat != 0) begin 				 // 아직 지연 단계
                  	rd_lat <= rd_lat - 1; 			 // 지연 카운트다운
                end else begin 						 // 데이터 출력 단계
					axi.rid <= rd_id_reg; 			 // ID 출력
                  	axi.rdata <= mem[rd_addr[11:2]]; // 워드 주소로 읽기
                  
                  	if (r_fire) begin 				 // 전송 성립 시
						rd_addr <= rd_addr + 4;		 // 다음 워드
                      	if (rd_cnt == rd_len) begin  // 마지막 beat면
							axi.rlast <= 1'b1; 		 // last=1
							rd_active <= 1'b0;		 // 읽기 종료
						end
						rd_cnt <= rd_cnt + 1;		 // 보낸 수 증가
					end
				end
			end
          
          	if (axi.awvalid && axi.awready) begin // AW 수락
              	wr_active <= 1'b1;				  // 쓰기 시작
              	wr_addr <= axi.awaddr;			  // 시작 주소 래치
              
              	wr_len <= axi.awlen;			  // 길이-1 래치
              	wr_cnt <= '0;				 	  // 카운터 초기화
              
              	wr_id_reg <= axi.awid;			  // ID 래치
			end
          
          	if (wr_active && axi.wvalid && axi.wready) begin // W 데이터 수신
              	mem[wr_addr[11:2]] <= axi.wdata;			 // 메모리 기록
              	wr_addr <= wr_addr + 4;						 // 다음 워드 주소
            	if (axi.wlast || (wr_cnt==wr_len)) begin	 // 마지막 beat 판단
					wr_active <= 1'b0;						 // 쓰기 종료
					bvalid_reg <= 1'b1;						 // BRESP 준비
					bresp_reg <= 2'b00;						 // OKAY
					bid_reg <= wr_id_reg;					 // 응답 ID
				end
				wr_cnt <= wr_cnt + 1;						 // 받은 수 증가
			end

          	if (bvalid_reg && axi.bready) begin				 // BRESP 수락되면
              	bvalid_reg <= 1'b0;							 // 응답 완료
			end
		end
	end
  
  	assign axi.bvalid = bvalid_reg;							 // BRESP valid 외부 연결
  
endmodule