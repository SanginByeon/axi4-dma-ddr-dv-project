// ============================================================================
// dma_controller.sv - AXI4 DMA Controller (DUT)
//
// - MMIO로 설정된 SRC, DST, SIZE에 따라 메모리 복사 수행.
// - AXI4 read burst로 수신한 데이터를 내부 FIFO에 저장한 후 write burst로 전송.
// - 전송 상태와 오류 정보를 MMIO register 및 interrupt로 제공.
// - Baseline design.sv의 DMA controller를 동작 변경 없이 별도 파일로 분리.
//
// [Bug Fix]
// - AXI4 W payload 갱신 조건 오류: WREADY 확인 없이 WVALID만으로 다음 payload를 출력하는 문제 수정.
// - FIFO prefetch 종료 조건 오류: 후속 beat가 없는데도 현재 burst 범위 밖의 data를 prefetch하는 문제 수정.
// - BRESP 오류 상태 전이 조건 오류: 이전 stat.error 값 참조로 S_DONE에 잘못 전이하는 문제 수정.
// ============================================================================

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
						if (m.wready) begin 							// handshake 성립 시에만 다음 beat 출력
							m.wdata <= wdata_hold; 					// 보관분을 내보냄
							m.wlast <= (w_beats_sent == burst_len_m1); // 마지막 여부
						end
					end
					else begin
						m.wlast <= 1'b0; 							// 유휴 시 last=0
                    end
                  
                  	if (w_fire) begin 						// W beat 송신 성립
                      	rd_ptr <= rd_ptr + 1; 				// RD 포인터++
                      	count <= count - 1; 				// 보유 수--
                      	cur_dst <= cur_dst + 4; 			// 목적지 주소 증가
						w_beats_sent <= w_beats_sent + 1; 	// 송신 카운트++
                      
						if ((w_beats_sent + 1) < burst_len_m1) // 이후 prefetch가 필요한 경우
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
				if (m.bresp != 2'b00)
					nxt = S_ERROR; 	// BRESP 오류이면 ERROR
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
